// ignore_for_file: prefer_initializing_formals
// Private fields cannot be initialising formals: a named parameter may not
// start with an underscore.
import 'dart:async';

import '../../../core/utils/result.dart';
import '../../../services/api/api_client.dart';
import '../../../services/api/api_endpoints.dart';
import '../../auth/models/teacher_account.dart';
import '../../auth/services/auth_session_store.dart';
import '../../setup/models/classroom_setup.dart';
import '../../setup/services/classroom_setup_repository.dart';

/// The teacher's canonical identity: their account plus their classroom.
///
/// Exactly what the profile screen renders and what an offline session keeps.
class TeacherIdentity {
  const TeacherIdentity({required this.account, required this.classroom});

  final TeacherAccount? account;
  final ClassroomSetup? classroom;
}

/// How the profile reads and writes the teacher's identity.
///
/// The screen talks to this, never to the network or the stores directly.
abstract interface class TeacherIdentityRepository {
  /// The identity known on this device, hydrated from the server when a token
  /// exists and the server can be reached. Never throws: an unreachable or
  /// rejecting server simply yields the cached local snapshot.
  Future<TeacherIdentity> load();

  /// Renames the teacher. The local account is the source of truth and is
  /// always written; when a token exists the change is also pushed to the
  /// server. Returns false only when the local write itself failed.
  Future<bool> updateDisplayName(String newName);
}

/// The device is the whole story: no token, no network call, ever.
class LocalTeacherIdentityRepository implements TeacherIdentityRepository {
  LocalTeacherIdentityRepository({
    required this.session,
    required this.classrooms,
  });

  final AuthSessionStore session;
  final ClassroomSetupRepository classrooms;

  @override
  Future<TeacherIdentity> load() async {
    final TeacherAccount? account = await session.account();
    final ClassroomSetup? classroom = account == null
        ? null
        : await classrooms.load(account.id);
    return TeacherIdentity(account: account, classroom: classroom);
  }

  @override
  Future<bool> updateDisplayName(String newName) =>
      session.updateAccount(displayName: newName);
}

/// Talks to the FastAPI server for canonical identity when there is a token.
///
/// ``/auth/me`` returns the account plus the classroom fields the device pushed
/// through sync. Those hydrate the local caches, but only ever *overwrite* a
/// local classroom that is not themselves waiting to sync — a teacher's pending
/// edits are never clobbered by the server.
class FastApiTeacherIdentityRepository implements TeacherIdentityRepository {
  FastApiTeacherIdentityRepository({
    required ApiClient api,
    required AuthSessionStore session,
    required ClassroomSetupRepository classrooms,
  })  : _api = api,
        _session = session,
        _classrooms = classrooms;

  final ApiClient _api;
  final AuthSessionStore _session;
  final ClassroomSetupRepository _classrooms;

  @override
  Future<TeacherIdentity> load() async {
    final TeacherAccount? localAccount = await _session.account();
    final String? teacherId = localAccount?.id;
    final ClassroomSetup? localClassroom = teacherId == null
        ? null
        : await _classrooms.load(teacherId);

    // No token means no server identity is available (offline sign-in, or a
    // device that never signed in online). The cached snapshot is the answer.
    final String? token = await _session.accessToken();
    if (token == null || token.isEmpty) {
      return TeacherIdentity(account: localAccount, classroom: localClassroom);
    }

    switch (await _api.get(ApiEndpoints.me)) {
      case Ok<Map<String, dynamic>>(:final Map<String, dynamic> value):
        return await _hydrated(localAccount, localClassroom, value);
      case Err<Map<String, dynamic>>():
        return TeacherIdentity(account: localAccount, classroom: localClassroom);
    }
  }

