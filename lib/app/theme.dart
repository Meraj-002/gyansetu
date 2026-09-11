import 'package:flutter/material.dart';

import '../core/constants/app_colors.dart';
import '../core/constants/app_radius.dart';
import '../core/constants/app_spacing.dart';
import '../core/constants/app_typography.dart';

/// The single source of truth for GyanSetu AI's visual style.
///
/// Screens read everything through `Theme.of(context)`. Nothing here should be
/// re-declared inside a feature: if a screen needs a new variant, add it to the
/// theme rather than styling the widget inline.
abstract final class AppTheme {
  static ThemeData get light => _build(_lightScheme);

  static ThemeData get dark => _build(_darkScheme);

  static const ColorScheme _lightScheme = ColorScheme(
    brightness: Brightness.light,
    primary: AppColors.primary,
    onPrimary: AppColors.onPrimary,
    primaryContainer: AppColors.primaryContainer,
    onPrimaryContainer: AppColors.onPrimaryContainer,
    secondary: AppColors.secondary,
    onSecondary: AppColors.onSecondary,
    secondaryContainer: AppColors.secondaryContainer,
    onSecondaryContainer: AppColors.onSecondaryContainer,
    tertiary: AppColors.info,
    onTertiary: AppColors.onPrimary,
    error: AppColors.error,
    onError: AppColors.onPrimary,
    surface: AppColors.surface,
    onSurface: AppColors.textPrimary,
    surfaceContainerHighest: AppColors.surfaceVariant,
    onSurfaceVariant: AppColors.textSecondary,
    outline: AppColors.outline,
    outlineVariant: AppColors.outlineVariant,
  );

  static const ColorScheme _darkScheme = ColorScheme(
    brightness: Brightness.dark,
    primary: AppColors.primaryLight,
    onPrimary: AppColors.onPrimary,
    primaryContainer: AppColors.primaryDark,
    onPrimaryContainer: AppColors.textOnDark,
    secondary: AppColors.secondaryLight,
    onSecondary: AppColors.onSecondary,
    secondaryContainer: AppColors.secondaryDark,
    onSecondaryContainer: AppColors.textOnDark,
    tertiary: AppColors.info,
    onTertiary: AppColors.onPrimary,
    error: AppColors.error,
    onError: AppColors.onPrimary,
    surface: AppColors.darkSurface,
    onSurface: AppColors.textOnDark,
    surfaceContainerHighest: AppColors.darkSurfaceVariant,
    onSurfaceVariant: AppColors.textDisabled,
    outline: AppColors.darkOutline,
    outlineVariant: AppColors.darkSurfaceVariant,
  );

  static ThemeData _build(ColorScheme scheme) {
    final bool isLight = scheme.brightness == Brightness.light;
    final TextTheme textTheme = AppTypography.textTheme.apply(
      bodyColor: scheme.onSurface,
      displayColor: scheme.onSurface,
      fontFamily: AppTypography.fontFamily,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor:
          isLight ? AppColors.background : AppColors.darkBackground,
      textTheme: textTheme,
      fontFamily: AppTypography.fontFamily,

      appBarTheme: AppBarTheme(
        backgroundColor: isLight ? AppColors.background : AppColors.darkBackground,
        foregroundColor: scheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 1,
        centerTitle: false,
        titleTextStyle: textTheme.titleLarge,
      ),

      // --- Buttons -----------------------------------------------------------
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(_buttonHeight),
          padding: _buttonPadding,
          textStyle: AppTypography.textTheme.labelLarge,
          shape: const RoundedRectangleBorder(borderRadius: AppRadius.mdAll),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: scheme.primary,
          foregroundColor: scheme.onPrimary,
          minimumSize: const Size.fromHeight(_buttonHeight),
          padding: _buttonPadding,
          elevation: 0,
          textStyle: AppTypography.textTheme.labelLarge,
          shape: const RoundedRectangleBorder(borderRadius: AppRadius.mdAll),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: scheme.primary,
          minimumSize: const Size.fromHeight(_buttonHeight),
          padding: _buttonPadding,
          textStyle: AppTypography.textTheme.labelLarge,
          side: BorderSide(color: scheme.outline),
          shape: const RoundedRectangleBorder(borderRadius: AppRadius.mdAll),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: scheme.primary,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: AppSpacing.xs,
          ),
          textStyle: AppTypography.textTheme.labelLarge,
          shape: const RoundedRectangleBorder(borderRadius: AppRadius.smAll),
        ),
      ),

      // --- Cards --------------------------------------------------------------
      cardTheme: CardThemeData(
        color: scheme.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.lgAll,
          side: BorderSide(color: scheme.outlineVariant),
        ),
      ),

      // --- Inputs -------------------------------------------------------------
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerHighest,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.md,
        ),
        border: const OutlineInputBorder(
          borderRadius: AppRadius.mdAll,
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: AppRadius.mdAll,
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: AppRadius.mdAll,
          borderSide: BorderSide(color: scheme.primary, width: 2),
        ),
      ),

      chipTheme: ChipThemeData(
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.pillAll),
        side: BorderSide(color: scheme.outlineVariant),
        labelStyle: AppTypography.textTheme.labelMedium,
      ),

      dividerTheme: DividerThemeData(color: scheme.outlineVariant, space: 1, thickness: 1),

      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.mdAll),
        contentTextStyle: AppTypography.textTheme.bodyMedium,
      ),
    );
  }

  /// Large touch targets: the app runs on shared classroom tablets.
  static const double _buttonHeight = 52;

  static const EdgeInsets _buttonPadding = EdgeInsets.symmetric(
    horizontal: AppSpacing.lg,
    vertical: AppSpacing.md,
  );
}
