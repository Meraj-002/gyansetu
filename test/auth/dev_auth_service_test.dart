import 'package:flutter_test/flutter_test.dart';
import 'package:gyan_setu_ai/features/auth/models/auth_result.dart';
import 'package:gyan_setu_ai/features/auth/services/auth_session_store.dart';
import 'package:gyan_setu_ai/features/auth/services/authentication_service.dart';
import 'package:gyan_setu_ai/features/auth/services/development_authentication_service.dart';
import 'package:gyan_setu_ai/features/auth/services/offline_authentication_service.dart';
import 'package:gyan_setu_ai/services/storage/secure_storage_service.dart';

import 'auth_test_doubles.dart';

void main() {
  late AuthSessionStore store;
  late OfflineAuthenticationService offline;
  late DevelopmentAuthenticationService dev;

  setUp(() {
    store = AuthSessionStore(InMemorySecureStorageService());
    offline = OfflineAuthenticationService(store: store, hasher: kFastHasher);
    dev = DevelopmentAuthenticationService(
      offline: offline,
      store: store,
      latency: Duration.zero,
    );
  });

  // Run this file under `flutter test --platform chrome` as well as the VM.
  // The bug it guards against — `nextInt(1 << 32)`, where a web int is a
  // JavaScript number and `<<` wraps mod 32 so the bound became 0 — is
  // invisible on the VM and threw on every web sign-in.
  test('signs in and provisions the device on every platform', () async {
    final AuthResult result = await dev.signIn(
      const AuthCredentials.mobile(mobile: '9876543210', pin: '4417'),
    );

    expect(result, isA<AuthSuccess>());
    final AuthSuccess success = result as AuthSuccess;
    expect(success.verifiedOnline, isTrue);
    expect(success.destination, PostAuthDestination.setup);
    expect(success.account.id, startsWith('dev-'));
    expect(success.account.mobileLast4, '3210');
    expect(await offline.hasProvisionedAccount(), isTrue);
  });

  test('generated account ids are well-formed and distinct', () async {
    final Set<String> ids = <String>{};
    for (int i = 0; i < 8; i++) {
      final AuthResult r = await dev.signIn(
        const AuthCredentials.teacherId(teacherId: 'JH-2291', pin: '4417'),
      );
      ids.add((r as AuthSuccess).account.id);
    }
    expect(ids.length, 8, reason: 'ids must not collide');
    for (final String id in ids) {
      expect(id, matches(RegExp(r'^dev-[0-9a-f]{8}$')));
    }
  });

  test('school code sign-in provisions the code for later offline use',
      () async {
    final AuthResult result = await dev.verifySchoolCode(
      const AuthCredentials.schoolCode(
        schoolCode: 'dum-114',
        identifier: 'JH-2291',
        pin: '4417',
      ),
    );

    expect(result, isA<AuthSuccess>());
    expect(await offline.isSchoolCodeProvisioned('DUM-114'), isTrue);
    expect(await offline.isSchoolCodeProvisioned('OTHER-1'), isFalse);
  });

  test('PIN recovery reports that it could not be started', () async {
    expect(await dev.requestPinRecovery('9876543210'), isFalse);
  });
}
