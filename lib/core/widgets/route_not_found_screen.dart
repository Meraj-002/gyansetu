import 'package:flutter/material.dart';

import 'error_view.dart';

/// Fallback rendered by `AppRouter` when a route name has no registered
/// builder. Reaching this screen is a programming error, not a user error.
class RouteNotFoundScreen extends StatelessWidget {
  const RouteNotFoundScreen({required this.routeName, super.key});

  final String? routeName;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Page not found')),
      body: ErrorView(message: 'No screen is registered for "${routeName ?? 'unknown'}".'),
    );
  }
}
