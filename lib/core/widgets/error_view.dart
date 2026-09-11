import 'package:flutter/material.dart';

import '../constants/app_spacing.dart';

/// Full-area error state with an optional retry action.
class ErrorView extends StatelessWidget {
  const ErrorView({required this.message, this.onRetry, this.retryLabel = 'Try again', super.key});

  final String message;
  final VoidCallback? onRetry;
  final String retryLabel;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: AppSpacing.screen,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 40, color: theme.colorScheme.error),
            AppSpacing.gapMd,
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyLarge,
            ),
            if (onRetry != null) ...[
              AppSpacing.gapLg,
              OutlinedButton(onPressed: onRetry, child: Text(retryLabel)),
            ],
          ],
        ),
      ),
    );
  }
}
