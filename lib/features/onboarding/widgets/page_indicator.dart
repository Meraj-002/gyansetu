import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';

/// Three dots tracking the current onboarding page.
///
/// The active dot widens and warms rather than merely changing colour, so the
/// position reads at a glance and does not rely on colour alone.
class PageIndicator extends StatelessWidget {
  const PageIndicator({
    required this.count,
    required this.currentIndex,
    super.key,
  });

  final int count;
  final int currentIndex;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Page ${currentIndex + 1} of $count',
      child: ExcludeSemantics(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: List<Widget>.generate(count, (int i) {
            final bool active = i == currentIndex;
            return AnimatedContainer(
              duration: const Duration(milliseconds: 280),
              curve: Curves.easeOutCubic,
              margin: const EdgeInsets.symmetric(horizontal: 5),
              width: active ? 22 : 9,
              height: 9,
              decoration: BoxDecoration(
                color: active
                    ? AppColors.brandOrangeBright
                    : Colors.white.withValues(alpha: 0.34),
                borderRadius: BorderRadius.circular(9),
              ),
            );
          }),
        ),
      ),
    );
  }
}
