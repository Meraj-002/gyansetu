import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/constants/app_strings.dart';
import '../services/service_registry.dart';
import 'app_settings.dart';
import 'routes.dart';
import 'theme.dart';

/// Root widget: installs app-wide providers, theme and the route table.
///
/// No screen UI belongs here. Screens live under `lib/features/` and are
/// reached only through [AppRouter].
class GyanSetuApp extends StatefulWidget {
  const GyanSetuApp({super.key});

  @override
  State<GyanSetuApp> createState() => _GyanSetuAppState();
}

class _GyanSetuAppState extends State<GyanSetuApp> {
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();

  @override
  void initState() {
    super.initState();
    ServiceRegistry.instance.session.setUnauthorizedHandler(_openLogin);
  }

  @override
  void dispose() {
    ServiceRegistry.instance.session.setUnauthorizedHandler(null);
    super.dispose();
  }

  Future<void> _openLogin() async {
    final NavigatorState? navigator = _navigatorKey.currentState;
    if (navigator == null) return;
    navigator.pushAndRemoveUntil(
      AppRouter.fadeRoute<void>(const RouteSettings(name: AppRoutes.auth)),
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<AppSettings>(create: (_) => AppSettings()),
        // Service providers are registered here as each service gains a
        // concrete implementation (database, API client, sync, audio).
      ],
      child: Consumer<AppSettings>(
        builder: (BuildContext context, AppSettings settings, Widget? child) {
          return MaterialApp(
            title: AppStrings.appName,
            debugShowCheckedModeBanner: false,
            navigatorKey: _navigatorKey,
            theme: AppTheme.light,
            darkTheme: AppTheme.dark,
            themeMode: settings.themeMode,
            initialRoute: AppRoutes.splash,
            onGenerateRoute: AppRouter.onGenerateRoute,
            // Accessibility overrides live above the Navigator so they reach
            // every screen, and only engage when the Settings screen has
            // changed them from the defaults.
            builder: (BuildContext context, Widget? navigator) {
              final MediaQueryData mq = MediaQuery.of(context);
              return MediaQuery(
                data: mq.copyWith(
                  textScaler: TextScaler.linear(settings.textScale),
                ),
                child: Theme(
                  data: settings.highContrast
                      ? _highContrastTheme(Theme.of(context))
                      : Theme.of(context),
                  child: navigator ?? const SizedBox.shrink(),
                ),
              );
            },
            // NOTE: `locale` / `supportedLocales` are deliberately not wired up
            // yet. Flutter's bundled localisations do not cover Santali, so
            // enabling them now would throw at runtime. They get set once
            // flutter_localizations and the ARB files land.
          );
        },
      ),
    );
  }
}

/// The high-contrast variant: the surface pair goes to pure black/white and
/// text colours move to their extreme, while the brand palette stays intact.
ThemeData _highContrastTheme(ThemeData base) {
  final bool dark = base.brightness == Brightness.dark;
  final Color foreground = dark ? Colors.white : const Color(0xFF000000);
  final Color background = dark ? const Color(0xFF000000) : Colors.white;
  return base.copyWith(
    colorScheme: base.colorScheme.copyWith(
      surface: background,
      onSurface: foreground,
    ),
    textTheme: base.textTheme.apply(
      bodyColor: foreground,
      displayColor: foreground,
    ),
  );
}
