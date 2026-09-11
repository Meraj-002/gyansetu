/// One stored row of the translation cache.
///
/// Small by design: a single translated sentence plus its provenance. The whole
/// cache is never held as one blob; the store reads and writes one row at a
/// time, which is the 2 GB-device rule for this feature.
class CachedTranslationEntry {
  const CachedTranslationEntry({
    required this.key,
    required this.translatedText,
    required this.modelVersion,
    this.spokenText,
    this.confidence,
    this.reviewedBySpeaker = false,
    this.sourceName,
    this.provider,
    this.model,
    this.engineName,
    this.engineIsRealModel = false,
    this.savedAt,
  });

  final String key;
  final String translatedText;
  final String modelVersion;
  final String? spokenText;
  final double? confidence;
  final bool reviewedBySpeaker;

  /// The storing provider's `TranslationSource.name`, when it said one.
  final String? sourceName;

  final String? provider;
  final String? model;
  final String? engineName;
  final bool engineIsRealModel;

  final DateTime? savedAt;

  factory CachedTranslationEntry.fromJson(Map<String, dynamic> json) =>
      CachedTranslationEntry(
        key: json['key'] as String,
        translatedText: json['text'] as String,
        modelVersion: json['modelVersion'] as String? ?? '',
        spokenText: json['spokenText'] as String?,
        confidence: (json['confidence'] as num?)?.toDouble(),
        reviewedBySpeaker: json['reviewed'] as bool? ?? false,
        sourceName: json['source'] as String?,
        provider: json['provider'] as String?,
        model: json['model'] as String?,
        engineName: json['engineName'] as String?,
        engineIsRealModel: json['isRealModel'] as bool? ?? false,
        savedAt: json['savedAt'] == null
            ? null
            : DateTime.tryParse(json['savedAt'] as String),
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
    'key': key,
    'text': translatedText,
    'modelVersion': modelVersion,
    'spokenText': spokenText,
    'confidence': confidence,
    'reviewed': reviewedBySpeaker,
    'source': sourceName,
    'provider': provider,
    'model': model,
    'engineName': engineName,
    'isRealModel': engineIsRealModel,
    'savedAt': savedAt?.toIso8601String(),
  };
}

/// Persistent, bounded, per-row cache storage.
///
/// The 2 GB rule lives here, not in a caller: reads and writes touch only the
/// requested row, the full cache is never decoded into RAM, and trimming runs
/// oldest-first inside the store so the cache stays bounded whatever the
/// decorator does.
abstract interface class TranslationCacheStore {
  Future<CachedTranslationEntry?> read(String key);

  Future<void> write(CachedTranslationEntry entry);

  /// Keeps at most [maxEntries] rows, dropping the oldest first.
  Future<void> trim(int maxEntries);

  Future<int> count();

  /// Empties the store. Used when a cache must be invalidated wholesale.
  Future<void> clear();
}

/// In-memory store: for tests and as the honest fallback on platforms with no
/// writable local persistence. Insertion-ordered, so trimming drops the oldest
/// written row first.
class MemoryTranslationCacheStore implements TranslationCacheStore {
  final Map<String, CachedTranslationEntry> _entries =
      <String, CachedTranslationEntry>{};

  @override
  Future<CachedTranslationEntry?> read(String key) async => _entries[key];

  @override
  Future<void> write(CachedTranslationEntry entry) async {
    _entries[entry.key] = entry;
  }

  @override
  Future<void> trim(int maxEntries) async {
    while (_entries.length > maxEntries && _entries.isNotEmpty) {
      _entries.remove(_entries.keys.first);
    }
  }

  @override
  Future<int> count() async => _entries.length;

  @override
  Future<void> clear() async => _entries.clear();
}
