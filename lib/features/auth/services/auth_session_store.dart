import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../../services/storage/secure_storage_service.dart';
import '../models/teacher_account.dart';
import 'pin_verifier.dart';

/// Everything the device remembers about a signed-in teacher.
///
/// All of it lives in [SecureStorageService]; nothing authentication-related is
/// written to preferences or the database. The PIN is not part of this record —
/// only a verifier derived from it.
class AuthSessionStore {
  AuthSessionStore(this._storage);

  final SecureStorageService _storage;
  Future<void> Function()? _unauthorizedHandler;
  bool _handlingUnauthorized = false;

  static const String _kAccount = 'auth.account';
  static const String _kVerifier = 'auth.pin_verifier';
  static const String _kDeviceId = 'auth.device_id';
  static const String _kLastAuthAt = 'auth.last_authenticated_at';
  static const String _kFailedAttempts = 'auth.failed_attempts';
  static const String _kLockedUntil = 'auth.locked_until';
  static const String _kSetupComplete = 'auth.classroom_setup_complete';
  static const String _kSchoolCodes = 'auth.provisioned_school_codes';
  static const String _kAccessToken = 'auth.access_token';
  static const String _kAccessTokenExpiresAt = 'auth.access_token_expires_at';

  /// How long an offline session stays valid without seeing the server again.
  static const Duration offlineSessionMaxAge = Duration(days: 30);

  Future<TeacherAccount?> account() async =>
      TeacherAccount.tryDecode(await _storage.read(_kAccount));

  Future<PinVerifier?> pinVerifier() async {
    final String? raw = await _storage.read(_kVerifier);
    if (raw == null || raw.isEmpty) return null;
    try {
      return PinVerifier.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } on FormatException {
      return null;
    } on TypeError {
      return null;
    }
  }

  Future<String?> deviceId() => _storage.read(_kDeviceId);

  Future<DateTime?> lastAuthenticatedAt() async {
    final String? raw = await _storage.read(_kLastAuthAt);
    if (raw == null) return null;
    return DateTime.tryParse(raw);
  }

  /// True when a locally provisioned account exists and has not gone stale.
  Future<bool> hasUsableOfflineAccount() async {
    if (await account() == null) return false;
    if (await pinVerifier() == null) return false;
    return !await isSessionExpired();
  }

  Future<bool> isSessionExpired() async {
    final DateTime? last = await lastAuthenticatedAt();
    if (last == null) return true;
    return DateTime.now().difference(last) > offlineSessionMaxAge;
  }

  /// Records a device registration after a successful online sign-in.
  ///
  /// Returns false when any part could not be persisted; the caller must then
  /// treat the device as unprovisioned rather than assume offline sign-in will
  /// work later.
  Future<bool> provision({
    required TeacherAccount account,
    required PinVerifier verifier,
    required String deviceId,
  }) async {
    final bool ok =
        await _storage.write(_kAccount, account.encode()) &&
        await _storage.write(_kVerifier, jsonEncode(verifier.toJson())) &&
        await _storage.write(_kDeviceId, deviceId) &&
        await touch();
    await resetFailedAttempts();
    return ok;
  }

  /// Refreshes the last-authenticated stamp.
  Future<bool> touch() =>
      _storage.write(_kLastAuthAt, DateTime.now().toIso8601String());

  /// Persists a display-name change to the existing account record.
  ///
  /// Returns false when no account exists or the update could not be written;
  /// the caller must then keep the old value rather than pretend it saved.
  Future<bool> updateAccount({required String displayName}) async {
    final TeacherAccount? current = await account();
    if (current == null) return false;
    final TeacherAccount updated = current.copyWith(displayName: displayName);
    return _storage.write(_kAccount, updated.encode());
  }

  /// Ages the session stamp so expiry can be exercised without waiting a month.
  @visibleForTesting
  Future<void> debugSetLastAuthenticatedAt(DateTime when) async =>
      _storage.write(_kLastAuthAt, when.toIso8601String());

  Future<int> failedAttempts() async =>
      int.tryParse(await _storage.read(_kFailedAttempts) ?? '') ?? 0;

