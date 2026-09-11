import 'package:flutter/material.dart';

import '../../core/widgets/feature_placeholder.dart';

/// Resources screen.
///
/// TODO(gyansetu): replace the placeholder with the real Resources UI.
class ResourcesScreen extends StatelessWidget {
  const ResourcesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const FeaturePlaceholder(
      title: 'Resources',
      description: 'Every teaching tool in one place.',
    );
  }
}
