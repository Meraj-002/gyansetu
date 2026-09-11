import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';
import '../../models/lesson_plan.dart';
import 'lesson_navigation.dart';

/// The quick assessment, opened from lesson detail.
///
/// Teacher-driven and offline by design: the teacher asks the child the
/// question in front of them and marks what happened. There is no scoring
/// engine and no network call, because neither would make the judgement any
/// more accurate than the teacher's.
class LessonAssessmentScreen extends StatefulWidget {
  const LessonAssessmentScreen({this.args, super.key});

  static const Key saveButtonKey = Key('assessment-save');

  static Key outcomeKey(String questionId, AssessmentOutcome outcome) =>
      Key('assessment-$questionId-${outcome.name}');

  final LessonAssessmentArgs? args;

  @override
  State<LessonAssessmentScreen> createState() => _LessonAssessmentScreenState();
}

class _LessonAssessmentScreenState extends State<LessonAssessmentScreen> {
  final Map<String, AssessmentOutcome> _outcomes =
      <String, AssessmentOutcome>{};

  LessonAssessmentArgs? _resolved;
  bool _restored = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_restored) return;
    _restored = true;

    final Object? routeArgs = ModalRoute.of(context)?.settings.arguments;
    _resolved =
        widget.args ?? (routeArgs is LessonAssessmentArgs ? routeArgs : null);

    // Reopening shows what was marked last time rather than a blank sheet, so
    // a teacher correcting one answer does not have to redo the others.
    final AssessmentResult? previous = _resolved?.previous;
    if (previous != null) _outcomes.addAll(previous.outcomes);
  }

  bool get _complete =>
      _resolved != null &&
      _resolved!.assessment.questions
          .every((AssessmentQuestion q) => _outcomes.containsKey(q.id));

  void _save() {
    final LessonAssessmentArgs? args = _resolved;
    if (args == null || !_complete) return;

    Navigator.of(context).pop(
      AssessmentResult(
        lessonId: args.lessonId,
        assessmentId: args.assessment.id,
        outcomes: Map<String, AssessmentOutcome>.from(_outcomes),
        recordedAt: DateTime.now(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final LessonAssessmentArgs? args = _resolved;
    if (args == null) return const _AssessmentUnavailable();

    final QuickAssessment assessment = args.assessment;

    return Scaffold(
      backgroundColor: AppColors.homePage,
      appBar: AppBar(
        title: const Text('Quick Assessment'),
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
                  args.lessonTitle,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.brandNavy.withValues(alpha: 0.6),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  assessment.summary,
                  style: const TextStyle(
                    fontSize: 22,
                    height: 1.2,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.4,
                    color: AppColors.brandNavy,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Ask each question, then mark what the child did. Nothing '
                  'here needs an internet connection.',
                  style: TextStyle(
                    fontSize: 13.5,
                    height: 1.45,
                    color: AppColors.brandNavy.withValues(alpha: 0.7),
                  ),
                ),
                const SizedBox(height: 20),
                for (final AssessmentQuestion question in assessment.questions)
                  _QuestionCard(
                    question: question,
                    selected: _outcomes[question.id],
                    onSelect: (AssessmentOutcome outcome) => setState(
                      () => _outcomes[question.id] = outcome,
                    ),
                  ),
                const SizedBox(height: 10),
                FilledButton(
                  key: LessonAssessmentScreen.saveButtonKey,
                  onPressed: _complete ? _save : null,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.setupLiteracy,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor:
                        AppColors.brandMuted.withValues(alpha: 0.25),
                    minimumSize: const Size(0, 54),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: Text(
                    _complete
                        ? 'Save result'
                        : 'Mark every question to save',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
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

class _QuestionCard extends StatelessWidget {
  const _QuestionCard({
    required this.question,
    required this.selected,
    required this.onSelect,
  });

  final AssessmentQuestion question;
  final AssessmentOutcome? selected;
  final ValueChanged<AssessmentOutcome> onSelect;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.authFieldBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            question.prompt,
            style: const TextStyle(
              fontSize: 15.5,
              height: 1.35,
              fontWeight: FontWeight.w700,
              color: AppColors.brandNavy,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            question.successCriteria,
            style: TextStyle(
              fontSize: 13,
              height: 1.4,
              color: AppColors.brandNavy.withValues(alpha: 0.65),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: <Widget>[
              Expanded(
                child: _OutcomeButton(
                  questionId: question.id,
                  outcome: AssessmentOutcome.achieved,
                  icon: Icons.check_circle_outline,
                  tint: AppColors.setupLiteracy,
                  active: selected == AssessmentOutcome.achieved,
                  onTap: () => onSelect(AssessmentOutcome.achieved),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _OutcomeButton(
                  questionId: question.id,
                  outcome: AssessmentOutcome.notYet,
                  icon: Icons.access_time,
                  tint: AppColors.warning,
                  active: selected == AssessmentOutcome.notYet,
                  onTap: () => onSelect(AssessmentOutcome.notYet),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _OutcomeButton extends StatelessWidget {
  const _OutcomeButton({
    required this.questionId,
    required this.outcome,
    required this.icon,
    required this.tint,
    required this.active,
    required this.onTap,
  });

  final String questionId;
  final AssessmentOutcome outcome;
  final IconData icon;
  final Color tint;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: active,
      label: outcome.label,
      child: ExcludeSemantics(
        child: OutlinedButton.icon(
          key: LessonAssessmentScreen.outcomeKey(questionId, outcome),
          onPressed: onTap,
          icon: Icon(icon, size: 18),
          label: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              outcome.label,
              maxLines: 1,
              style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
            ),
          ),
          style: OutlinedButton.styleFrom(
            foregroundColor: active ? tint : AppColors.brandNavy,
            backgroundColor: active ? tint.withValues(alpha: 0.10) : null,
            minimumSize: const Size(0, 46),
            padding: const EdgeInsets.symmetric(horizontal: 8),
            side: BorderSide(
              color: active ? tint : AppColors.authFieldBorder,
              width: active ? 1.6 : 1,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
      ),
    );
  }
}

class _AssessmentUnavailable extends StatelessWidget {
  const _AssessmentUnavailable();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.homePage,
      appBar: AppBar(
        title: const Text('Quick Assessment'),
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
                Icons.assignment_outlined,
                size: 38,
                color: AppColors.brandMuted,
              ),
              const SizedBox(height: 14),
              const Text(
                "Couldn't load the assessment.",
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: AppColors.brandNavy,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Open it from the lesson so it knows which questions to ask.',
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
