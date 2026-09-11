// ignore_for_file: prefer_initializing_formals
// Private fields cannot be initialising formals: a named parameter may not
// start with an underscore.
import '../../../core/utils/app_logger.dart';
import '../../../data/mock_lessons.dart';
import '../../../models/lesson.dart';
import '../../../services/storage/secure_storage_service.dart';
import '../../../services/sync/synced_catalog_store.dart';
import '../../setup/models/classroom_setup.dart';

/// The lesson catalogue.
///
/// One repository serves the library, the dashboard and lesson detail, so the
/// same lesson id always resolves to the same lesson.
abstract interface class LessonRepository {
  Future<List<Lesson>> lessons();

  Future<Lesson?> lessonById(String id);

  /// The lesson planned for [on] given the teacher's classroom, or null when
  /// nothing fits.
  Future<Lesson?> lessonForToday(ClassroomSetup classroom, {DateTime? on});

  /// Whether the lesson's content is on this device.
  Future<bool> isAvailableOffline(String lessonId);
}

/// Per-device lesson progress.
abstract interface class LessonProgressRepository {
  /// 0..100 for every lesson that has any progress.
  Future<Map<String, int>> all();

  Future<int> percentFor(String lessonId);

  /// Recorded by lesson detail as the teacher works through a lesson.
  Future<void> setPercent(String lessonId, int percent);
}

/// Which lessons this device holds content for.
abstract interface class LessonDownloadRepository {
  Future<Set<String>> downloadedIds();

  Future<void> markDownloaded(String lessonId);

  Future<void> remove(String lessonId);
}

/// Catalogue backed by the bundled prototype dataset.
///
/// The catalogue itself is read-only here; progress and download state live in
/// their own repositories because they belong to the device rather than to the
/// catalogue.
class LocalLessonRepository implements LessonRepository {
  LocalLessonRepository({
    List<Lesson>? catalogue,
    required LessonDownloadRepository downloads,
  })  : _catalogue = catalogue ?? MockLessons.all(),
        _downloads = downloads;

  final List<Lesson> _catalogue;
  final LessonDownloadRepository _downloads;

  @override
  Future<List<Lesson>> lessons() async => List<Lesson>.unmodifiable(_catalogue);

  @override
  Future<Lesson?> lessonById(String id) async {
    for (final Lesson lesson in _catalogue) {
      if (lesson.id == id) return lesson;
    }
    return null;
  }

  @override
  Future<Lesson?> lessonForToday(
    ClassroomSetup classroom, {
    DateTime? on,
  }) async =>
      todayFrom(_catalogue, classroom, on: on);

  /// The lesson planned for [on] from a catalogue, for the teacher's classroom.
  ///
  /// Shared with [PreferredSyncedLessonRepository] so "today's lesson" reads
  /// the same way from whichever catalogue is in use.
  static Lesson? todayFrom(
    List<Lesson> catalogue,
    ClassroomSetup classroom, {
    DateTime? on,
  }) {
    final List<Lesson> candidates = catalogue
        .where((Lesson l) =>
            l.classNumber == classroom.classLevel &&
            classroom.subjects.contains(l.subject))
        .toList()
      ..sort((Lesson a, Lesson b) => a.lessonOrder.compareTo(b.lessonOrder));

    if (candidates.isEmpty) return null;

    // Rotates by the day of the month so the dashboard is not identical every
    // morning. A planner will replace this.
    final DateTime day = on ?? DateTime.now();
    return candidates[day.day % candidates.length];
  }

  @override
  Future<bool> isAvailableOffline(String lessonId) async =>
      (await _downloads.downloadedIds()).contains(lessonId);
}

/// The catalogue default every screen builds unless a test hands its own in.
///
/// Prefers the synchronized backend catalogue whenever a pull has cached one;
/// otherwise falls back to the bundled [LocalLessonRepository] catalogue. The
/// synced store is secure storage on this device — reading it is never a
/// network call — so this is safe on first install, offline, and with the
/// backend down.
class PreferredSyncedLessonRepository implements LessonRepository {
  PreferredSyncedLessonRepository({
    required SyncedCatalogStore synced,
    required LessonRepository fallback,
  })  : _synced = synced,
        _fallback = fallback;

  final SyncedCatalogStore _synced;
  final LessonRepository _fallback;

  /// The synced catalogue only when a pull actually stored lessons in it. An
  /// empty store — the sync has never run, the server returned an empty
  /// catalogue, or the cached bytes cannot be read — is treated the same way:
  /// fall back. This is deliberate: an empty backend catalogue must never make
  /// the library unusable.
  Future<List<Lesson>> _effective() async {
    final List<Lesson> cached = await _synced.lessons();
    if (cached.isEmpty) return const <Lesson>[];
    return cached;
  }

