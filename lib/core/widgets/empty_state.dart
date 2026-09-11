import 'package:flutter/material.dart';

import '../constants/app_spacing.dart';

/// Shown when a list or collection has no content yet.
class EmptyState extends StatelessWidget {
  const EmptyState({required this.title, this.description, this.icon = Icons.inbox_outlined, super.key});

  final String title;
  final String? description;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: AppSpacing.screen,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 40, color: theme.colorScheme.onSurfaceVariant),
            AppSpacing.gapMd,
            Text(title, textAlign: TextAlign.center, style: theme.textTheme.titleMedium),
            if (description != null) ...[
              AppSpacing.gapSm,
              Text(
                description!,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
