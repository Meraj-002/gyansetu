import 'package:flutter/material.dart';

import '../../core/widgets/feature_placeholder.dart';

/// Notifications screen.
///
/// TODO(gyansetu): replace the placeholder with the real Notifications UI.
class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const FeaturePlaceholder(
      title: 'Notifications',
      description: 'Sync results, content updates and classroom reminders.',
    );
  }
}
