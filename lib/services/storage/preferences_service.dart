import '../../core/utils/result.dart';

/// Small key-value store for settings that are not worth a database table:
/// selected language, theme, onboarding completion.
///
/// Keys live in `AppStrings` so that they cannot drift between reader and
/// writer.
abstract interface class PreferencesService {
  Future<Result<String?>> getString(String key);
  Future<Result<void>> setString(String key, String value);

  Future<Result<bool?>> getBool(String key);
  Future<Result<void>> setBool(String key, bool value);

  Future<Result<void>> remove(String key);
}
