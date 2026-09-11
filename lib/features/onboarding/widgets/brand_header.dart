import 'package:flutter/material.dart';

import '../../../core/constants/app_assets.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';

/// Logo lock-up plus the Skip action, shared by all three onboarding pages.
///
/// The wordmark is live text rather than part of the image, so the product name
/// is never baked into an asset.
class BrandHeader extends StatelessWidget {
  const BrandHeader({required this.onSkip, this.scale = 1, super.key});

  final VoidCallback onSkip;

  /// Multiplier applied to the lock-up so it can shrink on short screens.
  final double scale;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      // The Stack is stretched to the full width on purpose: left to itself it
      // shrink-wraps the lock-up, and Skip then lands beside the logo rather
      // than in the corner.
      child: SizedBox(
        width: double.infinity,
        child: Stack(
          alignment: Alignment.topCenter,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.sm),
              child: BrandLockup(scale: scale),
            ),
            Positioned(
              top: 0,
              right: 0,
              child: TextButton(
                onPressed: onSkip,
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.brandMuted,
                  // Holds a 44dp touch target without visually enlarging the
                  // label, which the reference sets tight into the corner.
                  minimumSize: const Size(64, 44),
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm,
                  ),
                  textStyle: TextStyle(
                    fontSize: 15 * scale,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                child: const Text('Skip'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The mark, the GyanSetu AI wordmark and the strapline, stacked.
class BrandLockup extends StatelessWidget {
  const BrandLockup({this.scale = 1, super.key});

  final double scale;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'GyanSetu AI',
      child: ExcludeSemantics(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Image.asset(
              AppAssets.brandMark,
              height: 46 * scale,
              filterQuality: FilterQuality.medium,
            ),
            SizedBox(height: 6 * scale),
            Text.rich(
              TextSpan(
                children: const <InlineSpan>[
                  TextSpan(
                    text: 'GyanSetu',
                    style: TextStyle(color: AppColors.brandNavy),
                  ),
                  TextSpan(text: ' '),
                  TextSpan(
                    text: 'AI',
                    style: TextStyle(color: AppColors.brandOrange),
                  ),
                ],
                style: TextStyle(
                  fontSize: 23 * scale,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.2,
                  height: 1.05,
                ),
              ),
            ),
            SizedBox(height: 3 * scale),
            Text(
              'Mother Tongue Education for Every Child',
              style: TextStyle(
                fontSize: 8.5 * scale,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.1,
                color: AppColors.brandNavy.withValues(alpha: 0.85),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
