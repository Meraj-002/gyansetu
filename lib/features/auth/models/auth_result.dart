import 'teacher_account.dart';

/// Why an authentication attempt did not succeed.
///
/// The UI maps these to copy; services never hand a raw exception or a server
/// message to the screen.
enum AuthFailureReason {
  /// The identifier or PIN did not match.
  invalidCredentials,

  /// Nothing has been provisioned on this device, so offline sign-in is not
  /// possible yet.
  noOfflineAccount,

  /// Too many wrong PINs; offline sign-in is temporarily locked.
  lockedOut,

  /// The stored offline session is too old to be trusted.
  sessionExpired,

  /// The request never reached the server.
  network,

  /// The school code is not known to this device and cannot be checked offline.
  schoolCodeNotProvisioned,

  /// The server rejected the school code itself.
  schoolCodeRejected,

  /// Anything the service could not classify.
  unknown,
}

/// Whether a signed-in teacher still has to complete classroom setup.
enum PostAuthDestination { setup, home }

/// Outcome of an authentication attempt.
sealed class AuthResult {
  const AuthResult();
}

final class AuthSuccess extends AuthResult {
  const AuthSuccess({
    required this.account,
    required this.destination,
    required this.verifiedOnline,
  });

  final TeacherAccount account;

  /// Where the app should go next, decided by the service rather than the
  /// screen so the rule lives in one place.
  final PostAuthDestination destination;

  /// False when the teacher was verified against locally provisioned material.
  /// The UI says so rather than implying the server confirmed anything.
  final bool verifiedOnline;
}

final class AuthFailure extends AuthResult {
  const AuthFailure(this.reason, {this.retryAfter});

  final AuthFailureReason reason;

  /// Set for [AuthFailureReason.lockedOut].
  final Duration? retryAfter;
}
