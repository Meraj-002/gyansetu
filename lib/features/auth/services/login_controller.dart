// ignore_for_file: prefer_initializing_formals
// Private fields cannot be initialising formals: a named parameter may not
// start with an underscore, so `this._store` is not expressible.
import 'package:flutter/foundation.dart';

import '../../../core/utils/app_logger.dart';
import '../../../services/connectivity/connectivity_service.dart';
import '../models/auth_result.dart';
import '../models/login_method.dart';
import '../models/teacher_account.dart';
import 'auth_session_store.dart';
import 'authentication_service.dart';
import 'offline_authentication_service.dart';

/// Field-level validation for the login form.
///
/// Pure functions, kept away from the widgets so the rules can be tested
/// without pumping a screen.
abstract final class LoginValidators {
  static final RegExp _tenDigits = RegExp(r'^\d{10}$');
  static final RegExp _fourDigits = RegExp(r'^\d{4}$');

  /// Indian mobile numbers are ten digits beginning 6-9.
  static String? mobile(String value) {
    final String v = value.trim();
    if (v.isEmpty) return 'Enter your mobile number.';
    if (!_tenDigits.hasMatch(v)) {
      return 'Enter a valid 10-digit mobile number.';
    }
    if (!RegExp(r'^[6-9]').hasMatch(v)) {
      return 'Indian mobile numbers start with 6, 7, 8 or 9.';
    }
    return null;
  }

  static String? teacherId(String value) {
    final String v = value.trim();
    if (v.isEmpty) return 'Enter your Teacher ID.';
    if (v.length < 3) return 'Teacher ID looks too short.';
    if (v.length > 32) return 'Teacher ID looks too long.';
    return null;
  }

  static String? pin(String value) {
    if (value.isEmpty) return 'Enter your PIN.';
    if (!_fourDigits.hasMatch(value)) return 'PIN must be 4 digits.';
    return null;
  }

  static String? schoolCode(String value) {
    final String v = value.trim();
    if (v.isEmpty) return 'Enter your school code.';
    if (v.length < 4) return 'School code looks too short.';
    return null;
  }
}

/// Drives the login screen: which method is selected, what the fields hold,
/// whether a request is in flight, and what went wrong.
///
/// The screen renders this; it does not decide anything itself.
class LoginController extends ChangeNotifier {
  LoginController({
    required AuthenticationService authentication,
    required OfflineAuthenticationService offline,
    required ConnectivityService connectivity,
    required AuthSessionStore store,
  })  : _authentication = authentication,
        _offline = offline,
        _connectivity = connectivity,
        _store = store {
    _connectionStatus = connectivity.status;
    _connectivity.onStatusChanged.listen((ConnectionStatus status) {
      _connectionStatus = status;
      notifyListeners();
    });
    _bootstrap();
  }

  final AuthenticationService _authentication;
  final OfflineAuthenticationService _offline;
  final ConnectivityService _connectivity;
  final AuthSessionStore _store;

  LoginMethod _method = LoginMethod.mobile;
  LoginMethod get method => _method;

  String _mobile = '';
  String _teacherId = '';
  String _pin = '';

  String get mobile => _mobile;
  String get teacherId => _teacherId;

  bool _pinVisible = false;
  bool get pinVisible => _pinVisible;

  bool _rememberDevice = true;
  bool get rememberDevice => _rememberDevice;

  bool _busy = false;
  bool get busy => _busy;

  String? _mobileError;
  String? _teacherIdError;
  String? _pinError;
  String? _formError;

  String? get mobileError => _mobileError;
  String? get teacherIdError => _teacherIdError;
  String? get pinError => _pinError;

  /// Whole-form message shown above the Continue button.
  String? get formError => _formError;

  ConnectionStatus _connectionStatus = ConnectionStatus.unknown;
  ConnectionStatus get connectionStatus => _connectionStatus;

  bool _hasOfflineAccount = false;

  /// Whether this device has been provisioned, which is what makes the PIN tab
  /// usable and what the offline chip is allowed to promise.
  bool get hasOfflineAccount => _hasOfflineAccount;

