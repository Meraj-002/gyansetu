// ignore_for_file: prefer_initializing_formals
// Private fields cannot be initialising formals: a named parameter may not
// start with an underscore, so `this._store` is not expressible.
import 'dart:math';

import '../../../core/utils/app_logger.dart';
import '../models/auth_result.dart';
import '../models/teacher_account.dart';
import 'auth_session_store.dart';
import 'pin_verifier.dart';

/// Sign-in against material this device was provisioned with earlier.
///
/// A device can only reach this path after one successful online sign-in. That
/// ordering is the whole security model: there is no way to create an offline
/// account locally, so an unprovisioned device cannot be talked into accepting
/// a PIN.
class OfflineAuthenticationService {
  OfflineAuthenticationService({
    required AuthSessionStore store,
    PinHasher hasher = const PinHasher(),
  })  : _store = store,
        _hasher = hasher;

  final AuthSessionStore _store;
  final PinHasher _hasher;

  /// Wrong PINs tolerated before offline sign-in is locked for a while.
  static const int maxFailedAttempts = 5;
  static const Duration lockoutDuration = Duration(minutes: 15);

  static final Random _random = Random.secure();

  /// Whether the PIN tab can offer a quick sign-in at all.
  Future<bool> hasProvisionedAccount() => _store.hasUsableOfflineAccount();

  /// The teacher this device was provisioned for, if any.
  Future<TeacherAccount?> provisionedAccount() => _store.account();

  /// Verifies [pin] against the stored verifier.
  Future<AuthResult> signInWithPin(String pin) async {
    final DateTime? lockedUntil = await _store.lockedUntil();
    if (lockedUntil != null && lockedUntil.isAfter(DateTime.now())) {
      return AuthFailure(
        AuthFailureReason.lockedOut,
        retryAfter: lockedUntil.difference(DateTime.now()),
      );
    }

    final TeacherAccount? account = await _store.account();
    final PinVerifier? verifier = await _store.pinVerifier();
    if (account == null || verifier == null) {
      return const AuthFailure(AuthFailureReason.noOfflineAccount);
    }

    if (await _store.isSessionExpired()) {
      return const AuthFailure(AuthFailureReason.sessionExpired);
    }

    if (!await _hasher.matches(pin, verifier)) {
      final int attempts = await _store.recordFailedAttempt();
      if (attempts >= maxFailedAttempts) {
        await _store.lockFor(lockoutDuration);
        return const AuthFailure(
          AuthFailureReason.lockedOut,
          retryAfter: lockoutDuration,
        );
      }
      return const AuthFailure(AuthFailureReason.invalidCredentials);
    }

    await _store.resetFailedAttempts();
    // Note: the stamp is NOT refreshed here. Offline sign-ins must not extend
    // the window during which the device may go without seeing the server.
    return AuthSuccess(
      account: account,
      destination: await _store.isClassroomSetupComplete()
          ? PostAuthDestination.home
          : PostAuthDestination.setup,
      verifiedOnline: false,
    );
  }

  /// Called after the server has confirmed the teacher, to register this device
  /// and derive the verifier future offline sign-ins will check against.
  ///
  /// Returns whether the device ended up provisioned. This is deliberately not
  /// allowed to fail the sign-in around it: the server has already accepted the
  /// teacher, so a keystore that will not co-operate should cost them offline
  /// access, not access. The caller reports the reduced capability instead.
  Future<bool> provisionAfterOnlineSignIn({
    required TeacherAccount account,
    required String pin,
  }) async {
    try {
      final PinVerifier verifier = await _hasher.derive(pin);
      return await _store.provision(
        account: account,
        verifier: verifier,
        deviceId: await _store.deviceId() ?? _newDeviceId(),
      );
    } on Object catch (error, stackTrace) {
      AppLogger.error(
        'device provisioning failed; offline sign-in will be unavailable',
        error: error,
        stackTrace: stackTrace,
      );
      return false;
    }
  }

  /// Whether [code] has been verified online on this device before.
  Future<bool> isSchoolCodeProvisioned(String code) async {
    final Set<String> codes = await _store.provisionedSchoolCodes();
    return codes.contains(code.trim().toUpperCase());
  }

  /// Removes every trace of the teacher from this device.
  Future<void> forgetDevice() => _store.clear();

  static String _newDeviceId() {
    final List<int> bytes =
        List<int>.generate(16, (_) => _random.nextInt(256));
    return bytes
        .map((int b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
  }
}
