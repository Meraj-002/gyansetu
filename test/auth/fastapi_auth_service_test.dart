import 'package:flutter_test/flutter_test.dart';
import 'package:gyan_setu_ai/core/errors/app_exception.dart';
import 'package:gyan_setu_ai/core/utils/result.dart';
import 'package:gyan_setu_ai/features/auth/models/auth_result.dart';
import 'package:gyan_setu_ai/features/auth/services/auth_session_store.dart';
import 'package:gyan_setu_ai/features/auth/services/authentication_service.dart';
import 'package:gyan_setu_ai/features/auth/services/fastapi_authentication_service.dart';
import 'package:gyan_setu_ai/features/auth/services/offline_authentication_service.dart';
import 'package:gyan_setu_ai/services/api/api_endpoints.dart';
import 'package:gyan_setu_ai/services/storage/secure_storage_service.dart';

import '../api/api_test_doubles.dart';
import 'auth_test_doubles.dart';

void main() {
  late InMemorySecureStorageService storage;
  late AuthSessionStore session;
  late OfflineAuthenticationService offline;
  late ScriptedApiClient api;
  late FastApiAuthenticationService service;

  const Map<String, dynamic> tokenBody = <String, dynamic>{
    'accessToken': 'token-abc',
    'expiresIn': 3600,
    'account': <String, dynamic>{
      'id': 'teacher-1',
      'displayName': 'Asha Murmu',
      'schoolName': 'Govt. Primary School, Dumka',
    },
  };

  setUp(() {
    storage = InMemorySecureStorageService();
    session = AuthSessionStore(storage);
    offline = OfflineAuthenticationService(store: session, hasher: kFastHasher);
    api = ScriptedApiClient();
    service = FastApiAuthenticationService(
      api: api,
      offline: offline,
      session: session,
    );
  });

  group('signIn', () {
    test('success provisions the device, stores the token and routes home when '
        'setup is complete', () async {
      await session.setClassroomSetupComplete(complete: true);
      api.onPost = () => Ok<Map<String, dynamic>>(tokenBody);

      final AuthResult result = await service.signIn(
        const AuthCredentials.mobile(mobile: '7000000000', pin: '1234'),
      );

      expect(result, isA<AuthSuccess>());
      final AuthSuccess success = result as AuthSuccess;
      expect(success.account.id, 'teacher-1');
      expect(success.destination, PostAuthDestination.home);
      expect(success.verifiedOnline, isTrue);
      expect(api.postPaths, contains(ApiEndpoints.login));
      expect(
        api.postCallsFor(ApiEndpoints.login).last['body'],
        <String, dynamic>{
          'identifier': '7000000000',
          'password': '1234',
          'school_code': null,
          'device_id': null,
        },
      );

      expect(await session.accessToken(), 'token-abc');
      expect(await session.accessTokenExpiresAt(), isNotNull);

      final AuthResult offlineResult = await offline.signInWithPin('1234');
      expect(offlineResult, isA<AuthSuccess>());
      expect(
        (offlineResult as AuthSuccess).verifiedOnline,
        isFalse,
        reason: 'the offline path must not claim server verification',
      );
    });

    test(
      'success routes to setup when the classroom was never configured',
      () async {
        api.onPost = () => Ok<Map<String, dynamic>>(tokenBody);

        final AuthResult result = await service.signIn(
          const AuthCredentials.teacherId(teacherId: 'T-42', pin: '1234'),
        );

        expect((result as AuthSuccess).destination, PostAuthDestination.setup);
      },
    );

    test('rejected credentials map to invalidCredentials', () async {
      api.onPost = () => Err<Map<String, dynamic>>(
        const UnauthorizedException('invalid_credentials'),
      );

      final AuthResult result = await service.signIn(
        const AuthCredentials.mobile(mobile: '7000000000', pin: '9999'),
      );

      expect(result, isA<AuthFailure>());
      expect(
        (result as AuthFailure).reason,
        AuthFailureReason.invalidCredentials,
      );
      expect(await session.accessToken(), isNull);
    });

    test('a transport failure maps to network', () async {
      api.onPost = () =>
          Err<Map<String, dynamic>>(const NetworkException('no signal'));

      final AuthResult result = await service.signIn(
        const AuthCredentials.mobile(mobile: '7000000000', pin: '1234'),
      );

      expect((result as AuthFailure).reason, AuthFailureReason.network);
    });
  });

  group('verifySchoolCode', () {
    test('registers a brand-new teacher after the code checks out', () async {
      api.onPost = () {
        // Login must fail so the flow falls through to registration — that is
        // how a brand-new teacher is created.
        if (api.postPaths.last == ApiEndpoints.login) {
          return Err<Map<String, dynamic>>(
            const UnauthorizedException('invalid_credentials'),
          );
        }
        return Ok<Map<String, dynamic>>(tokenBody);
      };

      final AuthResult result = await service.verifySchoolCode(
        const AuthCredentials.schoolCode(
          schoolCode: 'sch001',
          identifier: '7000000000',
          pin: '1234',
        ),
      );

      expect(result, isA<AuthSuccess>());
      expect(api.postPaths, contains(ApiEndpoints.verifySchoolCode));
      expect(
        api.postPaths,
        containsAll(<String>[ApiEndpoints.login, ApiEndpoints.register]),
      );

      final Set<String> codes = await session.provisionedSchoolCodes();
      expect(codes, contains('SCH001'));

      final Object? registerBody = api
          .postCallsFor(ApiEndpoints.register)
          .last['body'];
      final Map<String, dynamic> register =
          registerBody! as Map<String, dynamic>;
      expect(register['mobile'], '7000000000');
      expect(register['schoolCode'], 'sch001');
      expect(register['password'], '1234');
    });

    test(
      'falls back to login when registration says the mobile is taken',
      () async {
        final List<String> seen = <String>[];
        api.onPost = () {
          final String path = api.postPaths.last;
          if (path == ApiEndpoints.verifySchoolCode) {
            return Ok<Map<String, dynamic>>(<String, dynamic>{'ok': true});
          }
          if (path == ApiEndpoints.login) {
            seen.add(path);
            return seen.length == 1
                ? Err<Map<String, dynamic>>(
                    const UnauthorizedException('invalid_credentials'),
                  )
                : Ok<Map<String, dynamic>>(tokenBody);
          }
          return Err<Map<String, dynamic>>(
            const ServerException('mobile_in_use', statusCode: 409),
          );
        };

        final AuthResult result = await service.verifySchoolCode(
          const AuthCredentials.schoolCode(
            schoolCode: 'SCH001',
            identifier: '7000000000',
            pin: '1234',
          ),
        );

        expect(result, isA<AuthSuccess>());
        expect(api.postCallsFor(ApiEndpoints.login).length, 2);
        expect(await session.accessToken(), 'token-abc');
      },
    );

    test('a 404 from the verifier means the code is not registered', () async {
      api.onPost = () => Err<Map<String, dynamic>>(
        const ServerException('unknown school code', statusCode: 404),
      );

      final AuthResult result = await service.verifySchoolCode(
        const AuthCredentials.schoolCode(
          schoolCode: 'NOPE',
          identifier: '7000000000',
          pin: '1234',
        ),
      );

      expect(
        (result as AuthFailure).reason,
        AuthFailureReason.schoolCodeRejected,
      );
      expect(await session.provisionedSchoolCodes(), isEmpty);
    });
  });

  group('recovery and sign-out', () {
    test('requestPinRecovery reports whether the server accepted it', () async {
      api.onPost = () => Ok<Map<String, dynamic>>(<String, dynamic>{});
      expect(await service.requestPinRecovery('7000000000'), isTrue);

      api.onPost = () => Err<Map<String, dynamic>>(
        const ServerException('not_found', statusCode: 404),
      );
      expect(await service.requestPinRecovery('7000000000'), isFalse);
    });

    test('signOut drops the token and tells the server', () async {
      await session.saveAccessToken('token-abc');
      api.onPost = () => Ok<Map<String, dynamic>>(<String, dynamic>{});

      await service.signOut();

      expect(await session.accessToken(), isNull);
      expect(api.postPaths, contains(ApiEndpoints.logout));
    });
  });
}
