// ignore_for_file: prefer_initializing_formals
// Private fields cannot be initialising formals: a named parameter may not
// start with an underscore, so `this._store` is not expressible.
import 'dart:math';

import '../models/auth_result.dart';
import '../models/teacher_account.dart';
import 'auth_session_store.dart';
import 'authentication_service.dart';
import 'offline_authentication_service.dart';

/// Stand-in for the FastAPI backend while it does not exist yet.
///
/// It simulates a server round trip and then accepts any well-formed input. It
/// contains no credential of any kind: there is nothing to "log in as", and
/// nothing here would let a real deployment through by accident, because
/// swapping in `FastApiAuthenticationService` removes it entirely.
///
/// The account it returns is derived from what was typed, so the rest of the
/// app can be exercised end to end without inventing a fixture user.
class DevelopmentAuthenticationService implements AuthenticationService {
  DevelopmentAuthenticationService({
    required OfflineAuthenticationService offline,
    required AuthSessionStore store,
    this.latency = const Duration(milliseconds: 900),
  })  : _offline = offline,
              _store = store;

  final OfflineAuthenticationService _offline;
  final AuthSessionStore _store;

  /// Simulated round-trip time, so loading states are exercised in development.
  final Duration latency;

  static final Random _random = Random.secure();

  /// Random hex from bytes rather than `nextInt(1 << 32)`.
  ///
  /// On the web an int is a JavaScript number and `<<` follows JS's mod-32
  /// shift semantics, so `1 << 32` evaluates to 0 there and `nextInt` throws.
  /// Byte-wise generation behaves identically on every target.
  static String _randomHex(int bytes) => List<int>.generate(
        bytes,
        (_) => _random.nextInt(256),
      ).map((int b) => b.toRadixString(16).padLeft(2, '0')).join();

  @override
  Future<AuthResult> signIn(AuthCredentials credentials) async {
    await Future<void>.delayed(latency);

    final TeacherAccount account = _accountFor(credentials);
    await _offline.provisionAfterOnlineSignIn(
      account: account,
      pin: credentials.pin,
    );

    return AuthSuccess(
      account: account,
      destination: await _store.isClassroomSetupComplete()
          ? PostAuthDestination.home
          : PostAuthDestination.setup,
      verifiedOnline: true,
    );
  }

  @override
  Future<AuthResult> verifySchoolCode(AuthCredentials credentials) async {
    await Future<void>.delayed(latency);

    final String? code = credentials.schoolCode?.trim().toUpperCase();
    if (code == null || code.isEmpty) {
      return const AuthFailure(AuthFailureReason.invalidCredentials);
    }

    await _store.rememberSchoolCode(code);
    final TeacherAccount account = _accountFor(credentials);
    await _offline.provisionAfterOnlineSignIn(
      account: account,
      pin: credentials.pin,
    );

    return AuthSuccess(
      account: account,
      destination: await _store.isClassroomSetupComplete()
          ? PostAuthDestination.home
          : PostAuthDestination.setup,
      verifiedOnline: true,
    );
  }

  @override
  Future<bool> requestPinRecovery(String identifier) async {
    await Future<void>.delayed(latency);
    // No recovery endpoint exists yet. Reporting false keeps the UI honest
    // instead of showing a success it cannot back up.
    return false;
  }

  @override
  Future<void> signOut() async {
    await Future<void>.delayed(const Duration(milliseconds: 150));
  }

  /// Builds a plausible account from whatever identified the teacher.
  TeacherAccount _accountFor(AuthCredentials credentials) {
    final String identifier = credentials.identifier.trim();
    final bool isMobile = credentials.kind == CredentialKind.mobile;

    return TeacherAccount(
      id: 'dev-${_randomHex(4)}',
      displayName: isMobile
          ? 'Teacher ${identifier.length >= 4 ? identifier.substring(identifier.length - 4) : identifier}'
          : 'Teacher $identifier',
      schoolName: credentials.schoolCode == null
          ? 'Your school'
          : 'School ${credentials.schoolCode}',
      schoolCode: credentials.schoolCode,
      mobileLast4: isMobile && identifier.length >= 4
          ? identifier.substring(identifier.length - 4)
          : null,
    );
  }
}
