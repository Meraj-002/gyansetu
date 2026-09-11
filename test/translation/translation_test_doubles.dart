import 'dart:convert';

import 'package:gyan_setu_ai/services/downloads/local_content_io.dart';
import 'package:gyan_setu_ai/services/downloads/offline_pack_source.dart';
import 'package:gyan_setu_ai/services/translation/text_translation_service.dart';

/// Serves pack paths the test fixed, so the phrasebook reader never touches a
/// real download pipeline.
class FixedPackSource implements OfflinePackSource {
  FixedPackSource([this.path]);

  /// The path a verified pack lives at, or null for "not on this device".
  String? path;

  @override
  String? pathForReady(String id) => path;
}

/// An in-memory filesystem the phrasebook streams from.
///
/// A directory is a mapping from absolute path (the fixed pack path) to a
/// UTF-8 String. `readLines` splits on real newlines, exactly like the device
/// implementation.
class MemoryLocalContentIo implements LocalContentIo {
  final Map<String, String> files = <String, String>{};

  void put(String path, String content) => files[path] = content;

  @override
  Future<String?> resolveContentRoot() async => '/memory';

  @override
  Future<bool> write(String path, Stream<List<int>> bytes) async {
    final StringBuffer buffer = StringBuffer();
    await for (final List<int> chunk in bytes) {
      buffer.write(utf8.decode(chunk));
    }
    files[path] = buffer.toString();
    return true;
  }

  @override
  Future<bool> rename(String from, String to) async {
    final String? content = files.remove(from);
    if (content == null) return false;
    files[to] = content;
    return true;
  }

  @override
  Future<bool> exists(String path) async => files.containsKey(path);

  @override
  Future<int?> length(String path) async {
    final String? content = files[path];
    if (content == null) return null;
    return utf8.encode(content).length;
  }

  @override
  Stream<String> readLines(String path) async* {
    final String? content = files[path];
    if (content == null) return;
    final List<String> lines = content.split('\n');
    for (final String line in lines) {
      yield line;
    }
  }

  @override
  Future<String?> sha256(String path) async =>
      files.containsKey(path) ? 'deadbeef' : null;

  @override
  Future<int> directoryBytes(String path) async => 0;

  @override
  Future<void> delete(String path) async {
    files.remove(path);
  }
}

/// A translator whose behaviour the test dictates and whose calls are counted.
///
/// `requiresNetwork` mirrors a real provider: true for the online adapter,
/// false for on-device providers.
class RecordingTranslator implements TextTranslationService {
  RecordingTranslator({
    this.answer,
    this.failure,
    this.supported = true,
    this.requiresNetwork = false,
    this.realModel = false,
    this.version = 'recording-1',
  });

  TranslationResult? answer;
  TextTranslationFailure? failure;
  bool supported;

  @override
  bool requiresNetwork;
  bool realModel;
  String version;

  int calls = 0;
  TranslationRequest? lastRequest;

  @override
  String get modelVersion => version;

  @override
  bool get isRealModel => realModel;

  @override
  Future<bool> supportsPair(String source, String target) async => supported;

  @override
  Future<TranslationResult> translate(TranslationRequest request) async {
    calls++;
    lastRequest = request;
    final TextTranslationFailure? thrown = failure;
    if (thrown != null) throw thrown;
    final TranslationResult? given = answer;
    if (given == null) {
      throw TextTranslationFailure(
        TranslationFailureReason.failed,
        'no answer scripted',
      );
    }
    return given;
  }
}

TranslationResult offlineResult({
  String text = "Gidra'ko, kete ul menaka?",
  String? spoken = 'गिड़ाको, केते उल् मेनाका?',
}) =>
    TranslationResult(
      translatedText: text,
      sourceLanguage: 'hi-IN',
      targetLanguage: 'sat',
      modelVersion: 'offline-phrasebook-1',
      confidence: null,
      spokenText: spoken,
      source: TranslationSource.phrasebook,
    );

TranslationResult onlineResult({
  String text = "Gidra'ko, kete ul menaka?",
  String? spoken = 'गिड़ाको, केते उल् मेनाका?',
}) =>
    TranslationResult(
      translatedText: text,
      sourceLanguage: 'hi-IN',
      targetLanguage: 'sat',
      modelVersion: 'api-translate-v1',
      confidence: null,
      spokenText: spoken,
      source: TranslationSource.onlineBackend,
    );

/// One directional source/target pair for building a phrasebook fixture.
class FixtureLine {
  const FixtureLine({
    required this.sourceLanguage,
    required this.targetLanguage,
    required this.sourceText,
    required this.targetText,
    this.spokenText,
  });

  final String sourceLanguage;
  final String targetLanguage;
  final String sourceText;
  final String targetText;
  final String? spokenText;
}

/// Builds the same JSONL (one JSON object per line) the seed script ships.
String buildPhrasebook(List<FixtureLine> lines) => lines
    .map(
      (FixtureLine line) => jsonEncode(<String, dynamic>{
        'id': 'pb-test',
        'sourceLanguage': line.sourceLanguage,
        'targetLanguage': line.targetLanguage,
        'sourceText': line.sourceText,
        'targetText': line.targetText,
        'spokenText': line.spokenText,
        'provenance': 'authored',
        'reviewedBySpeaker': false,
      }),
    )
    .join('\n');