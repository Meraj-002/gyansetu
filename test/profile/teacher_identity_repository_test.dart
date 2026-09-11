import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:gyan_setu_ai/core/errors/app_exception.dart';
import 'package:gyan_setu_ai/core/utils/result.dart';
import 'package:gyan_setu_ai/features/auth/models/teacher_account.dart';
import 'package:gyan_setu_ai/features/auth/services/auth_session_store.dart';
import 'package:gyan_setu_ai/features/auth/services/pin_verifier.dart';
import 'package:gyan_setu_ai/features/profile/services/teacher_identity_repository.dart';
import 'package:gyan_setu_ai/features/setup/models/classroom_setup.dart';
import 'package:gyan_setu_ai/services/api/api_endpoints.dart';
import 'package:gyan_setu_ai/services/storage/secure_storage_service.dart';

import '../api/api_test_doubles.dart';
import '../auth/auth_test_doubles.dart' as auth_doubles;
import '../setup/setup_test_doubles.dart' as setup_doubles;

/// The canonical identity `/auth/me` returns for the fictional teacher.
final Map<String, dynamic> meBody = <String, dynamic>{
  'id': auth_doubles.kTestTeacher.id,
  'displayName': auth_doubles.kTestTeacher.displayName,
  'schoolName': auth_doubles.kTestTeacher.schoolName,
  'schoolId': 'school-1',
  'districtId': 'dumka',
  'districtName': 'Dumka',
  'blockId': 'dumka.jama',
  'blockName': 'Jama',
  'classLevel': 1,
  'subjects': <String>['foundationalLiteracy', 'numeracy'],
  'teachingMedium': 'hindi',
  'targetLanguage': 'santali',
  'setupCompleted': true,
};

/// A local classroom that is itself waiting to sync and must not be clobbered.
ClassroomSetup pendingClassroom() => ClassroomSetup(
  teacherId: auth_doubles.kTestTeacher.id,
  schoolName: 'Local School',
  districtId: 'd',
  districtName: 'Dumka',
  blockId: 'b',
  blockName: 'Jama',
  teachingMedium: TeachingMedium.hindi,
  targetLanguage: TargetLanguage.santali,
  classLevel: 4,
  subjects: const <ClassroomSubject>{ClassroomSubject.numeracy},
  setupCompleted: true,
  pendingSync: true,
);

