import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';

/// Thin wrapper over `dart:developer` logging.
///
/// Centralised so that release builds stay quiet and so a crash reporter can be
/// attached later in one place rather than at every call site.
abstract final class AppLogger {
  static const String _name = 'GyanSetu';

  static void debug(String message) {
    if (kDebugMode) {
      developer.log(message, name: _name, level: 500);
    }
  }

  static void info(String message) {
    if (kDebugMode) {
      developer.log(message, name: _name, level: 800);
    }
  }

  static void error(String message, {Object? error, StackTrace? stackTrace}) {
    developer.log(
      message,
      name: _name,
      level: 1000,
      error: error,
      stackTrace: stackTrace,
    );
    if (kDebugMode) {
      // developer.log does not reach the terminal on web; debugPrint does, and
      // a swallowed cause with no trace is impossible to diagnose.
      debugPrint('[$_name] $message${error == null ? '' : ' -> $error'}');
    }
  }
}