  TeacherAccount? _provisionedAccount;
  TeacherAccount? get provisionedAccount => _provisionedAccount;

  bool _ready = false;

  /// False until the local account state has been read, so the UI can avoid
  /// claiming either state while it does not know.
  bool get ready => _ready;

  Future<void> _bootstrap() async {
    _hasOfflineAccount = await _offline.hasProvisionedAccount();
    _provisionedAccount = await _offline.provisionedAccount();
    await _connectivity.check();
    _connectionStatus = _connectivity.status;
    _ready = true;
    notifyListeners();
  }

  void selectMethod(LoginMethod next) {
    if (_method == next || _busy) return;
    _method = next;
    _clearErrors();
    notifyListeners();
  }

  void setMobile(String value) {
    _mobile = value;
    if (_mobileError != null) {
      _mobileError = null;
      _formError = null;
      notifyListeners();
    }
  }

  void setTeacherId(String value) {
    _teacherId = value;
    if (_teacherIdError != null) {
      _teacherIdError = null;
      _formError = null;
      notifyListeners();
    }
  }

  void setPin(String value) {
    _pin = value;
    if (_pinError != null) {
      _pinError = null;
      _formError = null;
      notifyListeners();
    }
  }

  void togglePinVisibility() {
    _pinVisible = !_pinVisible;
    notifyListeners();
  }

  void setRememberDevice({required bool value}) {
    _rememberDevice = value;
    notifyListeners();
  }

  void _clearErrors() {
    _mobileError = null;
    _teacherIdError = null;
    _pinError = null;
    _formError = null;
  }

  /// Validates the fields the current method actually uses.
  bool validate() {
    _clearErrors();

    switch (_method) {
      case LoginMethod.mobile:
        _mobileError = LoginValidators.mobile(_mobile);
        _pinError = LoginValidators.pin(_pin);
      case LoginMethod.teacherId:
        _teacherIdError = LoginValidators.teacherId(_teacherId);
        _pinError = LoginValidators.pin(_pin);
      case LoginMethod.pin:
        _pinError = LoginValidators.pin(_pin);
    }

    notifyListeners();
    return _mobileError == null &&
        _teacherIdError == null &&
        _pinError == null;
  }

