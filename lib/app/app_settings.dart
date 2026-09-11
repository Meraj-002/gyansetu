import 'package:flutter/material.dart';

/// App-wide preferences: teaching language and theme.
///
/// A plain [ChangeNotifier] — the lightest state holder Flutter ships with.
/// Feature-local state stays inside its own feature; only settings that affect
/// the whole app live here.
class AppSettings extends ChangeNotifier {
  AppSettings({
    Locale? locale,
    ThemeMode? themeMode,
    double textScale = 1.0,
    bool highContrast = false,
  })  : _locale = locale ?? hindi,
        _themeMode = themeMode ?? ThemeMode.light,
        // ignore: prefer_initializing_formals
        _textScale = textScale,
        // ignore: prefer_initializing_formals
        _highContrast = highContrast;

  /// Hindi, in Devanagari.
  static const Locale hindi = Locale('hi');

  /// Santali, explicitly in the Ol Chiki script — Santali is also written in
  /// Devanagari and Latin, so the script subtag is not optional here.
  static final Locale santali = Locale.fromSubtags(
    languageCode: 'sat',
    scriptCode: 'Olck',
  );

  static List<Locale> get supportedLocales => <Locale>[hindi, santali];

  Locale _locale;
  Locale get locale => _locale;

  ThemeMode _themeMode;
  ThemeMode get themeMode => _themeMode;

  void setLocale(Locale value) {
    if (_locale == value) return;
    _locale = value;
    notifyListeners();
  }

  void setThemeMode(ThemeMode value) {
    if (_themeMode == value) return;
    _themeMode = value;
    notifyListeners();
  }

  double _textScale;
  double get textScale => _textScale;

  bool _highContrast;
  bool get highContrast => _highContrast;

  /// Applies the accessibility profile from the Settings screen app-wide,
  /// immediately and for as long as this process runs.
  void applyAccessibility({required double textScale, required bool highContrast}) {
    if (_textScale == textScale && _highContrast == highContrast) return;
    _textScale = textScale;
    _highContrast = highContrast;
    notifyListeners();
  }
}