  @override
  Future<List<Lesson>> lessons() async {
    final List<Lesson> cached = await _effective();
    if (cached.isNotEmpty) return List<Lesson>.unmodifiable(cached);
    return _fallback.lessons();
  }

  @override
  Future<Lesson?> lessonById(String id) async {
    for (final Lesson lesson in await _effective()) {
      if (lesson.id == id) return lesson;
    }
    // A synced catalogue is preferred, not exclusive: a lesson that exists
    // only in the bundled set (a deep link, a saved classroom) still resolves.
    return _fallback.lessonById(id);
  }

  @override
  Future<Lesson?> lessonForToday(
    ClassroomSetup classroom, {
    DateTime? on,
  }) async {
    final List<Lesson> cached = await _effective();
    if (cached.isNotEmpty) {
      return LocalLessonRepository.todayFrom(cached, classroom, on: on);
    }
    return _fallback.lessonForToday(classroom, on: on);
  }

  @override
  Future<bool> isAvailableOffline(String lessonId) =>
      _fallback.isAvailableOffline(lessonId);
}

/// Builds the catalogue a screen defaults to when no repository is injected:
/// the synchronized backend catalogue when one is cached, the bundled
/// prototype otherwise. Every screen keeps its default construction to one
/// line, so a future catalogue source change happens here alone.
LessonRepository defaultLessonRepository({
  required SecureStorageService storage,
  required LessonDownloadRepository downloads,
}) =>
    PreferredSyncedLessonRepository(
      synced: SyncedCatalogStore(storage),
      fallback: LocalLessonRepository(downloads: downloads),
    );

/// Progress kept in the app's secure store.
///
/// Small and per-teacher, so it lives beside the session rather than in its own
/// database. It moves into the lessons table when one exists.
class LocalLessonProgressRepository implements LessonProgressRepository {
  LocalLessonProgressRepository(this._storage, {Map<String, int>? seed})
      : _seed = seed;

  static const String _key = 'lessons.progress';

  final SecureStorageService _storage;
  final Map<String, int>? _seed;

  Map<String, int>? _cache;

  @override
  Future<Map<String, int>> all() async {
    final Map<String, int>? cached = _cache;
    if (cached != null) return cached;

    final String? raw = await _storage.read(_key);
    if (raw == null || raw.isEmpty) {
      return _cache = Map<String, int>.from(_seed ?? MockLessons.seedProgress());
    }
    try {
      return _cache = _decode(raw);
    } on Object catch (error) {
      AppLogger.error('lesson progress could not be read', error: error);
      return _cache = <String, int>{};
    }
  }

  @override
  Future<int> percentFor(String lessonId) async =>
      (await all())[lessonId] ?? 0;

  @override
  Future<void> setPercent(String lessonId, int percent) async {
    final Map<String, int> current = Map<String, int>.from(await all());
    current[lessonId] = percent.clamp(0, 100);
    _cache = current;
    await _storage.write(_key, _encode(current));
  }

  static String _encode(Map<String, int> value) =>
      value.entries.map((MapEntry<String, int> e) => '${e.key}=${e.value}').join(';');

  static Map<String, int> _decode(String raw) => <String, int>{
        for (final String pair in raw.split(';'))
          if (pair.contains('='))
            pair.split('=').first: int.tryParse(pair.split('=').last) ?? 0,
      };
}

/// Download state kept in the app's secure store.
class LocalLessonDownloadRepository implements LessonDownloadRepository {
  LocalLessonDownloadRepository(this._storage, {Set<String>? seed})
      : _seed = seed;

  static const String _key = 'lessons.downloaded';

  final SecureStorageService _storage;
  final Set<String>? _seed;

  Set<String>? _cache;

  @override
  Future<Set<String>> downloadedIds() async {
    final Set<String>? cached = _cache;
    if (cached != null) return cached;

    final String? raw = await _storage.read(_key);
    if (raw == null || raw.isEmpty) {
      return _cache = Set<String>.from(_seed ?? MockLessons.seedDownloaded());
    }
    return _cache = raw.split(';').where((String s) => s.isNotEmpty).toSet();
  }

  @override
  Future<void> markDownloaded(String lessonId) async {
    final Set<String> ids = Set<String>.from(await downloadedIds())
      ..add(lessonId);
    _cache = ids;
    await _storage.write(_key, ids.join(';'));
  }

  @override
  Future<void> remove(String lessonId) async {
    final Set<String> ids = Set<String>.from(await downloadedIds())
      ..remove(lessonId);
    _cache = ids;
    await _storage.write(_key, ids.join(';'));
  }
}