  Future<TeacherIdentity> _hydrated(
    TeacherAccount? localAccount,
    ClassroomSetup? localClassroom,
    Map<String, dynamic> value,
  ) async {
    final String? teacherId = localAccount?.id;
    final ClassroomSetup? remoteClassroom =
        teacherId == null ? null : classroomFromIdentityJson(teacherId, value);

    // Mirror the canonical display name onto the device, so a rename made
    // elsewhere is visible here after the next reachable load.
    final String? canonicalName = value['displayName'] as String?;
    if (localAccount != null &&
        canonicalName != null &&
        canonicalName != localAccount.displayName) {
      unawaited(_session.updateAccount(displayName: canonicalName));
    }

    // Server canonical classroom overwrites the cache only when the cache is
    // absent or has nothing unsynced to lose.
    ClassroomSetup? classroom = localClassroom;
    if (remoteClassroom != null &&
        (localClassroom == null || localClassroom.pendingSync != true)) {
      await _classrooms.save(remoteClassroom);
      classroom = remoteClassroom;
    }

    final TeacherAccount? account =
        _parseAccount(value) ?? localAccount ?? _fallbackAccount(value);
    return TeacherIdentity(
      account: account,
      classroom: classroom ?? remoteClassroom,
    );
  }

  /// The server's account payload, or null when it is malformed. The identity
  /// contract guarantees ``id``/``displayName``/``schoolName``, but a hostile
  /// or stale server must never be allowed to fail a profile load.
  static TeacherAccount? _parseAccount(Map<String, dynamic> value) {
    try {
      return TeacherAccount.fromJson(value);
    } on TypeError {
      return null;
    }
  }

  static TeacherAccount? _fallbackAccount(Map<String, dynamic> value) {
    final Object? id = value['id'];
    final Object? name = value['displayName'];
    if (id is! String || name is! String) return null;
    return TeacherAccount(
      id: id,
      displayName: name,
      schoolName: value['schoolName'] as String? ?? '',
      schoolCode: value['schoolCode'] as String?,
      mobileLast4: value['mobileLast4'] as String?,
    );
  }

  @override
  Future<bool> updateDisplayName(String newName) async {
    final TeacherAccount? account = await _session.account();
    if (account == null) return false;
    if (!await _session.updateAccount(displayName: newName)) return false;

    final String? token = await _session.accessToken();
    if (token == null || token.isEmpty) return true;

    // Best-effort push now; a failure is safe because the local account is the
    // source of truth and the next successful load mirrors the server's name.
    await _api.patch(
      ApiEndpoints.teachersMe,
      body: <String, dynamic>{'displayName': newName},
    );
    return true;
  }
}

/// The classroom portion of a canonical identity payload, when the server has
/// one. A teacher who never pushed setup has none of these fields, so this
/// returns null for them.
ClassroomSetup? classroomFromIdentityJson(
  String teacherId,
  Map<String, dynamic> json,
) {
  final int? classLevel = json['classLevel'] as int?;
  if (json['setupCompleted'] != true || classLevel == null) return null;

  final List<dynamic> rawSubjects = json['subjects'] as List<dynamic>? ?? const <dynamic>[];
  return ClassroomSetup(
    teacherId: teacherId,
    schoolName: json['schoolName'] as String? ?? '',
    districtId: json['districtId'] as String? ?? '',
    districtName: json['districtName'] as String? ?? '',
    blockId: json['blockId'] as String? ?? '',
    blockName: json['blockName'] as String? ?? '',
    teachingMedium: TeachingMedium.byName(
          json['teachingMedium'] as String?,
        ) ??
        TeachingMedium.hindi,
    targetLanguage: TargetLanguage.byName(
          json['targetLanguage'] as String?,
        ) ??
        TargetLanguage.santali,
    classLevel: classLevel,
    subjects: <ClassroomSubject>{
      for (final dynamic s in rawSubjects)
        if (ClassroomSubject.byName(s as String?) case final ClassroomSubject v)
          v,
    },
    setupCompleted: true,
    pendingSync: false,
    schemaVersion: ClassroomSetup.currentSchemaVersion,
  );
}