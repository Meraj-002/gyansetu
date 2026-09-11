import '../../core/config/api_config.dart';

/// Server paths for the FastAPI backend.
///
/// The base URL is platform-aware and injectable at build time:
/// `flutter run --dart-define=GYANSETU_API_BASE_URL=https://api.example.org`
/// overrides the dev-server default picked by [ApiConfig.resolve].
abstract final class ApiEndpoints {
  /// Defaults to the platform-aware development address. A physical Android
  /// device must use the Mac LAN address via GYANSETU_API_BASE_URL.
  static String get baseUrl => ApiConfig.baseUrl;

  static const String _v1 = '/api/v1';

  static const String health = '$_v1/health';
  static const String translationTranslate = '$_v1/translation/translate';
  static const String translationDiagnostics = '$_v1/translation/diagnostics';
  static const String speechTranslation = '$_v1/translation/speech';

  // --- Authentication ------------------------------------------------------
  static const String register = '$_v1/auth/register';
  static const String login = '$_v1/auth/login';
  static const String me = '$_v1/auth/me';
  static const String verifySchoolCode = '$_v1/auth/verify-school-code';
  static const String recover = '$_v1/auth/recover';
  static const String logout = '$_v1/auth/logout';

  // --- Content catalogue ---------------------------------------------------
  static const String lessons = '$_v1/lessons';

  /// Downloadable content packs (lesson content, audio plans, worksheets,
  /// flashcards). Lists are paginated with `limit`/`offset`; individual packs
  /// stream from `$resources/{id}/content`.
  static const String resources = '$_v1/resources';

  // --- Teacher-owned records -----------------------------------------------
  static const String teachersMe = '$_v1/teachers/me';
  static const String worksheets = '$_v1/worksheets';
  static const String flashcards = '$_v1/flashcards';
  static const String assessments = '$_v1/assessments';
  static const String progress = '$_v1/progress';

  // --- Sync bridge ----------------------------------------------------------
  static const String sync = '$_v1/sync';
  static const String syncStatus = '$_v1/sync/status';
  static const String syncPush = '$_v1/sync/push';
  static const String syncPull = '$_v1/sync/pull';
}
