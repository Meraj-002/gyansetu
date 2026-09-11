// ignore_for_file: prefer_initializing_formals
// Private fields cannot be initialising formals: a named parameter may not
// start with an underscore.
import 'dart:convert';

import '../../core/utils/app_logger.dart';
import '../downloads/local_content_io.dart';
import '../downloads/offline_pack_source.dart';
import 'phrasebook_index/phrasebook_index_defs.dart';
import 'text_translation_service.dart';

/// The language pair the offline phrasebook covers (teaching medium -> mother
/// tongue and back), as locale ids.
const Set<String> offlineSupportedPairs = <String>{'hi-IN>sat', 'sat>hi-IN'};

/// The downloadable pack id the offline reader streams from.
const String offlinePhrasebookPackId = 'translation-hindi-santali';

/// The classroom phrase categories the phrasebook organises sentences under.
///
/// The set is the schema for the dataset: every authored line carries one of
/// these so a teacher (or a future editor) can see what a phrase is for.
enum PhrasebookCategory {
  greetings,
  classroomInstructions,
  questions,
  answers,
  encouragement,
  discipline,
  numbers,
  colors,
  bodyParts,
  family,
  food,
  schoolObjects,
  basicActions,
  learningActivities,
  safety,
  environment,
  basicMathematics,
  basicScience;

  /// A stable snake_case wire value, matching what the pack JSONL carries.
  String get wireName => name;
}

/// Where a phrasebook record's translation came from.
enum PhrasebookProvenance {
  /// Reviewed against an authoritative/sourced dataset. The record is
  /// presented as a real, checked translation.
  verifiedSource,

  /// Written for development only and NOT yet checked by a speaker. The record
  /// is clearly marked, and the UI must never present it as a verified
  /// mother-tongue translation.
  authoredDevelopment;
}

/// One entry of the phrasebook pack.
///
/// The source sentence is real wherever it comes from; [targetText] is the
/// part that must never be invented. It is null for placeholder records (the
/// source is written down, the mother-tongue form is not) and the reader never
/// answers from such a record — a placeholder is never presented as a
/// translation.
class PhrasebookRecord {
  const PhrasebookRecord({
    this.id,
    required this.sourceLanguage,
    required this.targetLanguage,
    required this.sourceText,
    required this.targetText,
    this.spokenTargetText,
    this.category,
    required this.verified,
    required this.provenance,
    this.context,
    this.dialect,
    this.version = 1,
  });

  final String? id;
  final String sourceLanguage;
  final String targetLanguage;
  final String sourceText;

  /// The mother-tongue form, or null for a placeholder record that must never
  /// be answered from.
  final String? targetText;

  /// Devanagari rendering of [targetText] for an Indic voice, when written.
  final String? spokenTargetText;

  /// True only when the record came from an authoritative source and was
  /// checked. A development record is never marked verified, and a record with
  /// no mother-tongue form can never be verified either.
  final bool verified;

  final PhrasebookCategory? category;
  final PhrasebookProvenance provenance;

  /// Optional structured metadata carried on the record (still unverified for
  /// every record in the current dataset).
  final String? context;
  final String? dialect;
  final int version;

  bool get canAnswer => targetText != null && targetText!.isNotEmpty;

