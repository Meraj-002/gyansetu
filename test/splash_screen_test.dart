import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gyan_setu_ai/app/routes.dart';
import 'package:gyan_setu_ai/core/constants/app_assets.dart';
import 'package:gyan_setu_ai/features/onboarding/onboarding_screen.dart';
import 'package:gyan_setu_ai/features/splash/splash_screen.dart';

void main() {
  Widget harness({Duration? displayDuration}) {
    return MaterialApp(
      onGenerateRoute: AppRouter.onGenerateRoute,
      home: SplashScreen(
        displayDuration: displayDuration ?? SplashScreen.defaultDisplayDuration,
      ),
    );
  }

  /// Lets the navigation timer fire and the cross-fade finish, so that nothing
  /// outlives the test.
  Future<void> settleThroughNavigation(
    WidgetTester tester,
    Duration displayDuration,
  ) async {
    await tester.pump(displayDuration + const Duration(milliseconds: 10));
    await tester.pumpAndSettle();
  }

  testWidgets('renders the splash artwork full-bleed', (WidgetTester tester) async {
    const Duration display = Duration(milliseconds: 100);
    await tester.pumpWidget(harness(displayDuration: display));
    await tester.pump();

    final Image image = tester.widget<Image>(find.byType(Image));
    expect((image.image as AssetImage).assetName, AppAssets.splashArtwork);

    // Full-bleed: the splash must not be inset by a SafeArea.
    expect(find.byType(SafeArea), findsNothing);

    await settleThroughNavigation(tester, display);
  });

  testWidgets('navigates to onboarding once the delay elapses',
      (WidgetTester tester) async {
    const Duration display = Duration(milliseconds: 100);
    await tester.pumpWidget(harness(displayDuration: display));
    await tester.pump();

    expect(find.byType(OnboardingScreen), findsNothing);

    await settleThroughNavigation(tester, display);

    expect(find.byType(OnboardingScreen), findsOneWidget);
  });

  testWidgets('replaces the splash so back cannot return to it',
      (WidgetTester tester) async {
    const Duration display = Duration(milliseconds: 100);
    await tester.pumpWidget(harness(displayDuration: display));
    await settleThroughNavigation(tester, display);

    expect(find.byType(SplashScreen), findsNothing);

    // Nothing left underneath: popping would leave the navigator empty rather
    // than reveal the splash again.
    final NavigatorState navigator =
        tester.state<NavigatorState>(find.byType(Navigator));
    expect(navigator.canPop(), isFalse);
  });

  testWidgets('cancels its timer when disposed before the delay elapses',
      (WidgetTester tester) async {
    await tester.pumpWidget(harness());
    await tester.pump();

    // Tear the splash down early, then run the clock past when the timer would
    // have fired. A leaked timer fails the test at teardown.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(
      SplashScreen.defaultDisplayDuration + const Duration(seconds: 1),
    );

    expect(tester.takeException(), isNull);
  });

  testWidgets('adapts the fit to the viewport aspect ratio',
      (WidgetTester tester) async {
    addTearDown(tester.view.reset);
    const Duration display = Duration(milliseconds: 100);

    Future<BoxFit?> fitFor(Size physicalSize) async {
      // Tear the previous tree down first. Pumping another MaterialApp of the
      // same type only updates the existing element tree, and the Navigator
      // would keep the route it had already advanced to.
      await tester.pumpWidget(const SizedBox.shrink());

      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = physicalSize;

      await tester.pumpWidget(harness(displayDuration: display));
      await tester.pump();
      final BoxFit? fit = tester.widget<Image>(find.byType(Image)).fit;

      await settleThroughNavigation(tester, display);
      return fit;
    }

    // 9:19.5 — the shape the artwork was drawn for.
    expect(await fitFor(const Size(1080, 2340)), BoxFit.cover);

    // 9:16 — a budget handset. Cover crops ~18% of decorative margin, which is
    // acceptable, so it stays edge-to-edge.
    expect(await fitFor(const Size(1080, 1920)), BoxFit.cover);

    // Landscape. Covering here would cut away the tagline, so the artwork is
    // letterboxed against its own edge colours instead.
    expect(await fitFor(const Size(2340, 1080)), BoxFit.contain);
  });

  test('fitFor never distorts and degrades safely', () {
    expect(SplashScreen.fitFor(const Size(1080, 2340)), BoxFit.cover);
    expect(SplashScreen.fitFor(const Size(1080, 2600)), BoxFit.cover);
    expect(SplashScreen.fitFor(Size.zero), BoxFit.contain);
    expect(
      const <BoxFit>[BoxFit.cover, BoxFit.contain],
      contains(SplashScreen.fitFor(const Size(1600, 1200))),
    );
  });
}
