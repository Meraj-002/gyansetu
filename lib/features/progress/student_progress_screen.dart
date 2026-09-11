import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';
import '../../models/student_progress.dart';
import 'models/learning_insights.dart';
import 'widgets/progress_widgets.dart';

/// What the students screen is opened with.
class StudentProgressArgs {
  const StudentProgressArgs({
    required this.group,
    required this.students,
    required this.usesPrototypeData,
    this.classLabel,
  });

  /// The concept these children are behind on.
  final AttentionGroup group;

  final List<StudentProgress> students;

  /// True while these records come from the sample class rather than a roster
  /// somebody entered. The screen says so at the top, unmissably.
  final bool usesPrototypeData;

  final String? classLabel;

  static StudentProgressArgs? from(Object? arguments) =>
      arguments is StudentProgressArgs ? arguments : null;
}

/// The children behind on one concept.
///
/// This is a reading of pupil records, not a pupil management screen: there is
/// nothing to edit here, because nothing in this app writes pupil records yet.
class StudentProgressScreen extends StatelessWidget {
  const StudentProgressScreen({this.args, super.key});

  static const Key scrollKey = Key('students-scroll');
  static const Key backKey = Key('students-back');
  static const Key statusKey = Key('students-status');
  static const Key sampleDataKey = Key('students-sample-data');

  static Key studentKey(String studentId) => Key('students-$studentId');

  /// Supplied directly by tests; read from the route otherwise.
  final StudentProgressArgs? args;

  @override
  Widget build(BuildContext context) {
    final StudentProgressArgs? given = args ??
        StudentProgressArgs.from(ModalRoute.of(context)?.settings.arguments);

    return Scaffold(
      backgroundColor: AppColors.homePage,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: <Widget>[
            InsightsHeader(
              backKey: backKey,
              statusKey: statusKey,
              onBack: () => Navigator.of(context).maybePop(),
            ),
            Expanded(
              child: given == null ? const _NoStudents() : _body(context, given),
            ),
          ],
        ),
      ),
    );
  }

  Widget _body(BuildContext context, StudentProgressArgs args) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double width = constraints.maxWidth;
        final double contentWidth = width.clamp(0.0, 720.0);
        final double side = ((width - contentWidth) / 2) + 16;

        return ListView(
          key: scrollKey,
          padding: EdgeInsets.fromLTRB(side, 2, side, 26),
          children: <Widget>[
            const FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                'Learners to support',
                maxLines: 1,
                style: TextStyle(
                  fontSize: 28,
                  height: 1.1,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.8,
                  color: AppColors.brandNavy,
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              args.group.concept,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: AppColors.setupNumeracy,
              ),
            ),
            if (args.classLabel != null) ...<Widget>[
              const SizedBox(height: 2),
              Text(
                args.classLabel!,
                style: const TextStyle(
                  fontSize: 13,
                  color: AppColors.brandMuted,
                ),
              ),
            ],
            const SizedBox(height: 14),
            if (args.usesPrototypeData) ...<Widget>[
              const InsightNotice(
                key: sampleDataKey,
                message: 'These are sample pupil records, not real children. '
                    'No roster has been entered on this device, and nothing in '
                    'the app writes pupil records yet.',
              ),
              const SizedBox(height: 14),
            ],
            Container(
              padding: const EdgeInsets.fromLTRB(14, 13, 14, 14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.authFieldBorder),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    args.group.headline,
                    style: const TextStyle(
                      fontSize: 15,
                      height: 1.35,
                      fontWeight: FontWeight.w800,
                      color: AppColors.brandNavy,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    args.group.detail,
                    style: const TextStyle(
                      fontSize: 13,
                      height: 1.45,
                      color: AppColors.brandBody,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            if (args.students.isEmpty)
              const InsightNotice(
                icon: Icons.person_outline,
                tint: AppColors.setupNumeracy,
                background: AppColors.setupNumeracyTint,
                border: AppColors.authFieldBorder,
                message: 'No pupil records are available, so the concept is '
                    'reported for the class rather than for named children.',
              )
            else
              for (final StudentProgress s in args.students)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _StudentRow(student: s, concept: args.group.concept),
                ),
          ],
        );
      },
    );
  }
}

class _StudentRow extends StatelessWidget {
  const _StudentRow({required this.student, required this.concept});

  final StudentProgress student;
  final String concept;

  @override
  Widget build(BuildContext context) {
    final int? average = student.averageScore;

    return Container(
      key: StudentProgressScreen.studentKey(student.studentId),
      padding: const EdgeInsets.fromLTRB(13, 12, 13, 13),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: AppColors.authFieldBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              StudentAvatar(student: student, size: 44),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      student.name,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: AppColors.brandNavy,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      // A dash, not a zero, when this child has not been
                      // assessed: unknown and nought are different things.
                      average == null
                          ? 'Not assessed yet  •  '
                              '${student.lessonsCompleted} lesson'
                              '${student.lessonsCompleted == 1 ? '' : 's'} done'
                          : 'Average $average%  •  '
                              '${student.lessonsCompleted} lesson'
                              '${student.lessonsCompleted == 1 ? '' : 's'} done',
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: AppColors.brandMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 7,
            runSpacing: 7,
            children: <Widget>[
              for (final String c in student.conceptsNeedingPractice)
                _ConceptChip(
                  label: c,
                  colour: c.toLowerCase() == concept.toLowerCase()
                      ? AppColors.error
                      : AppColors.warning,
                ),
              for (final String c in student.conceptsMastered)
                _ConceptChip(label: c, colour: AppColors.setupLiteracy),
            ],
          ),
        ],
      ),
    );
  }
}

class _ConceptChip extends StatelessWidget {
  const _ConceptChip({required this.label, required this.colour});

  final String label;
  final Color colour;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: colour.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: colour.withValues(alpha: 0.3)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
          color: colour,
        ),
      ),
    );
  }
}

/// Shown when the screen is reached without a group, which can only happen
/// through a bad deep link.
class _NoStudents extends StatelessWidget {
  const _NoStudents();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(
              Icons.groups_outlined,
              size: 42,
              color: AppColors.brandMuted,
            ),
            const SizedBox(height: 14),
            const Text(
              'No learners to show.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: AppColors.brandNavy,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'This screen lists the children behind on one concept, opened '
              'from Learning Insights.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                height: 1.45,
                color: AppColors.brandMuted,
              ),
            ),
            const SizedBox(height: 16),
            TextButton(
              onPressed: () => Navigator.of(context).maybePop(),
              child: const Text('Back'),
            ),
          ],
        ),
      ),
    );
  }
}