  /// The pack-wire shape, exactly what the JSONL carried in.
  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'sourceLanguage': sourceLanguage,
        'targetLanguage': targetLanguage,
        'sourceText': sourceText,
        'targetText': targetText,
        'spokenText': spokenTargetText,
        'category': category?.wireName,
        'provenance': provenance.name,
        'verified': verified,
        'context': context,
        'dialect': dialect,
        'version': version,
      };

  static PhrasebookRecord? fromJson(Map<String, dynamic> json) {
    final String source = json['sourceText'] as String? ?? '';
    final String? sourceLanguage = json['sourceLanguage'] as String?;
    final String? targetLanguage = json['targetLanguage'] as String?;
    if (source.isEmpty || sourceLanguage == null || targetLanguage == null) {
      return null;
    }
    final String? target = json['targetText'] as String?;
    return PhrasebookRecord(
      id: json['id'] as String?,
      sourceLanguage: sourceLanguage,
      targetLanguage: targetLanguage,
      sourceText: source,
      targetText: (target == null || target.isEmpty) ? null : target,
      spokenTargetText: json['spokenText'] as String?,
      category: _category(json['category'] as String?),
      // Honest flags, regardless of what the file says: a record can only be
      // verified when a real authoritative source and a written mother-tongue
      // form are both present. Development records stay unverified.
      verified: (json['verified'] as bool? ?? false) &&
          target != null &&
          _provenance(json['provenance'] as String?) ==
              PhrasebookProvenance.verifiedSource,
      provenance: _provenance(json['provenance'] as String?),
      context: json['context'] as String?,
      dialect: json['dialect'] as String?,
      version: json['version'] as int? ?? 1,
    );
  }

  static PhrasebookCategory? _category(String? value) {
    if (value == null || value.isEmpty) return null;
    for (final PhrasebookCategory category in PhrasebookCategory.values) {
      if (category.name == value) return category;
    }
    return null;
  }

  static PhrasebookProvenance _provenance(String? value) {
    if (value == 'verifiedSource') {
      return PhrasebookProvenance.verifiedSource;
    }
    // "authored-development", the historical "authored", anything else: written
    // by hand and NOT yet verified against a sourced dataset.
    return PhrasebookProvenance.authoredDevelopment;
  }
}

/// Reads and answers the offline phrasebook pack.
///
/// Reads the pack file lazily, one JSONL line at a time (never the whole file
/// in memory at once). On first use it streams every line into an indexed
/// store — one row per record in SQLite on a device, so a verified phrasebook
/// of tens of thousands of lines stays off the 2 GB heap — and answers each
/// sentence with a single stored-row read.
///
/// Honest by design: it answers only sentences that actually have a written-out
/// mother-tongue form (placeholder records are skipped, never answered from),
/// marks every development entry as unreviewed, and refuses everything else
/// with [TranslationFailureReason.notConfigured] so the offline-first
/// orchestrator can fall back to the network instead of presenting a guessed
/// mother-tongue sentence to a class.
class OfflinePhrasebookTranslationService implements TextTranslationService {
  OfflinePhrasebookTranslationService({
    required OfflinePackSource source,
    LocalContentIo? io,
    PhrasebookIndexStore? indexStore,
  })  : _source = source,
        _io = io ?? deviceLocalContentIo,
        _indexStore = indexStore ?? MemoryPhrasebookIndexStore();

  final OfflinePackSource _source;
  final LocalContentIo _io;
  final PhrasebookIndexStore _indexStore;
  bool _indexed = false;

  @override
  String get modelVersion => 'offline-phrasebook-1';

  @override
  bool get isRealModel => false;

  @override
  bool get requiresNetwork => false;

  /// The absolute path of the pack on disk, or null when this platform has no
  /// writable folder or the pack is not installed.
  Future<String?> _packPath() async {
    final String? path = _source.pathForReady(offlinePhrasebookPackId);
    if (path == null) return null;
    if (!await _io.exists(path)) return null;
    final int? length = await _io.length(path);
    if (length == null || length == 0) return null;
    return path;
  }

  /// True when the pack is on disk right now. The download manager's ready gate
  /// already verified size + checksum on this exact path.
  Future<bool> isInstalled() async => await _packPath() != null;

  /// How many records are indexed for the session. Placeholders are counted
  /// too (they are stored so the reader can refuse them, never answer from
  /// them); a missing pack is 0.
  Future<int> indexedRecords() async => _indexStore.count();

  @override
  Future<bool> supportsPair(String sourceLanguage, String targetLanguage) async {
    if (!offlineSupportedPairs.contains('$sourceLanguage>$targetLanguage')) {
      return false;
    }
    return await isInstalled();
  }

