import '../models/auth_result.dart';

/// Credentials handed to an [AuthenticationService].
///
/// [pin] is held only for the duration of the call. Nothing here is logged, and
/// [toString] is overridden so an accidental interpolation cannot leak it.
class AuthCredentials {
  const AuthCredentials.mobile({required String mobile, required this.pin})
      : identifier = mobile,
        kind = CredentialKind.mobile,
        schoolCode = null;

  const AuthCredentials.teacherId({
    required String teacherId,
    required this.pin,
  })  : identifier = teacherId,
        kind = CredentialKind.teacherId,
        schoolCode = null;

  const AuthCredentials.schoolCode({
    required this.schoolCode,
    required this.identifier,
    required this.pin,
  }) : kind = CredentialKind.schoolCode;

  final CredentialKind kind;

  /// Mobile number, Teacher ID, or the identifier accompanying a school code.
  final String identifier;

  final String pin;
  final String? schoolCode;

  @override
  String toString() => 'AuthCredentials(${kind.name}, pin: <redacted>)';
}

enum CredentialKind { mobile, teacherId, schoolCode }

/// Server-side authentication.
///
/// The FastAPI client will implement this interface unchanged; nothing above it
/// knows how the call is made.
abstract interface class AuthenticationService {
  /// Verifies [credentials] against the server and registers this device.
  Future<AuthResult> signIn(AuthCredentials credentials);

  /// Checks a school code and returns whether it is known to the server.
  Future<AuthResult> verifySchoolCode(AuthCredentials credentials);

  /// Starts PIN recovery for [identifier]. Requires connectivity; there is no
  /// local reset path by design.
  Future<bool> requestPinRecovery(String identifier);

  /// Invalidates the server-side session. Local material is cleared separately
  /// by [OfflineAuthenticationService.forgetDevice].
  Future<void> signOut();
}
