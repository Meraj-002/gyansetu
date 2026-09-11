import 'dart:convert';

import '../../core/utils/app_logger.dart';
import '../storage/secure_storage_service.dart';

/// One saved audio clip, tracked properly rather than left as a loose file.
///
/// Every field here exists so the clip can be found again, checked for
/// staleness, and cleaned up: a file on disk with no record is a leak, and a
/// record with no file is a broken promise of offline audio.
class AudioResource {
  const AudioResource({
    required this.audioResourceId,
    required this.lessonId,
    required this.localeId,
    required this.filePath,
    required this.createdAt,
    this.textHash = '',
    this.durationMs,
    this.version = 1,
  });

  factory AudioResource.fromJson(Map<String, dynamic> json) => AudioResource(
        audioResourceId: json['audioResourceId'] as String,
        lessonId: json['lessonId'] as String,
        localeId: json['localeId'] as String,
        filePath: json['filePath'] as String,
        createdAt: DateTime.parse(json['createdAt'] as String),
        textHash: json['textHash'] as String? ?? '',
        durationMs: json['durationMs'] as int?,
        version: json['version'] as int? ?? 1,
      );

  final String audioResourceId;
  final String lessonId;

  /// The language the clip is spoken in, so one lesson can hold a clip per
  /// language without them overwriting each other.
  final String localeId;

  final String filePath;

  /// Hash of the exact words this clip speaks.
  ///
  /// Part of the key, so one lesson can hold a clip per sentence and a changed
  /// sentence never plays the previous recording. Empty for a clip that speaks
  /// a whole lesson passage rather than one line.
  final String textHash;

  /// Null when the platform did not report it. The UI must not show a duration
  /// it does not have.
  final int? durationMs;

  /// Matches the translation version the clip was made from. A newer
  /// translation makes the clip stale.
  final int version;

  final DateTime createdAt;

  static String keyFor(
    String lessonId,
    String localeId, [
    String textHash = '',
  ]) =>
      '$lessonId#$localeId#$textHash';

  String get key => keyFor(lessonId, localeId, textHash);

  Map<String, dynamic> toJson() => <String, dynamic>{
        'audioResourceId': audioResourceId,
        'lessonId': lessonId,
        'localeId': localeId,
        'filePath': filePath,
        'textHash': textHash,
        'durationMs': durationMs,
        'version': version,
        'createdAt': createdAt.toIso8601String(),
      };
}

/// The index of saved audio clips.
abstract interface class AudioResourceStore {
  Future<AudioResource?> find(
    String lessonId,
    String localeId, [
    String textHash = '',
  ]);

  Future<void> save(AudioResource resource);

  Future<void> remove(
    String lessonId,
    String localeId, [
    String textHash = '',
  ]);

  Future<List<AudioResource>> all();
}

/// Keeps the index in the app's existing secure store.
///
/// The clip itself is a file; only its metadata lives here. Deliberately not a
/// second database — the app already has one storage layer and this is a
/// handful of small records.
class LocalAudioResourceStore implements AudioResourceStore {
  LocalAudioResourceStore(this._storage);

  static const String _key = 'lessons.audio.index';

  final SecureStorageService _storage;

  Map<String, AudioResource>? _cache;

  Future<Map<String, AudioResource>> _load() async {
    final Map<String, AudioResource>? held = _cache;
    if (held != null) return held;

    final String? raw = await _storage.read(_key);
    if (raw == null || raw.isEmpty) {
      return _cache = <String, AudioResource>{};
    }
    try {
      final Map<String, dynamic> decoded =
          jsonDecode(raw) as Map<String, dynamic>;
      return _cache = <String, AudioResource>{
        for (final MapEntry<String, dynamic> e in decoded.entries)
          e.key: AudioResource.fromJson(e.value as Map<String, dynamic>),
      };
    } on Object catch (error) {
      AppLogger.error('audio index could not be read', error: error);
      return _cache = <String, AudioResource>{};
    }
  }

  Future<void> _flush(Map<String, AudioResource> values) async {
    _cache = values;
    await _storage.write(
      _key,
      jsonEncode(<String, dynamic>{
        for (final MapEntry<String, AudioResource> e in values.entries)
          e.key: e.value.toJson(),
      }),
    );
  }

  @override
  Future<AudioResource?> find(
    String lessonId,
    String localeId, [
    String textHash = '',
  ]) async =>
      (await _load())[AudioResource.keyFor(lessonId, localeId, textHash)];

  @override
  Future<void> save(AudioResource resource) async {
    final Map<String, AudioResource> values =
        Map<String, AudioResource>.from(await _load());
    values[resource.key] = resource;
    await _flush(values);
  }

  @override
  Future<void> remove(
    String lessonId,
    String localeId, [
    String textHash = '',
  ]) async {
    final Map<String, AudioResource> values =
        Map<String, AudioResource>.from(await _load());
    values.remove(AudioResource.keyFor(lessonId, localeId, textHash));
    await _flush(values);
  }

  @override
  Future<List<AudioResource>> all() async =>
      (await _load()).values.toList(growable: false);
}

/// In-memory index, for tests.
class InMemoryAudioResourceStore implements AudioResourceStore {
  final Map<String, AudioResource> _values = <String, AudioResource>{};

  @override
  Future<AudioResource?> find(
    String lessonId,
    String localeId, [
    String textHash = '',
  ]) async =>
      _values[AudioResource.keyFor(lessonId, localeId, textHash)];

  @override
  Future<void> save(AudioResource resource) async =>
      _values[resource.key] = resource;

  @override
  Future<void> remove(
    String lessonId,
    String localeId, [
    String textHash = '',
  ]) async =>
      _values.remove(AudioResource.keyFor(lessonId, localeId, textHash));

  @override
  Future<List<AudioResource>> all() async => _values.values.toList();
}
