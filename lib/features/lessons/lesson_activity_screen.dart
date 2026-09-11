import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';
import '../../models/lesson_plan.dart';
import 'lesson_navigation.dart';

/// The classroom activity, opened from lesson detail.
///
/// Deliberately small: it shows the steps a teacher follows with the class and
/// nothing else. It needs no connection, because everything it renders came
/// from the lesson plan already cached on the device.
class LessonActivityScreen extends StatelessWidget {
  const LessonActivityScreen({this.args, super.key});

  static const Key startedButtonKey = Key('activity-started');

  /// Falls back to the route argument when not passed directly.
  final LessonActivityArgs? args;

  @override
  Widget build(BuildContext context) {
    final Object? routeArgs = ModalRoute.of(context)?.settings.arguments;
    final LessonActivityArgs? resolved =
        args ?? (routeArgs is LessonActivityArgs ? routeArgs : null);

    if (resolved == null) {
      return const _ActivityUnavailable();
    }

    final ClassroomActivity activity = resolved.activity;

    return Scaffold(
      backgroundColor: AppColors.homePage,
      appBar: AppBar(
        title: const Text('Classroom Activity'),
        backgroundColor: AppColors.homePage,
        foregroundColor: AppColors.brandNavy,
        elevation: 0,
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            final double side =
                ((constraints.maxWidth - 640).clamp(0, 400)) / 2 + 20;

            return ListView(
              padding: EdgeInsets.fromLTRB(side, 8, side, 28),
              children: <Widget>[
                Text(
                  resolved.lessonTitle,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.brandNavy.withValues(alpha: 0.6),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  activity.title,
                  style: const TextStyle(
                    fontSize: 24,
                    height: 1.15,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.4,
                    color: AppColors.brandNavy,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  activity.summary,
                  style: TextStyle(
                    fontSize: 14.5,
                    height: 1.45,
                    color: AppColors.brandNavy.withValues(alpha: 0.78),
                  ),
                ),
                const SizedBox(height: 18),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: <Widget>[
                    _Pill(
                      icon: Icons.schedule,
                      label: '${activity.minutes} min',
                    ),
                    for (final String material in activity.materials)
                      _Pill(icon: Icons.inventory_2_outlined, label: material),
                  ],
                ),
                const SizedBox(height: 24),
                const Text(
                  'Steps',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: AppColors.brandNavy,
                  ),
                ),
                const SizedBox(height: 10),
                for (int i = 0; i < activity.steps.length; i++)
                  _Step(number: i + 1, text: activity.steps[i]),
                const SizedBox(height: 26),
                FilledButton(
                  key: startedButtonKey,
                  onPressed: () => Navigator.of(context).pop(true),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.authNavy,
                    foregroundColor: Colors.white,
                    minimumSize: const Size(0, 54),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: const Text(
                    'Done with this activity',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({required this.number, required this.text});

  final int number;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            width: 26,
            height: 26,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.setupNumeracy.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Text(
              '$number',
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: AppColors.setupNumeracy,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Text(
                text,
                style: const TextStyle(
                  fontSize: 14.5,
                  height: 1.45,
                  color: AppColors.brandBody,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
      decoration: BoxDecoration(
        color: AppColors.authChip,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 15, color: AppColors.brandNavy),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: AppColors.brandNavy,
            ),
          ),
        ],
      ),
    );
  }
}

/// Reached only when the route is opened without an activity — a deep link, or
/// a caller that lost its arguments. It says so rather than showing a blank.
class _ActivityUnavailable extends StatelessWidget {
  const _ActivityUnavailable();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.homePage,
      appBar: AppBar(
        title: const Text('Classroom Activity'),
        backgroundColor: AppColors.homePage,
        foregroundColor: AppColors.brandNavy,
        elevation: 0,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Icon(
                Icons.groups_outlined,
                size: 38,
                color: AppColors.brandMuted,
              ),
              const SizedBox(height: 14),
              const Text(
                "Couldn't open this activity.",
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: AppColors.brandNavy,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Open it from the lesson so it knows which activity to show.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13.5,
                  height: 1.4,
                  color: AppColors.brandNavy.withValues(alpha: 0.7),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