  Future<int> recordFailedAttempt() async {
    final int next = await failedAttempts() + 1;
    await _storage.write(_kFailedAttempts, '$next');
    return next;
  }

  Future<void> resetFailedAttempts() async {
    await _storage.delete(_kFailedAttempts);
    await _storage.delete(_kLockedUntil);
  }

  Future<DateTime?> lockedUntil() async {
    final String? raw = await _storage.read(_kLockedUntil);
    if (raw == null) return null;
    return DateTime.tryParse(raw);
  }

  Future<void> lockFor(Duration duration) async => _storage.write(
    _kLockedUntil,
    DateTime.now().add(duration).toIso8601String(),
  );

  Future<bool> isClassroomSetupComplete() async =>
      await _storage.read(_kSetupComplete) == 'true';

  Future<void> setClassroomSetupComplete({required bool complete}) async =>
      _storage.write(_kSetupComplete, complete ? 'true' : 'false');

  /// School codes this device has already had verified online, so school-code
  /// sign-in can work offline for them and only for them.
  Future<Set<String>> provisionedSchoolCodes() async {
    final String? raw = await _storage.read(_kSchoolCodes);
    if (raw == null || raw.isEmpty) return <String>{};
    try {
      return (jsonDecode(raw) as List<dynamic>).cast<String>().toSet();
    } on FormatException {
      return <String>{};
    } on TypeError {
      return <String>{};
    }
  }

  Future<void> rememberSchoolCode(String code) async {
    final Set<String> codes = await provisionedSchoolCodes()
      ..add(code.trim().toUpperCase());
    await _storage.write(_kSchoolCodes, jsonEncode(codes.toList()));
  }

  /// The bearer token from the last online sign-in, if any.
  ///
  /// Null when the device has only ever signed in offline, or has signed out.
  /// The sync layer needs this to talk to the server; without it a sync run
  /// must say it cannot proceed rather than pretend otherwise.
  Future<String?> accessToken() => _storage.read(_kAccessToken);

  /// When the stored token expires, or null if unknown.
  Future<DateTime?> accessTokenExpiresAt() async {
    final String? raw = await _storage.read(_kAccessTokenExpiresAt);
    if (raw == null) return null;
    return DateTime.tryParse(raw);
  }

  /// Persists the token a successful server sign-in returned.
  Future<void> saveAccessToken(String token, {DateTime? expiresAt}) async {
    await _storage.write(_kAccessToken, token);
    if (expiresAt != null) {
      await _storage.write(_kAccessTokenExpiresAt, expiresAt.toIso8601String());
    }
  }

  /// Drops the server session token but keeps the offline account, so a
  /// provisioned device's PIN tab keeps working after a sign-out.
  Future<void> clearAccessToken() async {
    await _storage.delete(_kAccessToken);
    await _storage.delete(_kAccessTokenExpiresAt);
  }

  /// Installs the app-level response to an expired server session.
  ///
  /// The session store owns clearing credentials; the app owns navigation. A
  /// handler is optional so service-level tests and non-UI callers stay small.
  void setUnauthorizedHandler(Future<void> Function()? handler) {
    _unauthorizedHandler = handler;
  }

  /// Clears an expired token and asks the app to return to sign-in.
  ///
  /// Login itself also receives 401s, but has no stored token yet and must stay
  /// on the form to show its invalid-credentials message.
  Future<void> handleUnauthorized() async {
    if (_handlingUnauthorized) return;
    _handlingUnauthorized = true;
    try {
      final String? token = await accessToken();
      await clearAccessToken();
      if (token == null || token.isEmpty) return;
      await _unauthorizedHandler?.call();
    } finally {
      _handlingUnauthorized = false;
    }
  }

  /// Removes everything this device knows about the teacher.
  Future<void> clear() async {
    for (final String key in <String>[
      _kAccount,
      _kVerifier,
      _kDeviceId,
      _kLastAuthAt,
      _kFailedAttempts,
      _kLockedUntil,
      _kSetupComplete,
      _kSchoolCodes,
      _kAccessToken,
      _kAccessTokenExpiresAt,
    ]) {
      await _storage.delete(key);
    }
  }
}