  /// Runs the sign-in appropriate to the selected method and the connection.
  ///
  /// Returns null when the attempt did not get as far as a result — a failed
  /// validation, or a second tap while the first is still in flight.
  Future<AuthResult?> submit() async {
    if (_busy) return null;
    if (!validate()) return null;

    _busy = true;
    _formError = null;
    notifyListeners();

    try {
      final AuthResult result = await _runSignIn();
      if (result is AuthFailure) {
        _formError = messageFor(result);
      } else if (result is AuthSuccess && !_rememberDevice) {
        // The teacher opted out of being remembered, so drop the material that
        // would otherwise let this device sign in offline later.
        await _offline.forgetDevice();
        _hasOfflineAccount = false;
      }
      return result;
    } on Object catch (error, stackTrace) {
      // The teacher sees a neutral message — the cause can carry server detail
      // — but it is logged, or an outage is undiagnosable.
      // IMPORTANT: Do not map arbitrary state/navigation errors to network.
      // Network is only for transport failures already handled by AuthService.
      AppLogger.error(
        'sign-in failed for method ${_method.name}',
        error: error,
        stackTrace: stackTrace,
      );
      _formError = messageFor(
        const AuthFailure(AuthFailureReason.unknown),
      );
      return const AuthFailure(AuthFailureReason.unknown);
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  Future<AuthResult> _runSignIn() async {
    final ConnectionStatus status = await _connectivity.check();
    _connectionStatus = status;

    if (_method == LoginMethod.pin) {
      // Quick sign-in is a local check by definition.
      if (!_hasOfflineAccount) {
        return const AuthFailure(AuthFailureReason.noOfflineAccount);
      }
      return _offline.signInWithPin(_pin);
    }

    if (status == ConnectionStatus.offline) {
      // Falling back locally is only honest if this device was provisioned.
      if (!_hasOfflineAccount) {
        return const AuthFailure(AuthFailureReason.noOfflineAccount);
      }
      return _offline.signInWithPin(_pin);
    }

    final AuthCredentials credentials = switch (_method) {
      LoginMethod.mobile =>
        AuthCredentials.mobile(mobile: _mobile.trim(), pin: _pin),
      LoginMethod.teacherId =>
        AuthCredentials.teacherId(teacherId: _teacherId.trim(), pin: _pin),
      LoginMethod.pin =>
        AuthCredentials.teacherId(teacherId: _teacherId.trim(), pin: _pin),
    };

    final AuthResult result = await _authentication.signIn(credentials);
    if (result is AuthSuccess) {
      _hasOfflineAccount = await _offline.hasProvisionedAccount();
      _provisionedAccount = result.account;
    }
    return result;
  }

  /// Signs in with a school code, provisioning the device when the server
  /// accepts it.
  Future<AuthResult> submitSchoolCode({
    required String schoolCode,
    required String identifier,
    required String pin,
  }) async {
    final ConnectionStatus status = await _connectivity.check();
    _connectionStatus = status;

    if (status == ConnectionStatus.offline) {
      if (!await _offline.isSchoolCodeProvisioned(schoolCode)) {
        return const AuthFailure(AuthFailureReason.schoolCodeNotProvisioned);
      }
      if (!_hasOfflineAccount) {
        return const AuthFailure(AuthFailureReason.noOfflineAccount);
      }
      return _offline.signInWithPin(pin);
    }

    try {
      final AuthResult result = await _authentication.verifySchoolCode(
        AuthCredentials.schoolCode(
          schoolCode: schoolCode.trim(),
          identifier: identifier.trim(),
          pin: pin,
        ),
      );
      if (result is AuthSuccess) {
        _hasOfflineAccount = await _offline.hasProvisionedAccount();
        _provisionedAccount = result.account;
      }
      return result;
    } on Object catch (error, stackTrace) {
      AppLogger.error(
        'school-code sign-in failed',
        error: error,
        stackTrace: stackTrace,
      );
      return const AuthFailure(AuthFailureReason.unknown);
    }
  }

  /// Starts PIN recovery. Returns false when it could not be started, which is
  /// what the UI needs in order to say so plainly.
  Future<bool> requestPinRecovery() async {
    final ConnectionStatus status = await _connectivity.check();
    _connectionStatus = status;
    if (status != ConnectionStatus.online) return false;

    final String identifier =
        _method == LoginMethod.teacherId ? _teacherId.trim() : _mobile.trim();
    try {
      return await _authentication.requestPinRecovery(identifier);
    } on Object {
      return false;
    }
  }

  Future<bool> isClassroomSetupComplete() => _store.isClassroomSetupComplete();

  /// User-facing copy for a failure. Server text and exceptions never reach
  /// the screen.
  static String messageFor(AuthFailure failure) => switch (failure.reason) {
        AuthFailureReason.invalidCredentials =>
          'Incorrect PIN. Please try again.',
        AuthFailureReason.noOfflineAccount =>
          'This account is not available for offline login on this device.',
        AuthFailureReason.lockedOut =>
          'Too many incorrect attempts. Try again in '
              '${failure.retryAfter?.inMinutes ?? 15} minutes.',
        AuthFailureReason.sessionExpired =>
          'Your session has expired. Connect to the internet to sign in again.',
        AuthFailureReason.network =>
          'We couldn’t connect. Check your internet connection, or use offline '
              'login if this device is already set up.',
        AuthFailureReason.schoolCodeNotProvisioned =>
          'This school code has not been verified on this device yet. '
              'First-time school-code login needs an internet connection.',
        AuthFailureReason.schoolCodeRejected =>
          'This school code is not registered. Check the code and try again.',
        AuthFailureReason.unknown => 'Something went wrong. Please try again.',
      };
}
