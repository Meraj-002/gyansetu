import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gyan_setu_ai/app/theme.dart';
import 'package:gyan_setu_ai/core/constants/app_colors.dart';

void main() {
  test('light theme carries the GyanSetu brand palette', () {
    final ThemeData theme = AppTheme.light;

    expect(theme.colorScheme.primary, AppColors.primary);
    expect(theme.colorScheme.secondary, AppColors.secondary);
    expect(theme.scaffoldBackgroundColor, AppColors.background);
    expect(theme.useMaterial3, isTrue);
  });

  test('dark theme is a dark scheme built from the same tokens', () {
    final ThemeData theme = AppTheme.dark;

    expect(theme.colorScheme.brightness, Brightness.dark);
    expect(theme.scaffoldBackgroundColor, AppColors.darkBackground);
  });

  test('button and card styles are defined centrally, not per screen', () {
    final ThemeData theme = AppTheme.light;

    expect(theme.filledButtonTheme.style, isNotNull);
    expect(theme.elevatedButtonTheme.style, isNotNull);
    expect(theme.outlinedButtonTheme.style, isNotNull);
    expect(theme.textButtonTheme.style, isNotNull);
    expect(theme.cardTheme.shape, isNotNull);
  });
}
