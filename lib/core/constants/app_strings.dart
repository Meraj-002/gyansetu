/// Strings that are not user-facing copy: brand name, storage keys, and other
/// identifiers that must stay identical across the app.
///
/// User-facing copy does NOT belong here — it moves into ARB localisation files
/// once the Hindi and Santali translations land.
abstract final class AppStrings {
  static const String appName = 'GyanSetu AI';
  static const String appTagline = 'Offline-first classroom assistant';

  // Persisted preference keys.
  static const String keyLocale = 'settings.locale';
  static const String keyThemeMode = 'settings.theme_mode';
  static const String keyOnboardingComplete = 'settings.onboarding_complete';
}
