import 'package:flutter_test/flutter_test.dart';
import 'package:gyan_setu_ai/features/auth/services/auth_session_store.dart';
import 'package:gyan_setu_ai/services/storage/secure_storage_service.dart';

import 'auth_test_doubles.dart';

void main() {
  late InMemorySecureStorageService storage;
  late AuthSessionStore session;

  setUp(() {
    storage = InMemorySecureStorageService();
    session = AuthSessionStore(storage);
  });

  group('AuthSessionStore access token', () {
    test('saves and reads back the token and its expiry', () async {
      expect(await session.accessToken(), isNull);
      final DateTime expiresAt = DateTime.now().add(const Duration(days: 1));

      await session.saveAccessToken('token-123', expiresAt: expiresAt);

      expect(await session.accessToken(), 'token-123');
      expect(
        (await session.accessTokenExpiresAt())!.difference(expiresAt).abs(),
        lessThan(const Duration(seconds: 1)),
      );
    });

    test('clears the token without touching the offline account', () async {
      await session.provision(
        account: kTestTeacher,
        verifier: await kFastHasher.derive('1234'),
        deviceId: 'dev-1',
      );
      await session.saveAccessToken('token-123');

      await session.clearAccessToken();

      expect(await session.accessToken(), isNull);
      expect(await session.accessTokenExpiresAt(), isNull);
      expect(await session.account(), isNotNull);
      expect(await session.deviceId(), 'dev-1');
    });

    test('save without expiry persists no expiry', () async {
      await session.saveAccessToken('token-123');
      expect(await session.accessToken(), 'token-123');
      expect(await session.accessTokenExpiresAt(), isNull);
    });

    test(
      'an unauthorized response clears the token and notifies the app',
      () async {
        bool notified = false;
        await session.saveAccessToken('token-123');
        session.setUnauthorizedHandler(() async => notified = true);

        await session.handleUnauthorized();

        expect(await session.accessToken(), isNull);
        expect(notified, isTrue);
      },
    );

    test(
      'an unauthorized login response does not navigate without a token',
      () async {
        bool notified = false;
        session.setUnauthorizedHandler(() async => notified = true);

        await session.handleUnauthorized();

        expect(notified, isFalse);
      },
    );

    test('clear() removes the token alongside everything else', () async {
      await session.provision(
        account: kTestTeacher,
        verifier: await kFastHasher.derive('1234'),
        deviceId: 'dev-1',
      );
      await session.saveAccessToken('token-123');
      await session.setClassroomSetupComplete(complete: true);
      await session.rememberSchoolCode('SCH123');

      await session.clear();

      expect(await session.accessToken(), isNull);
      expect(await session.account(), isNull);
      expect(await session.pinVerifier(), isNull);
      expect(await session.isClassroomSetupComplete(), false);
      expect(await session.provisionedSchoolCodes(), isEmpty);
    });
  });
}
