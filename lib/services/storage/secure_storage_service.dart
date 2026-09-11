import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../core/utils/app_logger.dart';

/// Contract for the only place authentication material may be written.
///
/// Kept behind an interface so that no feature reaches for a concrete storage
/// plugin, and so tests can run without a platform keystore.
abstract interface class SecureStorageService {
  Future<String?> read(String key);

  /// Returns false when the value could not be persisted.
  Future<bool> write(String key, String value);

  Future<void> delete(String key);
  Future<void> deleteAll();
}

/// Platform-backed implementation: Android Keystore / iOS Keychain, and
/// WebCrypto-wrapped storage on the web.
///
/// Every call degrades rather than throws. A keystore can be genuinely
/// unavailable — a platform channel that is not registered, a browser with site
/// data blocked, a keystore invalidated by a lock-screen change — and none of
/// those is a reason to fail an authentication the server already accepted.
/// A failed read reads as "nothing stored", which makes the device look
/// unprovisioned; a failed write is reported to the caller, so the UI stops
/// promising offline access instead of quietly losing it. Failures are logged,
/// never silent.
class PlatformSecureStorageService implements SecureStorageService {
  PlatformSecureStorageService([FlutterSecureStorage? storage])
      // v11's defaults are already the strong path: AES-GCM data encryption
      // with an RSA-OAEP key wrapped in the Android Keystore.
      : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(storageNamespace: 'gyansetu.auth'),
            );

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) async {
    try {
      return await _storage.read(key: key);
    } on Object catch (error) {
      AppLogger.error('secure read failed for "$key"', error: error);
      return null;
    }
  }

  @override
  Future<bool> write(String key, String value) async {
    try {
      await _storage.write(key: key, value: value);
      return true;
    } on Object catch (error) {
      AppLogger.error('secure write failed for "$key"', error: error);
      return false;
    }
  }

  @override
  Future<void> delete(String key) async {
    try {
      await _storage.delete(key: key);
    } on Object catch (error) {
      AppLogger.error('secure delete failed for "$key"', error: error);
    }
  }

  @override
  Future<void> deleteAll() async {
    try {
      await _storage.deleteAll();
    } on Object catch (error) {
      AppLogger.error('secure deleteAll failed', error: error);
    }
  }
}

/// In-memory stand-in for tests and for widget previews.
///
/// Never wire this into a release build: it keeps values in the heap only.
class InMemorySecureStorageService implements SecureStorageService {
  final Map<String, String> _values = <String, String>{};

  @override
  Future<String?> read(String key) async => _values[key];

  @override
  Future<bool> write(String key, String value) async {
    _values[key] = value;
    return true;
  }

  @override
  Future<void> delete(String key) async => _values.remove(key);

  @override
  Future<void> deleteAll() async => _values.clear();
}
