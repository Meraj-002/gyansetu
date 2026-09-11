import 'package:flutter/material.dart';

import '../../app/routes.dart';
import '../../core/constants/app_assets.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_spacing.dart';
import 'widgets/brand_header.dart';
import 'widgets/offline_showcase.dart';
import 'widgets/onboarding_cta.dart';
import 'widgets/page_indicator.dart';
import 'widgets/translation_showcase.dart';
import 'widgets/tribal_backdrop.dart';
import 'widgets/wave_panel.dart';

/// The three-page introduction shown once, before sign-in.
///
/// The brand lock-up, the cream ground and the navy wave panel are identical on
/// all three pages, so they are painted once around the [PageView] rather than
/// rebuilt inside it. Only the parts that actually differ — heading, supporting
/// line and illustration — travel with the swipe, which is what makes the
/// transition read as one product rather than three sliding screenshots.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  /// Where onboarding hands off once it is finished or skipped.
  static const String destinationRoute = AppRoutes.auth;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  static const Duration _pageChangeDuration = Duration(milliseconds: 420);

  final PageController _controller = PageController();
  int _index = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _goToPage(int index) {
    if (index < 0 || index >= _OnboardingPageSpec.pages.length) return;
    _controller.animateToPage(
      index,
      duration: _pageChangeDuration,
      curve: Curves.easeOutCubic,
    );
  }

  void _leaveOnboarding() {
    // pushReplacement, so finishing or skipping cannot be undone with back.
    AppRouter.replaceWithFade(context, OnboardingScreen.destinationRoute);
  }

  void _onPrimaryAction() {
    if (_index == _OnboardingPageSpec.pages.length - 1) {
      _leaveOnboarding();
    } else {
      _goToPage(_index + 1);
    }
  }

  @override
  Widget build(BuildContext context) {
    final List<_OnboardingPageSpec> pages = _OnboardingPageSpec.pages;
    final MediaQueryData media = MediaQuery.of(context);
    final double panelHeight =
        WavePanel.waveHeight + 84 + media.padding.bottom;
    // Shrink the lock-up a little on short devices so the heading keeps its
    // place in the hierarchy.
    final double headerScale =
        (media.size.height / 780).clamp(0.82, 1.0).toDouble();

    return PopScope(
      // Back steps through onboarding before it leaves it.
      canPop: _index == 0,
      onPopInvokedWithResult: (bool didPop, Object? result) {
        if (didPop) return;
        _goToPage(_index - 1);
      },
      child: Scaffold(
        body: Stack(
          children: <Widget>[
            const Positioned.fill(child: TribalBackdrop()),
            Column(
              children: <Widget>[
                SafeArea(
                  bottom: false,
                  child: BrandHeader(
                    onSkip: _leaveOnboarding,
                    scale: headerScale,
                  ),
                ),
                Expanded(
                  child: PageView.builder(
                    controller: _controller,
                    itemCount: pages.length,
                    onPageChanged: (int index) => setState(() => _index = index),
                    itemBuilder: (BuildContext context, int index) {
                      return _OnboardingPage(
                        spec: pages[index],
                        index: index,
                        controller: _controller,
                        currentIndex: _index,
                        reserveBottom: panelHeight,
                      );
                    },
                  ),
                ),
              ],
            ),
            Align(
              alignment: Alignment.bottomCenter,
              child: SizedBox(
                height: panelHeight,
                child: WavePanel(
                  child: Padding(
                    padding: EdgeInsets.only(
                      left: AppSpacing.lg,
                      right: AppSpacing.md,
                      bottom: media.padding.bottom,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: <Widget>[
                        PageIndicator(
                          count: pages.length,
                          currentIndex: _index,
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        // Flexible, not Spacer: on a narrow device with large
                        // text the label scales down rather than overflowing.
                        Flexible(
                          child: OnboardingCta(
                            label: pages[_index].ctaLabel,
                            onPressed: _onPrimaryAction,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Everything that differs between the three pages.
class _OnboardingPageSpec {
  const _OnboardingPageSpec({
    required this.headingLead,
    required this.headingAccent,
    required this.headingTrail,
    required this.description,
    required this.ctaLabel,
    required this.headingFactor,
    required this.illustration,
    required this.semanticLabel,
  });

  /// Navy text before the saffron emphasis.
  final String headingLead;

  /// The saffron phrase the reference puts the weight on.
  final String headingAccent;

  /// Navy text after the emphasis, if any.
  final String headingTrail;

  final String description;
  final String ctaLabel;

  /// Heading size as a share of screen width, so long headings stay on the
  /// same number of lines across phone sizes.
  final double headingFactor;

  final WidgetBuilder illustration;

  /// Spoken description of the artwork, so nothing is conveyed by image alone.
  final String semanticLabel;

  static final List<_OnboardingPageSpec> pages = <_OnboardingPageSpec>[
    _OnboardingPageSpec(
      headingLead: 'Teach in Every\n',
      headingAccent: 'Child’s Language',
      headingTrail: '',
      description: 'Bridge the language gap between\nteachers and learners.',
      ctaLabel: 'Next',
      headingFactor: 0.076,
      semanticLabel:
          'A teacher with a tablet teaching primary-school children in a '
          'classroom decorated with tribal wall art.',
      // SizedBox.expand, not Align: the photograph has to fill the space left
      // under the text and run on behind the wave panel, the way the key art
      // does. Aligning it would let it keep its intrinsic height and leave a
      // band of bare cream above it.
      illustration: (BuildContext context) => SizedBox.expand(
        child: Image.asset(
          AppAssets.onboardingClassroom,
          fit: BoxFit.cover,
          alignment: Alignment.topCenter,
          excludeFromSemantics: true,
        ),
      ),
    ),
    _OnboardingPageSpec(
      headingLead: 'Speak. Translate. ',
      headingAccent: 'Teach.',
      headingTrail: '',
      description:
          'Real-time Hindi ↔ tribal-language\nclassroom communication.',
      ctaLabel: 'Next',
      headingFactor: 0.064,
      semanticLabel:
          'A teacher speaking Hindi, with the speech shown being translated '
          'into Santali, Mundari and Ho.',
      illustration: (BuildContext context) => const TranslationShowcase(),
    ),
    _OnboardingPageSpec(
      headingLead: 'Works ',
      headingAccent: 'Without Internet',
      headingTrail: '',
      description:
          'Lessons, translation, audio and\nworksheets continue working '
          'offline.',
      ctaLabel: 'Get Started',
      headingFactor: 0.068,
      semanticLabel:
          'A device held in a rural classroom showing lessons, translation, '
          'audio and worksheets available offline.',
      illustration: (BuildContext context) => const OfflineShowcase(),
    ),
  ];
}

/// One onboarding page: heading block above, illustration filling the rest.
class _OnboardingPage extends StatelessWidget {
  const _OnboardingPage({
    required this.spec,
    required this.index,
    required this.controller,
    required this.currentIndex,
    required this.reserveBottom,
  });

  final _OnboardingPageSpec spec;
  final int index;
  final PageController controller;
  final int currentIndex;

  /// Height of the navy panel, so pages that must not slide under it can pad.
  final double reserveBottom;

  /// Distance of this page from the viewport centre, 0 when settled.
  double _offsetFromCentre() {
    if (!controller.hasClients || !controller.position.hasContentDimensions) {
      return (index - currentIndex).toDouble();
    }
    return (controller.page ?? currentIndex.toDouble()) - index;
  }

  @override
  Widget build(BuildContext context) {
    final double width = MediaQuery.sizeOf(context).width;
    final double headingSize =
        (width * spec.headingFactor).clamp(19.0, 31.0).toDouble();
    final double bodySize = (width * 0.0405).clamp(13.0, 16.5).toDouble();

    return AnimatedBuilder(
      animation: controller,
      builder: (BuildContext context, Widget? child) {
        final double t = _offsetFromCentre().abs().clamp(0.0, 1.0);
        // Content settles in as the page arrives; the backdrop stays put.
        return Opacity(
          opacity: 1 - (t * 0.85),
          child: Transform.translate(offset: Offset(0, 16 * t), child: child),
        );
      },
      child: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.sm,
              AppSpacing.lg,
              0,
            ),
            child: Column(
              children: <Widget>[
                Text.rich(
                  TextSpan(
                    children: <InlineSpan>[
                      TextSpan(text: spec.headingLead),
                      TextSpan(
                        text: spec.headingAccent,
                        style: const TextStyle(color: AppColors.brandOrange),
                      ),
                      TextSpan(text: spec.headingTrail),
                    ],
                    style: TextStyle(
                      fontSize: headingSize,
                      height: 1.22,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.4,
                      color: AppColors.brandNavy,
                    ),
                  ),
                  textAlign: TextAlign.center,
                ),
                SizedBox(height: AppSpacing.sm + 2),
                Text(
                  spec.description,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: bodySize,
                    height: 1.42,
                    fontWeight: FontWeight.w500,
                    color: AppColors.brandBody,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Expanded(
            child: Semantics(
              image: true,
              label: spec.semanticLabel,
              child: Padding(
                // Page 1's photograph is meant to run under the wave panel;
                // the other two hold content that must stay clear of it.
                padding: EdgeInsets.only(
                  bottom: index == 0 ? 0 : reserveBottom * 0.82,
                ),
                child: Builder(builder: spec.illustration),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
