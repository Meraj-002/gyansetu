import 'package:flutter/material.dart';

import 'app/app.dart';

/// Entry point for GyanSetu AI.
///
/// Bootstrap only. Screen UI belongs in `lib/features/<feature>/`, the root
/// widget in `lib/app/app.dart`, and the route table in `lib/app/routes.dart`.
void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // Service initialisation (SQLite, preferences, sync scheduler) goes here,
  // before runApp, as each service gains a concrete implementation.

  runApp(const GyanSetuApp());
}
