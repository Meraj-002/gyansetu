import 'package:flutter/material.dart';

/// Type scale for GyanSetu AI.
///
/// [fontFamily] is intentionally left null so that each script resolves through
/// the platform's own font-fallback chain: Devanagari for Hindi, Latin for
/// English.
///
/// NOTE (Santali): Santali is written in Ol Chiki, which most Android system
/// fonts do NOT cover. Before the Santali UI ships, bundle `Noto Sans Ol Chiki`
/// as an asset font and set it here — resolving it at runtime from a font CDN
/// would break the offline-first requirement.
abstract final class AppTypography {
  static const String? fontFamily = null;

  static const TextTheme textTheme = TextTheme(
    displayLarge: TextStyle(
      fontSize: 40,
      height: 1.15,
      fontWeight: FontWeight.w700,
      letterSpacing: -0.5,
    ),
    displayMedium: TextStyle(
      fontSize: 32,
      height: 1.2,
      fontWeight: FontWeight.w700,
      letterSpacing: -0.25,
    ),
    displaySmall: TextStyle(fontSize: 28, height: 1.25, fontWeight: FontWeight.w600),
    headlineMedium: TextStyle(fontSize: 24, height: 1.3, fontWeight: FontWeight.w600),
    headlineSmall: TextStyle(fontSize: 20, height: 1.3, fontWeight: FontWeight.w600),
    titleLarge: TextStyle(fontSize: 18, height: 1.35, fontWeight: FontWeight.w600),
    titleMedium: TextStyle(fontSize: 16, height: 1.4, fontWeight: FontWeight.w600),
    titleSmall: TextStyle(fontSize: 14, height: 1.4, fontWeight: FontWeight.w600),
    bodyLarge: TextStyle(fontSize: 16, height: 1.5, fontWeight: FontWeight.w400),
    bodyMedium: TextStyle(fontSize: 14, height: 1.5, fontWeight: FontWeight.w400),
    bodySmall: TextStyle(fontSize: 12, height: 1.45, fontWeight: FontWeight.w400),
    labelLarge: TextStyle(fontSize: 15, height: 1.2, fontWeight: FontWeight.w600, letterSpacing: 0.2),
    labelMedium: TextStyle(fontSize: 13, height: 1.2, fontWeight: FontWeight.w500, letterSpacing: 0.2),
    labelSmall: TextStyle(fontSize: 11, height: 1.2, fontWeight: FontWeight.w500, letterSpacing: 0.4),
  );
}
