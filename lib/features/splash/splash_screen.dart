import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/routes.dart';
import '../../core/constants/app_assets.dart';
import '../../services/storage/secure_storage_service.dart';
import '../auth/services/auth_session_store.dart';

/// Branded entry screen.
///
/// Shows the GyanSetu AI artwork for [displayDuration], then cross-fades to
/// onboarding. Deliberately does no work beyond rendering: no network calls, no
/// database opening, no model loading. Anything heavier belongs after
/// onboarding, where it can show real progress instead of stalling a splash.
class SplashScreen extends StatefulWidget {
  const SplashScreen({this.displayDuration = defaultDisplayDuration, super.key});

  /// How long the artwork stays up before onboarding takes over.
  static const Duration defaultDisplayDuration = Duration(milliseconds: 2800);

  /// Overridable so tests do not have to wait out the real delay.
  final Duration displayDuration;

  /// Smallest share of the artwork's height that may stay visible before
  /// [BoxFit.cover] is abandoned. Covering always crops the overflowing axis;
  /// below this threshold the crop starts eating the supporting line near the
  /// base of the cream panel.
  static const double minVisibleArtworkHeight = 0.72;

  /// Chooses how the artwork fills the screen.
  ///
  /// The artwork is drawn at roughly 9:19.5, the shape of a current phone, so
  /// on any portrait handset [BoxFit.cover] fills the display edge to edge with
  /// no distortion and crops only decorative margin — 18% at the extreme of a
  /// 9:16 budget device.
  ///
  /// A landscape or otherwise very wide viewport is a different matter: there
  /// covering would scale the artwork to the width and cut away most of its
  /// height, including the tagline. Past [minVisibleArtworkHeight] the fit
  /// falls back to [BoxFit.contain], and [_edgeGradient] fills the side margins
  /// with the artwork's own edge colours so the seam is invisible.
  static BoxFit fitFor(Size viewport) {
    if (viewport.width <= 0 || viewport.height <= 0) return BoxFit.contain;

    final double viewportAspect = viewport.width / viewport.height;
    if (viewportAspect <= AppAssets.splashArtworkAspectRatio) {
      // Viewport is narrower than the artwork: covering crops the sides, which
      // are decorative pattern. Always safe.
      return BoxFit.cover;
    }

    final double visibleHeight =
        AppAssets.splashArtworkAspectRatio / viewportAspect;
    return visibleHeight >= minVisibleArtworkHeight
        ? BoxFit.cover
        : BoxFit.contain;
  }

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  static const Duration _fadeInDuration = Duration(milliseconds: 600);

  late final AnimationController _fadeController;
  late final Animation<double> _fadeIn;
  Timer? _navigationTimer;

  @override
  void initState() {
    super.initState();

    _fadeController = AnimationController(
      vsync: this,
      duration: _fadeInDuration,
    );
    _fadeIn = CurvedAnimation(parent: _fadeController, curve: Curves.easeOut);
    _fadeController.forward();

    _navigationTimer = Timer(widget.displayDuration, _openOnboarding);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Decode the artwork before the first paint so the fade-in reveals the
    // image rather than an empty background.
    precacheImage(const AssetImage(AppAssets.splashArtwork), context);
  }

  @override
  void dispose() {
    // Both must be released here: a pending timer would fire against a dead
    // element, and an undisposed controller leaks its ticker.
    _navigationTimer?.cancel();
    _navigationTimer = null;
    _fadeController.dispose();
    super.dispose();
  }

  void _openOnboarding() {
    if (!mounted) return;
    _checkSessionAndRoute();
  }

  Future<void> _checkSessionAndRoute() async {
    try {
      final AuthSessionStore session = AuthSessionStore(
        PlatformSecureStorageService(),
      );
      final bool hasSession = await session.hasUsableOfflineAccount();
      if (!mounted) return;

      if (hasSession) {
        final bool setupDone = await session.isClassroomSetupComplete();
        if (!mounted) return;

        AppRouter.replaceWithFade(
          context,
          setupDone ? AppRoutes.home : AppRoutes.setup,
        );
      } else {
        AppRouter.replaceWithFade(context, AppRoutes.onboarding);
      }
    } on Object {
      if (!mounted) return;
      AppRouter.replaceWithFade(context, AppRoutes.onboarding);
    }
  }

  /// Sampled from the artwork's own left and right edges, so letterbox margins
  /// continue the image instead of framing it.
  static const LinearGradient _edgeGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: <Color>[
      Color(0xFF031338), // deep navy, top of the artwork
      Color(0xFF051D4C), // navy just above the gold curve
      Color(0xFFF5A437), // the gold seam
      Color(0xFFF6F0EB), // cream, immediately below it
      Color(0xFFEDE0D1), // warm cream at the base
    ],
    stops: <double>[0.0, 0.48, 0.50, 0.52, 1.0],
  );

  static const SystemUiOverlayStyle _overlayStyle = SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    statusBarBrightness: Brightness.dark,
    systemNavigationBarColor: Color(0xFFEDE0D1),
    systemNavigationBarIconBrightness: Brightness.dark,
  );

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: _overlayStyle,
      // The splash is transient boot state, not a destination. Blocking pop
      // keeps back from tearing it down mid-timer and leaving a bare navigator;
      // once onboarding replaces it there is nothing to come back to.
      child: PopScope(
        canPop: false,
        child: Scaffold(
          // Painted rather than left transparent so no white flashes through
          // before the image decodes.
          backgroundColor: const Color(0xFF031338),
          // No SafeArea here on purpose: the artwork is meant to run under the
          // status and navigation bars. Legibility is handled by tinting the
          // system bars in [_overlayStyle] instead of insetting the image.
          body: LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) {
              return DecoratedBox(
                decoration: const BoxDecoration(gradient: _edgeGradient),
                child: FadeTransition(
                  opacity: _fadeIn,
                  child: SizedBox.expand(
                    child: Image.asset(
                      AppAssets.splashArtwork,
                      fit: SplashScreen.fitFor(constraints.biggest),
                      alignment: Alignment.center,
                      filterQuality: FilterQuality.medium,
                      excludeFromSemantics: true,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
