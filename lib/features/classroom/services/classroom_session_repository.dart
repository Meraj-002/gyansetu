import 'dart:convert';

import '../../../core/utils/app_logger.dart';
import '../../../services/storage/secure_storage_service.dart';
import '../models/classroom_session.dart';

/// Where live sessions are kept.
///
/// Sessions are written to the device as they run, not only when they end: a
/// teacher who backgrounds the app mid-lesson, or whose phone kills the
/// process, must not lose what the class already said.
abstract interface class ClassroomSessionRepository {
  /// Writes the session as it stands. Called after every completed turn.
  Future<void> save(ClassroomSession session);

  Future<ClassroomSession?> byId(String sessionId);

  /// A session that was started and never ended, so it can be offered back.
  Future<ClassroomSession?> unfinishedFor(String lessonId);

  Future<List<ClassroomSession>> recent({int limit = 10});

  Future<void> delete(String sessionId);
}

/// Sessions in the app's existing secure store, newest kept, oldest dropped.
class LocalClassroomSessionRepository implements ClassroomSessionRepository {
  LocalClassroomSessionRepository(this._storage, {this.maxSessions = 20});

  static const String _key = 'classroom.sessions';

  final SecureStorageService _storage;

  /// Bounded so a term of teaching does not grow without limit on a phone with
  /// 2 GB of RAM and little free storage.
  final int maxSessions;

  Map<String, ClassroomSession>? _cache;

  Future<Map<String, ClassroomSession>> _load() async {
    final Map<String, ClassroomSession>? held = _cache;
    if (held != null) return held;

    final String? raw = await _storage.read(_key);
    if (raw == null || raw.isEmpty) {
      return _cache = <String, ClassroomSession>{};
    }
    try {
      final Map<String, dynamic> decoded =
          jsonDecode(raw) as Map<String, dynamic>;
      return _cache = <String, ClassroomSession>{
        for (final MapEntry<String, dynamic> e in decoded.entries)
          e.key: ClassroomSession.fromJson(e.value as Map<String, dynamic>),
      };
    } on Object catch (error) {
      AppLogger.error('classroom sessions could not be read', error: error);
      return _cache = <String, ClassroomSession>{};
    }
  }

  Future<void> _flush(Map<String, ClassroomSession> values) async {
    _cache = values;
    await _storage.write(
      _key,
      jsonEncode(<String, dynamic>{
        for (final MapEntry<String, ClassroomSession> e in values.entries)
          e.key: e.value.toJson(),
      }),
    );
  }

  @override
  Future<void> save(ClassroomSession session) async {
    final Map<String, ClassroomSession> values =
        Map<String, ClassroomSession>.from(await _load());
    values[session.sessionId] = session;

    while (values.length > maxSessions) {
      // Oldest by start time, so an old finished session goes before a live
      // one that merely happens to have been inserted first.
      final String oldest = values.entries
          .reduce(
            (MapEntry<String, ClassroomSession> a,
                    MapEntry<String, ClassroomSession> b) =>
                a.value.startedAt.isBefore(b.value.startedAt) ? a : b,
          )
          .key;
      if (oldest == session.sessionId) break;
      values.remove(oldest);
    }

    await _flush(values);
  }

  @override
  Future<ClassroomSession?> byId(String sessionId) async =>
      (await _load())[sessionId];

  @override
  Future<ClassroomSession?> unfinishedFor(String lessonId) async {
    final List<ClassroomSession> open = (await _load())
        .values
        .where(
          (ClassroomSession s) =>
              s.lessonId == lessonId && !s.completed && s.turns.isNotEmpty,
        )
        .toList()
      ..sort(
        (ClassroomSession a, ClassroomSession b) =>
            b.startedAt.compareTo(a.startedAt),
      );
    return open.isEmpty ? null : open.first;
  }

  @override
  Future<List<ClassroomSession>> recent({int limit = 10}) async {
    final List<ClassroomSession> all = (await _load()).values.toList()
      ..sort(
        (ClassroomSession a, ClassroomSession b) =>
            b.startedAt.compareTo(a.startedAt),
      );
    return all.take(limit).toList(growable: false);
  }

  @override
  Future<void> delete(String sessionId) async {
    final Map<String, ClassroomSession> values =
        Map<String, ClassroomSession>.from(await _load());
    values.remove(sessionId);
    await _flush(values);
  }
}

/// Sessions in memory, for tests.
class InMemoryClassroomSessionRepository
    implements ClassroomSessionRepository {
  final Map<String, ClassroomSession> values = <String, ClassroomSession>{};

  int saveCalls = 0;

  @override
  Future<void> save(ClassroomSession session) async {
    saveCalls++;
    values[session.sessionId] = session;
  }

  @override
  Future<ClassroomSession?> byId(String sessionId) async => values[sessionId];

  @override
  Future<ClassroomSession?> unfinishedFor(String lessonId) async {
    for (final ClassroomSession session in values.values) {
      if (session.lessonId == lessonId && !session.completed) return session;
    }
    return null;
  }

  @override
  Future<List<ClassroomSession>> recent({int limit = 10}) async =>
      values.values.take(limit).toList();

  @override
  Future<void> delete(String sessionId) async => values.remove(sessionId);
}
