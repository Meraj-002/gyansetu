import 'package:gyan_setu_ai/features/auth/models/auth_result.dart';
import 'package:gyan_setu_ai/features/auth/models/teacher_account.dart';
import 'package:gyan_setu_ai/features/auth/services/auth_session_store.dart';
import 'package:gyan_setu_ai/features/auth/services/authentication_service.dart';
import 'package:gyan_setu_ai/features/auth/services/offline_authentication_service.dart';
import 'package:gyan_setu_ai/features/auth/services/pin_verifier.dart';
import 'package:gyan_setu_ai/services/storage/secure_storage_service.dart';

/// A fictional teacher used only by tests. Not a credential: nothing in the app
/// accepts these values, because the fakes below decide the outcome instead.
const TeacherAccount kTestTeacher = TeacherAccount(
  id: 'test-teacher',
  displayName: 'Asha Murmu',
  schoolName: 'Govt. Primary School, Dumka',
  mobileLast4: '4321',
);

/// PBKDF2 at production strength would make the suite crawl. Tests exercise
/// the same code path with a token work factor.
const PinHasher kFastHasher = PinHasher(iterations: 1);

/// Builds a store backed by memory rather than a platform keystore.
AuthSessionStore memoryStore() =>
    AuthSessionStore(InMemorySecureStorageService());

/// An authentication service whose outcome the test chooses.
class FakeAuthenticationService implements AuthenticationService {
  FakeAuthenticationService({
    this.result,
    this.throwOnSignIn = false,
    this.recoveryStarts = false,
    this.latency = Duration.zero,
    this.offline,
  });

  /// Returned by [signIn] and [verifySchoolCode] when set.
  AuthResult? result;

  /// Simulates a transport failure so the controller's catch-all is exercised.
  bool throwOnSignIn;

  bool recoveryStarts;
  Duration latency;

  /// When supplied, a successful sign-in provisions the device, mirroring what
  /// the real service does.
  final OfflineAuthenticationService? offline;

  int signInCalls = 0;
  int schoolCodeCalls = 0;
  int signOutCalls = 0;
  AuthCredentials? lastCredentials;

  @override
  Future<AuthResult> signIn(AuthCredentials credentials) async {
    signInCalls++;
    lastCredentials = credentials;
    if (latency > Duration.zero) await Future<void>.delayed(latency);
    if (throwOnSignIn) throw StateError('transport failed');

    final AuthResult r = result ??
        const AuthSuccess(
          account: kTestTeacher,
          destination: PostAuthDestination.setup,
          verifiedOnline: true,
        );
    if (r is AuthSuccess && offline != null) {
      await offline!.provisionAfterOnlineSignIn(
        account: r.account,
        pin: credentials.pin,
      );
    }
    return r;
  }

  @override
  Future<AuthResult> verifySchoolCode(AuthCredentials credentials) async {
    schoolCodeCalls++;
    lastCredentials = credentials;
    if (latency > Duration.zero) await Future<void>.delayed(latency);
    return result ??
        const AuthSuccess(
          account: kTestTeacher,
          destination: PostAuthDestination.setup,
          verifiedOnline: true,
        );
  }

  @override
  Future<bool> requestPinRecovery(String identifier) async => recoveryStarts;

  @override
  Future<void> signOut() async => signOutCalls++;
}