  @override
  Future<TranslationResult> translate(TranslationRequest request) async {
    final String pair = '${request.sourceLanguage}>${request.targetLanguage}';
    if (!offlineSupportedPairs.contains(pair)) {
      throw TextTranslationFailure(
        TranslationFailureReason.unsupportedPair,
        'Translation between these two languages is not available offline.',
      );
    }

    if (!await isInstalled()) {
      throw const TextTranslationFailure(
        TranslationFailureReason.notConfigured,
        'The offline phrasebook for this language is not installed yet. '
            'Download it once, and this sentence can translate without a '
            'connection.',
      );
    }

    await _ensureIndexed();
    final PhrasebookRecord? entry = await _lookup(
      request.sourceLanguage,
      request.targetLanguage,
      request.sourceText,
    );
    if (entry == null || !entry.canAnswer) {
      throw const TextTranslationFailure(
        TranslationFailureReason.notConfigured,
        "This sentence isn't in the offline phrasebook yet.",
      );
    }

    return TranslationResult(
      translatedText: entry.targetText!,
      sourceLanguage: request.sourceLanguage,
      targetLanguage: request.targetLanguage,
      modelVersion: modelVersion,
      originalText: request.sourceText,
      confidence: null,
      spokenText: entry.spokenTargetText,
      // A record is only "reviewed by a speaker" when it came from a verified
      // source. Development records stay unreviewed and say so.
      reviewedBySpeaker: entry.verified,
      source: TranslationSource.phrasebook,
    );
  }

  /// Streams the pack into the index on first use, one line at a time. Each
  /// line becomes one stored row; a corrupt or placeholder line is skipped or
  /// stored (never answered) exactly as the reader always treated it.
  Future<void> _ensureIndexed() async {
    if (_indexed) return;
    final String? path = await _packPath();
    if (path == null) {
      _indexed = true;
      return;
    }
    await for (final String line in _io.readLines(path)) {
      final String trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      final PhrasebookRecord? entry = PhrasebookRecord.fromJson(
        _decodeLine(trimmed),
      );
      if (entry == null) continue;
      await _indexStore.indexRecord(
        pair: '${_locale(entry.sourceLanguage)}>${_locale(entry.targetLanguage)}',
        normalizedKey: _normalise(entry.sourceText),
        recordJson: jsonEncode(entry.toJson()),
      );
    }
    _indexed = true;
  }

  Map<String, dynamic> _decodeLine(String line) {
    try {
      return jsonDecode(line) as Map<String, dynamic>;
    } on Object catch (error) {
      AppLogger.error('a phrasebook line was unreadable', error: error);
      return <String, dynamic>{};
    }
  }

  Future<PhrasebookRecord?> _lookup(
    String sourceLanguage,
    String targetLanguage,
    String text,
  ) async {
    final String? raw = await _indexStore.lookup(
      pair: '${_locale(sourceLanguage)}>${_locale(targetLanguage)}',
      normalizedKey: _normalise(text),
    );
    if (raw == null) return null;
    try {
      return PhrasebookRecord.fromJson(
        jsonDecode(raw) as Map<String, dynamic>,
      );
    } on Object {
      return null;
    }
  }

  /// Resets the cached index (forget it) so the next translate re-reads the
  /// pack. Useful when the pack was just freshly re-downloaded.
  void forget() {
    _indexed = false;
    _indexStore.clear();
  }

  /// Folds both a bare canonical code AND the app's locale id onto the same
  /// classroom locale key: "hindi" and "hi-IN" both mean the classroom teaching
  /// medium, "santali" and "sat" both mean the mother tongue, etc.
  static String _locale(String language) {
    switch (language.toLowerCase()) {
      case 'hindi':
      case 'hi':
      case 'hi-in':
        return 'hi-IN';
      case 'santali':
      case 'sat':
        return 'sat';
      case 'english':
      case 'en':
      case 'en-in':
        return 'en-IN';
      case 'bengali':
      case 'bn':
      case 'bn-in':
        return 'bn-IN';
      case 'mundari':
      case 'unr':
        return 'unr';
      case 'ho':
      case 'hoc':
      case 'hoj':
        return 'hoc';
      default:
        return language.toLowerCase();
    }
  }

  static String _normalise(String value) => value
      .toLowerCase()
      .replaceAll(RegExp(r'[?!।,.\s]+'), ' ')
      .trim();
}