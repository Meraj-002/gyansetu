import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';

/// The saffron pill that advances onboarding.
///
/// Presses shrink it very slightly. That is the only motion here on purpose:
/// this is a government education product, and the feedback should read as
/// solid rather than playful.
class OnboardingCta extends StatefulWidget {
  const OnboardingCta({required this.label, required this.onPressed, super.key});

  final String label;
  final VoidCallback onPressed;

  @override
  State<OnboardingCta> createState() => _OnboardingCtaState();
}

class _OnboardingCtaState extends State<OnboardingCta> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (_pressed == value) return;
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: widget.label,
      child: ExcludeSemantics(
        child: GestureDetector(
          onTapDown: (_) => _setPressed(true),
          onTapUp: (_) => _setPressed(false),
          onTapCancel: () => _setPressed(false),
          onTap: widget.onPressed,
          child: AnimatedScale(
            scale: _pressed ? 0.97 : 1,
            duration: const Duration(milliseconds: 120),
            curve: Curves.easeOut,
            child: Container(
              // 52 tall keeps the target comfortably above the 48dp minimum.
              height: 52,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(26),
                gradient: const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: <Color>[
                    AppColors.brandCtaTop,
                    AppColors.brandCtaBottom,
                  ],
                ),
                boxShadow: <BoxShadow>[
                  BoxShadow(
                    color: AppColors.brandCtaBottom.withValues(alpha: 0.35),
                    blurRadius: 14,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Flexible(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        widget.label,
                        maxLines: 1,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: AppColors.brandOnCta,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 9),
                  const Icon(
                    Icons.arrow_forward,
                    size: 19,
                    color: AppColors.brandOnCta,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
