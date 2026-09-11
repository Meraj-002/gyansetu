import 'package:flutter/material.dart';

import '../constants/app_spacing.dart';

/// Centred progress indicator with an optional caption.
class LoadingIndicator extends StatelessWidget {
  const LoadingIndicator({this.label, super.key});

  final String? label;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          if (label != null) ...[
            AppSpacing.gapMd,
            Text(label!, style: Theme.of(context).textTheme.bodyMedium),
          ],
        ],
      ),
    );
  }
}
