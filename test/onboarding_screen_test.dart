import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gyan_setu_ai/app/routes.dart';
import 'package:gyan_setu_ai/features/auth/login_screen.dart';
import 'package:gyan_setu_ai/features/onboarding/onboarding_screen.dart';
import 'package:gyan_setu_ai/features/onboarding/widgets/page_indicator.dart';
import 'package:gyan_setu_ai/features/onboarding/widgets/translation_showcase.dart';

void main() {
  // `home:`, not `initialRoute:`. A path-like initial route makes Flutter
  // synthesise the routes above it, which would leave a live SplashScreen
  // underneath onboarding — its timer then navigates back on top of whatever
  // the test just did.
  Widget harness() => MaterialApp(
        onGenerateRoute: AppRouter.onGenerateRoute,
        home: const OnboardingScreen(),
      );

  Future<void> swipeLeft(WidgetTester tester) async {
    await tester.drag(find.byType(PageView), const Offset(-420, 0));
    await tester.pumpAndSettle();
  }

  Future<void> swipeRight(WidgetTester tester) async {
    await tester.drag(find.byType(PageView), const Offset(420, 0));
    await tester.pumpAndSettle();
  }

  /// Asserts the dots track the PageView.
  void expectPage(WidgetTester tester, int oneBased) {
    final PageIndicator indicator =
        tester.widget<PageIndicator>(find.byType(PageIndicator));
    expect(indicator.currentIndex, oneBased - 1);
  }

  testWidgets('opens on page 1 with its heading and CTA',
      (WidgetTester tester) async {
    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();

    expect(find.textContaining('Teach in Every'), findsOneWidget);
    expect(find.text('Next'), findsOneWidget);
    expect(find.text('Skip'), findsOneWidget);
    expectPage(tester, 1);
  });

  testWidgets('swipes forward through all three pages and back again',
      (WidgetTester tester) async {
    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();

    await swipeLeft(tester);
    expect(find.textContaining('Speak. Translate.'), findsOneWidget);
    expectPage(tester, 2);

    await swipeLeft(tester);
    expect(find.textContaining('Works '), findsOneWidget);
    expect(find.text('Get Started'), findsOneWidget);
    expectPage(tester, 3);

    await swipeRight(tester);
    expectPage(tester, 2);

    await swipeRight(tester);
    expectPage(tester, 1);
  });

  testWidgets('Next advances one page at a time', (WidgetTester tester) async {
    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expectPage(tester, 2);

    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expectPage(tester, 3);

    // The last page swaps the label rather than advancing further.
    expect(find.text('Next'), findsNothing);
    expect(find.text('Get Started'), findsOneWidget);
  });

  testWidgets('Get Started leaves onboarding for the sign-in route',
      (WidgetTester tester) async {
    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Get Started'));
    await tester.pumpAndSettle();

    expect(find.byType(OnboardingScreen), findsNothing);
    expect(find.byType(LoginScreen), findsOneWidget);

    // Replaced, not pushed: there is nothing to go back to.
    final NavigatorState navigator =
        tester.state<NavigatorState>(find.byType(Navigator));
    expect(navigator.canPop(), isFalse);
  });

  for (int page = 0; page < 3; page++) {
    testWidgets('Skip on page ${page + 1} leaves onboarding',
        (WidgetTester tester) async {
      await tester.pumpWidget(harness());
      await tester.pumpAndSettle();

      for (int i = 0; i < page; i++) {
        await swipeLeft(tester);
      }
      expectPage(tester, page + 1);

      await tester.tap(find.text('Skip'));
      await tester.pumpAndSettle();

      expect(find.byType(OnboardingScreen), findsNothing);
      expect(find.byType(LoginScreen), findsOneWidget);
    });
  }

  testWidgets('system back steps to the previous page before leaving',
      (WidgetTester tester) async {
    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();

    await swipeLeft(tester);
    await swipeLeft(tester);
    expectPage(tester, 3);

    final NavigatorState navigator =
        tester.state<NavigatorState>(find.byType(Navigator));

    await navigator.maybePop();
    await tester.pumpAndSettle();
    expectPage(tester, 2);

    await navigator.maybePop();
    await tester.pumpAndSettle();
    expectPage(tester, 1);

    // On page 1 there is nothing left to step back to.
    expect(navigator.canPop(), isFalse);
  });

  testWidgets('page 2 renders the language chips as real widgets',
      (WidgetTester tester) async {
    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();
    await swipeLeft(tester);

    for (final String language in TranslationShowcase.languages) {
      expect(find.text(language), findsOneWidget);
    }
  });

  testWidgets('page 3 exposes every capability as text, not just artwork',
      (WidgetTester tester) async {
    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();
    await swipeLeft(tester);
    await swipeLeft(tester);

    expect(find.textContaining('Multilingual'), findsOneWidget);
    expect(find.textContaining('Translation'), findsOneWidget);
    expect(find.textContaining('Audio'), findsOneWidget);
    expect(find.textContaining('Worksheets'), findsOneWidget);
    expect(find.text('Offline Mode'), findsOneWidget);
    expect(
      find.text('Reliable learning, even in remote areas.'),
      findsOneWidget,
    );
  });

  testWidgets('the retired brand name appears nowhere in the UI',
      (WidgetTester tester) async {
    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();

    for (int page = 0; page < 3; page++) {
      if (page > 0) await swipeLeft(tester);
      expect(find.textContaining('BhashaSetu'), findsNothing);
      expect(find.textContaining('Bhasha'), findsNothing);
    }
  });

  testWidgets('lays out without overflow on a small handset',
      (WidgetTester tester) async {
    addTearDown(tester.view.reset);
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(320, 640);

    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();

    for (int page = 0; page < 3; page++) {
      if (page > 0) await swipeLeft(tester);
      expect(tester.takeException(), isNull, reason: 'page ${page + 1} threw');
    }
  });
}
