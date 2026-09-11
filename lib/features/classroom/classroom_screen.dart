import 'package:flutter/material.dart';

import '../../core/widgets/feature_placeholder.dart';

/// Classroom screen.
///
/// TODO(gyansetu): replace the placeholder with the real Classroom UI.
class ClassroomScreen extends StatelessWidget {
  const ClassroomScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const FeaturePlaceholder(
      title: 'Classroom',
      description: 'Live teaching mode with speech-to-text and text-to-speech.',
    );
  }
}
