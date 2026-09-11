import 'package:flutter/widgets.dart';

/// Spacing scale (4pt grid).
///
/// Every gap, pad and inset in the app comes from here so that density stays
/// consistent across screens and can be tuned in one place for small tablets.
abstract final class AppSpacing {
  static const double xxs = 2;
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 32;
  static const double xxl = 48;

  /// Default horizontal inset for full-screen content.
  static const EdgeInsets screen = EdgeInsets.all(md);

  /// Default inner padding for cards and list tiles.
  static const EdgeInsets card = EdgeInsets.all(md);

  /// Vertical rhythm between stacked sections.
  static const SizedBox gapXs = SizedBox(height: xs);
  static const SizedBox gapSm = SizedBox(height: sm);
  static const SizedBox gapMd = SizedBox(height: md);
  static const SizedBox gapLg = SizedBox(height: lg);
}
