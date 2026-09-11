// ignore_for_file: prefer_initializing_formals
// Private fields cannot be initialising formals: a named parameter may not
// start with an underscore.
import 'dart:async';

import '../../../core/errors/app_exception.dart';
import '../../../core/utils/app_logger.dart';
import '../../../core/utils/result.dart';
import '../../../services/api/api_client.dart';
import '../../../services/api/api_endpoints.dart';
import '../../profile/services/teacher_identity_repository.dart';
import '../../setup/models/classroom_setup.dart';
import '../../setup/services/classroom_setup_repository.dart';
import '../models/auth_result.dart';
import '../models/teacher_account.dart';
import 'auth_session_store.dart';
import 'authentication_service.dart';
import 'offline_authentication_service.dart';

/// [AuthenticationService] backed by the FastAPI server.
///
/// The PIN is the server password here: a 4-digit PIPN clears the backend's
/// 4-character minimum. On success the device is provisioned through
/// [OfflineAuthenticationService] so the PIN tab keeps working offline, and the
/// returned bearer token is stored for the sync layer.
class FastApiAuthenticationService implements AuthenticationService {
  FastApiAuthenticationService({
    required ApiClient api,
    required OfflineAuthenticationService offline,
    required AuthSessionStore session,
    ClassroomSetupRepository? classrooms,
  }) : _api = api,
       _offline = offline,
       _session = session,
       _classrooms = classrooms;

  final ApiClient _api;
  final OfflineAuthenticationService _offline;
  final AuthSessionStore _session;

  /// When provided, a classroom the server already knows about is hydrated into
  /// the device caches right after sign-in.
  final ClassroomSetupRepository? _classrooms;

  static final RegExp _tenDigits = RegExp(r'^\d{10}$');

  @override
  Future<AuthResult> signIn(AuthCredentials credentials) async {
    final Result<Map<String, dynamic>> result = await _api.post(
      ApiEndpoints.login,
      body: await _loginBody(credentials),
    );
    switch (result) {
      case Ok<Map<String, dynamic>>(:final Map<String, dynamic> value):
        return await _handleSuccess(value, credentials);
      case Err<Map<String, dynamic>>(:final AppException error):
        return _handleFailure(error);
    }
  }

  @override
  Future<AuthResult> verifySchoolCode(AuthCredentials credentials) async {
    if (credentials.schoolCode == null) {
      return const AuthFailure(AuthFailureReason.invalidCredentials);
    }

    final Result<Map<String, dynamic>> codeResult = await _api.post(
      ApiEndpoints.verifySchoolCode,
      body: <String, dynamic>{'schoolCode': credentials.schoolCode},
    );
    if (codeResult is Err<Map<String, dynamic>>) {
      return _handleFailure(codeResult.error);
    }

    // The code is real. Remember it so the same code works offline later, then
    // sign the teacher in — creating the account on first use if needed.
    await _session.rememberSchoolCode(credentials.schoolCode!);
    return _loginOrRegister(credentials);
  }

  @override
  Future<bool> requestPinRecovery(String identifier) async {
    final Result<Map<String, dynamic>> result = await _api.post(
      ApiEndpoints.recover,
      body: <String, dynamic>{'identifier': identifier},
    );
    return result is Ok<Map<String, dynamic>>;
  }

  @override
  Future<void> signOut() async {
    // JWTs are stateless: the server keeps nothing to revoke. Drop the token so
    // the sync layer stops sending a credential this device no longer wants,
    // and leave the offline account for [OfflineAuthenticationService] to clear
    // separately.
    // Send the logout request while the bearer token is still available, then
    // clear it locally even when the server is unreachable.
    try {
      await _api.post(ApiEndpoints.logout);
    } finally {
      await _session.clearAccessToken();
    }
  }

