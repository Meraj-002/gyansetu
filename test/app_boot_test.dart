import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gyan_setu_ai/app/app.dart';
import 'package:gyan_setu_ai/app/app_settings.dart';
import 'package:gyan_setu_ai/app/routes.dart';
import 'package:gyan_setu_ai/features/splash/splash_screen.dart';
import 'package:provider/provider.dart';

void main() {
  /// Runs the clock past the splash's navigation timer so no timer outlives a
  /// test that happened to mount it.
  Future<void> flushSplash(WidgetTester tester) async {
    await tester.pump(
      SplashScreen.defaultDisplayDuration + const Duration(milliseconds: 10),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('app boots to the splash screen', (WidgetTester tester) async {
    await tester.pumpWidget(const GyanSetuApp());
    await tester.pump();

    expect(find.byType(SplashScreen), findsOneWidget);
    expect(tester.takeException(), isNull);

    await flushSplash(tester);
  });

  testWidgets('every registered route builds without error',
      (WidgetTester tester) async {
    for (final String route in AppRouter.registeredRoutes) {
      await tester.pumpWidget(
        ChangeNotifierProvider<AppSettings>(
          create: (_) => AppSettings(),
          child: MaterialApp(
            initialRoute: route,
            onGenerateRoute: AppRouter.onGenerateRoute,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'route $route threw');

      await flushSplash(tester);
    }
  });

  testWidgets('an unregistered route falls back to the not-found screen',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        initialRoute: '/does-not-exist',
        onGenerateRoute: AppRouter.onGenerateRoute,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Page not found'), findsOneWidget);
  });
}