Future<void> provision(AuthSessionStore session) => session.provision(
  account: auth_doubles.kTestTeacher,
  verifier: PinVerifier(
    salt: Uint8List(1),
    hash: Uint8List(1),
    iterations: 1,
  ),
  deviceId: 'test-device',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late InMemorySecureStorageService storage;
  late AuthSessionStore session;
  late setup_doubles.TestRepository classrooms;
  late ScriptedApiClient api;
  late FastApiTeacherIdentityRepository repository;

  setUp(() {
    storage = InMemorySecureStorageService();
    session = AuthSessionStore(storage);
    classrooms = setup_doubles.TestRepository();
    api = ScriptedApiClient();
    repository = FastApiTeacherIdentityRepository(
      api: api,
      session: session,
      classrooms: classrooms,
    );
  });

  group('load with no token', () {
    test('returns the cached local snapshot without any network call', () async {
      await provision(session);
      classrooms.save(
        pendingClassroom().copyWith(pendingSync: false),
      );

      final TeacherIdentity identity = await repository.load();

      expect(identity.account!.id, auth_doubles.kTestTeacher.id);
      expect(identity.classroom, isNotNull);
      expect(api.getPaths, isEmpty);
    });

    test('returns an empty identity when not even provisioned', () async {
      final TeacherIdentity identity = await repository.load();
      expect(identity.account, isNull);
      expect(identity.classroom, isNull);
      expect(api.getPaths, isEmpty);
    });
  });

  group('load with a token', () {
    test('hydrates the classroom cache from the server when absent', () async {
      await provision(session);
      await session.saveAccessToken('token-1');
      api.onGet = () => Ok<Map<String, dynamic>>(meBody);

      final TeacherIdentity identity = await repository.load();

      expect(api.getPaths, <String>[ApiEndpoints.me]);
      final ClassroomSetup? stored = classrooms.recordFor(
        auth_doubles.kTestTeacher.id,
      );
      expect(stored, isNotNull);
      expect(stored!.classLevel, 1);
      expect(stored.setupCompleted, isTrue);
      expect(stored.pendingSync, isFalse);
      expect(stored.subjects, contains(ClassroomSubject.foundationalLiteracy));
      expect(identity.account!.schoolName, auth_doubles.kTestTeacher.schoolName);
    });

    test('keeps a pending-sync local classroom instead of the server copy', () async {
      await provision(session);
      await session.saveAccessToken('token-1');
      classrooms.save(pendingClassroom());
      api.onGet = () => Ok<Map<String, dynamic>>(meBody);

      final TeacherIdentity identity = await repository.load();

      // The local, unsynced version is untouched.
      final ClassroomSetup? stored = classrooms.recordFor(
        auth_doubles.kTestTeacher.id,
      );
      expect(stored, isNotNull);
      expect(stored!.classLevel, 4);
      expect(stored.pendingSync, isTrue);
      expect(identity.classroom!.classLevel, 4);
    });

    test('mirrors a server rename onto the device account', () async {
      await provision(session);
      await session.saveAccessToken('token-1');
      api.onGet = () => Ok<Map<String, dynamic>>(
        <String, dynamic>{...meBody, 'displayName': 'Asha K'},
      );

      await repository.load();

      final TeacherAccount? stored = await session.account();
      expect(stored!.displayName, 'Asha K');
    });

    test('falls back to local on an expired token without crashing', () async {
      await provision(session);
      await session.saveAccessToken('stale-token');
      classrooms.save(pendingClassroom());
      final int savesBefore = classrooms.saveCalls;
      api.onGet = () =>
          Err<Map<String, dynamic>>(UnauthorizedException('invalid_token'));

      final TeacherIdentity identity = await repository.load();

      expect(identity.account!.id, auth_doubles.kTestTeacher.id);
      expect(identity.classroom!.classLevel, 4);
      // The error path never writes; the stale classroom stays exactly as it was.
      expect(classrooms.saveCalls, savesBefore);
    });

    test('falls back to local when the server is unreachable', () async {
      await provision(session);
      await session.saveAccessToken('token-1');
      classrooms.save(pendingClassroom().copyWith(pendingSync: false));
      api.onGet = () =>
          Err<Map<String, dynamic>>(NetworkException('no route to host'));

      final TeacherIdentity identity = await repository.load();

      expect(identity.account, isNotNull);
      expect(identity.classroom!.classLevel, 4);
    });

    test('a server copy with no classroom leaves the cache alone', () async {
      await provision(session);
      await session.saveAccessToken('token-1');
      classrooms.save(pendingClassroom().copyWith(pendingSync: false));
      final int savesBefore = classrooms.saveCalls;
      api.onGet = () => Ok<Map<String, dynamic>>(
        <String, dynamic>{
          'id': auth_doubles.kTestTeacher.id,
          'displayName': auth_doubles.kTestTeacher.displayName,
          'schoolName': auth_doubles.kTestTeacher.schoolName,
        },
      );

      final TeacherIdentity identity = await repository.load();

      expect(classrooms.saveCalls, savesBefore);
      expect(identity.classroom!.classLevel, 4);
    });
  });

  group('updateDisplayName', () {
    test('writes locally and pushes to the server when a token exists', () async {
      await provision(session);
      await session.saveAccessToken('token-1');
      api.onPatch = () => Ok<Map<String, dynamic>>(meBody);

      final bool ok = await repository.updateDisplayName('Anita Murmu');

      expect(ok, isTrue);
      final TeacherAccount? stored = await session.account();
      expect(stored!.displayName, 'Anita Murmu');
      expect(api.patchPaths, <String>[ApiEndpoints.teachersMe]);
    });

    test('a server rejection still counts the local save as kept', () async {
      await provision(session);
      await session.saveAccessToken('token-1');
      api.onPatch = () =>
          Err<Map<String, dynamic>>(UnauthorizedException('invalid_token'));

      expect(await repository.updateDisplayName('Anita Murmu'), isTrue);
      expect((await session.account())!.displayName, 'Anita Murmu');
    });

    test('never calls the server without a token', () async {
      await provision(session);

      expect(await repository.updateDisplayName('Anita Murmu'), isTrue);
      expect(api.patchPaths, isEmpty);
      expect((await session.account())!.displayName, 'Anita Murmu');
    });

    test('returns false when there is no account to rename', () async {
      expect(await repository.updateDisplayName('Anita Murmu'), isFalse);
      expect(api.patchPaths, isEmpty);
    });
  });
}