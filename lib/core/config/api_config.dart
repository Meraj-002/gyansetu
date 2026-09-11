import 'package:flutter/foundation.dart';

/// Where the FastAPI backend lives, resolved for the platform the app runs on.
///
/// Emulators need an alias (the Android emulator reaches the host machine at
/// 10.0.2.2). A physical Android device must be given the Mac's LAN address;
/// pass that once at launch with [GYANSETU_API_BASE_URL]. Staging and release
/// builds pin the server explicitly:
///
///     flutter run --dart-define=GYANSETU_API_BASE_URL=http://192.168.1.6:8000
abstract final class ApiConfig {
  static const String _override = String.fromEnvironment(
    'GYANSETU_API_BASE_URL',
  );

  /// Pure resolution so the platform choice can be tested without a device.
  static String resolve({bool? isWeb, TargetPlatform? platform}) {
    final bool web = isWeb ?? kIsWeb;
    if (web) return 'http://localhost:8000';
    final TargetPlatform target = platform ?? defaultTargetPlatform;
    if (target == TargetPlatform.android) return 'http://10.0.2.2:8000';
    return 'http://localhost:8000';
  }

  /// The base URL a produced build actually talks to. A compile-time override
  /// wins; otherwise the platform-aware development default above applies.
  static String get baseUrl => _override.isNotEmpty ? _override : resolve();
}
