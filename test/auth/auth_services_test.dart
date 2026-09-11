import 'package:flutter_test/flutter_test.dart';
import 'package:gyan_setu_ai/features/auth/models/auth_result.dart';
import 'package:gyan_setu_ai/features/auth/services/auth_session_store.dart';
import 'package:gyan_setu_ai/features/auth/services/offline_authentication_service.dart';
import 'package:gyan_setu_ai/features/auth/services/pin_verifier.dart';

import 'auth_test_doubles.dart';

void main() {
  group('PinHasher', () {
    test('a derived verifier matches only the PIN it came from', () async {
      const PinHasher hasher = PinHasher(iterations: 2);
      final PinVerifier verifier = await hasher.derive('7391');

      expect(await hasher.matches('7391', verifier), isTrue);
      expect(await hasher.matches('7392', verifier), isFalse);
      expect(await hasher.matches('', verifier), isFalse);
    });

    test('two derivations of the same PIN use different salts', () async {
      const PinHasher hasher = PinHasher(iterations: 2);
      final PinVerifier a = await hasher.derive('5150');
      final PinVerifier b = await hasher.derive('5150');

      expect(a.salt, isNot(equals(b.salt)));
      expect(a.hash, isNot(equals(b.hash)));
      // Either verifier still accepts the PIN.
      expect(await hasher.matches('5150', a), isTrue);
      expect(await hasher.matches('5150', b), isTrue);
    });

    test('the stored record never contains the PIN', () async {
      final PinVerifier verifier = await kFastHasher.derive('2468');
      final String encoded = verifier.toJson().toString();

      expect(encoded.contains('2468'), isFalse);
      expect(verifier.toString().contains('2468'), isFalse);
      // Nor the derived material, which must not be logged either.
      expect(verifier.toString().contains('hash'), isFalse);
    });
  });

  group('OfflineAuthenticationService', () {
    late AuthSessionStore store;
    late OfflineAuthenticationService offline;

    setUp(() {
      store = memoryStore();
      offline = OfflineAuthenticationService(
        store: store,
        hasher: kFastHasher,
      );
    });

    test('an unprovisioned device cannot sign in offline', () async {
      expect(await offline.hasProvisionedAccount(), isFalse);

      final AuthResult result = await offline.signInWithPin('1357');
      expect(result, isA<AuthFailure>());
      expect(
        (result as AuthFailure).reason,
        AuthFailureReason.noOfflineAccount,
      );
    });

    test('signs in after provisioning, and reports it was not online',
        () async {
      await offline.provisionAfterOnlineSignIn(
        account: kTestTeacher,
        pin: '8642',
      );
      expect(await offline.hasProvisionedAccount(), isTrue);

      final AuthResult result = await offline.signInWithPin('8642');
      expect(result, isA<AuthSuccess>());
      expect((result as AuthSuccess).verifiedOnline, isFalse);
      expect(result.account.id, kTestTeacher.id);
    });

    test('rejects the wrong PIN', () async {
      await offline.provisionAfterOnlineSignIn(
        account: kTestTeacher,
        pin: '8642',
      );

      final AuthResult result = await offline.signInWithPin('1111');
      expect(
        (result as AuthFailure).reason,
        AuthFailureReason.invalidCredentials,
      );
    });

    test('locks out after repeated wrong PINs', () async {
      await offline.provisionAfterOnlineSignIn(
        account: kTestTeacher,
        pin: '8642',
      );

      for (int i = 1; i < OfflineAuthenticationService.maxFailedAttempts; i++) {
        expect(
          ((await offline.signInWithPin('0000')) as AuthFailure).reason,
          AuthFailureReason.invalidCredentials,
          reason: 'attempt $i should merely fail',
        );
      }

      final AuthResult locked = await offline.signInWithPin('0000');
      expect((locked as AuthFailure).reason, AuthFailureReason.lockedOut);

      // Even the correct PIN is refused while the lockout stands.
      final AuthResult stillLocked = await offline.signInWithPin('8642');
      expect((stillLocked as AuthFailure).reason, AuthFailureReason.lockedOut);
    });

    test('a successful sign-in clears the failure count', () async {
      await offline.provisionAfterOnlineSignIn(
        account: kTestTeacher,
        pin: '8642',
      );
      await offline.signInWithPin('0000');
      expect(await store.failedAttempts(), 1);

      await offline.signInWithPin('8642');
      expect(await store.failedAttempts(), 0);
    });

    test('refuses a session that has aged out', () async {
      await offline.provisionAfterOnlineSignIn(
        account: kTestTeacher,
        pin: '8642',
      );
      // Backdate the last online contact past the offline window.
      final InMemorySnapshot snapshot = InMemorySnapshot(store);
      await snapshot.backdateLastAuth(
        AuthSessionStore.offlineSessionMaxAge + const Duration(days: 1),
      );

      final AuthResult result = await offline.signInWithPin('8642');
      expect((result as AuthFailure).reason, AuthFailureReason.sessionExpired);
    });

    test('forgetDevice removes the ability to sign in offline', () async {
      await offline.provisionAfterOnlineSignIn(
        account: kTestTeacher,
        pin: '8642',
      );
      await offline.forgetDevice();

      expect(await offline.hasProvisionedAccount(), isFalse);
      expect(await offline.provisionedAccount(), isNull);
    });

    test('school codes are only usable offline once provisioned', () async {
      expect(await offline.isSchoolCodeProvisioned('DUM-114'), isFalse);
      await store.rememberSchoolCode('dum-114');
      expect(await offline.isSchoolCodeProvisioned('DUM-114'), isTrue);
    });
  });

  group('AuthSessionStore', () {
    test('reports setup state, defaulting to incomplete', () async {
      final AuthSessionStore store = memoryStore();
      expect(await store.isClassroomSetupComplete(), isFalse);

      await store.setClassroomSetupComplete(complete: true);
      expect(await store.isClassroomSetupComplete(), isTrue);
    });
  });
}

/// Reaches into the store to age a session, which is otherwise only possible
/// by waiting a month.
class InMemorySnapshot {
  const InMemorySnapshot(this.store);

  final AuthSessionStore store;

  Future<void> backdateLastAuth(Duration by) async {
    final DateTime? current = await store.lastAuthenticatedAt();
    expect(current, isNotNull);
    // The store writes the stamp itself; rewrite it through the same key.
    await store.debugSetLastAuthenticatedAt(current!.subtract(by));
  }
}