  /// Existing teachers log straight in; a brand-new teacher falls through to
  /// registration (school-code sign-in is how accounts are first created).
  Future<AuthResult> _loginOrRegister(AuthCredentials credentials) async {
    final Result<Map<String, dynamic>> loginResult = await _api.post(
      ApiEndpoints.login,
      body: await _loginBody(credentials),
    );
    switch (loginResult) {
      case Ok<Map<String, dynamic>>(:final Map<String, dynamic> value):
        return _handleSuccess(value, credentials);
      case Err<Map<String, dynamic>>(:final AppException error):
        if (error is! UnauthorizedException) return _handleFailure(error);
    }

    final Result<Map<String, dynamic>> registerResult = await _api.post(
      ApiEndpoints.register,
      body: await _registerBody(credentials),
    );
    switch (registerResult) {
      case Ok<Map<String, dynamic>>(:final Map<String, dynamic> value):
        return _handleSuccess(value, credentials);
      case Err<Map<String, dynamic>>(:final AppException error):
        // The mobile is already registered to a teacher: retry login, in case
        // this is a repeat school-code sign-in.
        if (error is ServerException && error.statusCode == 409) {
          final Result<Map<String, dynamic>> retry = await _api.post(
            ApiEndpoints.login,
            body: await _loginBody(credentials),
          );
          switch (retry) {
            case Ok<Map<String, dynamic>>(:final Map<String, dynamic> value):
              return await _handleSuccess(value, credentials);
            case Err<Map<String, dynamic>>(:final AppException error):
              return _handleFailure(error);
          }
        }
        return _handleFailure(error);
    }
  }

  Future<AuthResult> _handleSuccess(
    Map<String, dynamic> body,
    AuthCredentials credentials,
  ) async {
    try {
      final Object? accountJson = body['account'];
      if (accountJson is! Map<String, dynamic>) {
        return const AuthFailure(AuthFailureReason.unknown);
      }
      final TeacherAccount account = TeacherAccount.fromJson(accountJson);

      await _offline.provisionAfterOnlineSignIn(
        account: account,
        pin: credentials.pin,
      );

      final String token = body['accessToken'] as String? ?? '';
      final int expiresIn = body['expiresIn'] as int? ?? 0;
      if (token.isNotEmpty) {
        await _session.saveAccessToken(
          token,
          expiresAt: expiresIn > 0
              ? DateTime.now().add(Duration(seconds: expiresIn))
              : null,
        );
      }

      unawaited(_hydrateClassroom(account, accountJson));

      return AuthSuccess(
        account: account,
        destination: await _session.isClassroomSetupComplete()
            ? PostAuthDestination.home
            : PostAuthDestination.setup,
        verifiedOnline: true,
      );
    } on Object catch (error, stackTrace) {
      AppLogger.error(
        'server sign-in succeeded but the device was not provisioned',
        error: error,
        stackTrace: stackTrace,
      );
      return const AuthFailure(AuthFailureReason.unknown);
    }
  }

  AuthFailure _handleFailure(AppException error) => AuthFailure(switch (error) {
    NetworkException() => AuthFailureReason.network,
    UnauthorizedException() => AuthFailureReason.invalidCredentials,
    ServerException(:final int? statusCode) when statusCode == 404 =>
      AuthFailureReason.schoolCodeRejected,
    _ => AuthFailureReason.unknown,
  });

  /// Copies the server's classroom into the device caches, but never over a
  /// local classroom that is itself waiting to sync. Best-effort: a failed
  /// write must not fail the sign-in around it.
  Future<void> _hydrateClassroom(
    TeacherAccount account,
    Map<String, dynamic> accountJson,
  ) async {
    final ClassroomSetupRepository? classrooms = _classrooms;
    if (classrooms == null) return;
    try {
      final ClassroomSetup? remote = classroomFromIdentityJson(
        account.id,
        accountJson,
      );
      if (remote == null) return;
      final ClassroomSetup? local = await classrooms.load(account.id);
      if (local == null ||
          (remote.setupCompleted && local.pendingSync != true)) {
        await classrooms.save(remote);
        if (remote.setupCompleted) {
          await _session.setClassroomSetupComplete(complete: true);
        }
      }
    } on Object catch (error, stackTrace) {
      AppLogger.error(
        'classroom hydration after sign-in failed; keeping local data',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  Future<Map<String, dynamic>> _loginBody(AuthCredentials credentials) async {
    final String? deviceId = await _session.deviceId();
    return <String, dynamic>{
      'identifier': credentials.identifier,
      'password': credentials.pin,
      'school_code': credentials.schoolCode,
      'device_id': deviceId,
    };
  }

  Future<Map<String, dynamic>> _registerBody(
    AuthCredentials credentials,
  ) async {
    final String identifier = credentials.identifier.trim();
    final bool isMobile = _tenDigits.hasMatch(identifier);
    final String? deviceId = await _session.deviceId();
    final String fallbackName = isMobile
        ? 'Teacher ${identifier.substring(identifier.length - 4)}'
        : 'Teacher $identifier';
    return <String, dynamic>{
      'displayName': fallbackName,
      if (isMobile) 'mobile': identifier,
      'password': credentials.pin,
      'schoolCode': ?credentials.schoolCode,
      'deviceId': ?deviceId,
    };
  }
}
