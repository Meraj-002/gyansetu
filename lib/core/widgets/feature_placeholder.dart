import 'package:flutter/material.dart';

import '../constants/app_spacing.dart';

/// Scaffolding stand-in for a screen that has not been implemented yet.
///
/// Every feature screen currently renders one of these. As each feature is
/// built, its screen replaces the [FeaturePlaceholder] with real UI — this
/// widget is then deleted, and nothing should be built on top of it.
class FeaturePlaceholder extends StatelessWidget {
  const FeaturePlaceholder({required this.title, required this.description, super.key});

  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Center(
        child: Padding(
          padding: AppSpacing.screen,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.construction_outlined,
                size: 40,
                color: theme.colorScheme.secondary,
              ),
              AppSpacing.gapMd,
              Text(title, style: theme.textTheme.headlineSmall, textAlign: TextAlign.center),
              AppSpacing.gapSm,
              Text(
                description,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
