import 'package:flutter/material.dart';

import '../../app/routes.dart';
import '../../core/constants/app_colors.dart';
import '../../models/assessment_answer.dart';
import '../../models/assessment_question.dart';
import '../../models/assessment_result.dart';
import '../flashcards/flashcards_screen.dart' show FlashcardsArgs;
import '../lessons/lesson_navigation.dart';
import '../worksheet/worksheet_generator_screen.dart'
    show WorksheetGeneratorArgs;
import 'services/assessment_recommendation_service.dart';
import 'widgets/assessment_widgets.dart';

/// What the detailed result screen is opened with.
///
/// The result travels whole rather than being read back by id: it was just
/// computed on the previous screen, and re-reading it would let the two screens
/// disagree about the same assessment.
class AssessmentResultArgs {
  const AssessmentResultArgs({
    required this.result,
    required this.questions,
    this.suggestion,
    this.lessonTitle,
  });

  final QuizResult result;

  /// The questions the result was marked against, so each answer can be shown
  /// beside what was asked.
  final List<QuizQuestion> questions;

  final PracticeSuggestion? suggestion;
  final String? lessonTitle;

  static AssessmentResultArgs? from(Object? arguments) =>
      arguments is AssessmentResultArgs ? arguments : null;
}

/// Question by question, with the marking shown.
///
/// Nothing new is computed here. Every figure comes from the [QuizResult] the
/// assessment screen produced, so the two screens cannot report different
/// scores for the same answers.
class AssessmentResultScreen extends StatelessWidget {
  const AssessmentResultScreen({this.args, super.key});

  static const Key scrollKey = Key('assessment-result-scroll');
  static const Key backKey = Key('assessment-result-back');
  static const Key statusKey = Key('assessment-result-status');
  static const Key suggestionActionKey = Key('assessment-result-action');
  static const Key doneKey = Key('assessment-result-done');

  static Key questionKey(String questionId) =>
      Key('assessment-result-q-$questionId');

  /// Supplied directly by tests; read from the route otherwise.
  final AssessmentResultArgs? args;

  @override
  Widget build(BuildContext context) {
    final AssessmentResultArgs? given = args ??
        AssessmentResultArgs.from(ModalRoute.of(context)?.settings.arguments);

    return Scaffold(
      backgroundColor: AppColors.homePage,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: <Widget>[
            AssessmentHeader(
              status: 'Offline Assessment',
              statusKey: statusKey,
              backKey: backKey,
              onBack: () => Navigator.of(context).maybePop(),
            ),
            Expanded(
              child: given == null
                  ? const _NoResult()
                  : _body(context, given),
            ),
          ],
        ),
      ),
    );
  }

  Widget _body(BuildContext context, AssessmentResultArgs args) {
    final QuizResult result = args.result;

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
                'Assessment Details',
                maxLines: 1,
                style: TextStyle(
                  fontSize: 28,
                  height: 1.1,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.7,
                  color: AppColors.brandNavy,
                ),
              ),
            ),
            if (args.lessonTitle != null) ...<Widget>[
              const SizedBox(height: 4),
              Text(
                args.lessonTitle!,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: AppColors.setupNumeracy,
                ),
              ),
            ],
            const SizedBox(height: 16),
            _summary(result, width),
            const SizedBox(height: 18),
            const _SectionTitle('Concepts'),
            const SizedBox(height: 10),
            ConceptList(
              title: 'Concepts Understood',
              icon: Icons.check_circle_outline,
              colour: AppColors.setupLiteracy,
              concepts: result.understood,
              emptyLabel:
                  'No concept was answered correctly all the way through.',
              showCounts: true,
            ),
            const SizedBox(height: 10),
            ConceptList(
              title: 'Needs Reinforcement',
              icon: Icons.adjust,
              colour: AppColors.brandOrange,
              concepts: result.needsReinforcement,
              emptyLabel:
                  'Every concept in this assessment was answered correctly.',
              showCounts: true,
            ),
            if (args.suggestion != null) ...<Widget>[
              const SizedBox(height: 18),
              const _SectionTitle('What to do next'),
              const SizedBox(height: 10),
              _suggestion(context, args.suggestion!, result.lessonId),
            ],
            const SizedBox(height: 18),
            const _SectionTitle('Every question'),
            const SizedBox(height: 10),
            for (int i = 0; i < args.questions.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _questionRow(args.questions[i], result, i),
              ),
            const SizedBox(height: 6),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                key: doneKey,
                onPressed: () => Navigator.of(context).maybePop(),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.brandNavy,
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  side: const BorderSide(color: AppColors.authFieldBorder),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  textStyle: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                child: const Text('Back to the summary'),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _summary(QuizResult result, double width) {
    final Widget ring = ScoreRing(
      score: result.score,
      total: result.total,
      percentage: result.percentage,
      size: 108,
    );

    final Widget figures = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _Figure(label: 'Correct', value: '${result.score} of ${result.total}'),
        const SizedBox(height: 10),
        _Figure(label: 'Score', value: '${result.percentage}%'),
        const SizedBox(height: 10),
        // "--" rather than "0 sec" when the clock was never running, which is
        // what a result restored from storage looks like.
        _Figure(label: 'Time taken', value: result.durationLabel),
      ],
    );

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.authFieldBorder),
      ),
      child: width < 420
          ? Column(
              children: <Widget>[
                ring,
                const SizedBox(height: 16),
                SizedBox(width: double.infinity, child: figures),
              ],
            )
          : Row(
              children: <Widget>[
                ring,
                const SizedBox(width: 20),
                Expanded(child: figures),
              ],
            ),
    );
  }

  Widget _suggestion(
    BuildContext context,
    PracticeSuggestion suggestion,
    String lessonId,
  ) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 15),
      decoration: BoxDecoration(
        color: AppColors.homeBannerTint,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.secondaryContainer),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            suggestion.headline,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: AppColors.brandNavy,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            suggestion.body,
            style: const TextStyle(
              fontSize: 13.5,
              height: 1.45,
              color: AppColors.brandBody,
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              key: suggestionActionKey,
              onPressed: () => _follow(context, suggestion.action, lessonId),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.authNavy,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(13),
                ),
                textStyle: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
              child: Text(suggestion.action.label),
            ),
          ),
          const SizedBox(height: 9),
          Text(
            suggestion.sourceNote,
            style: const TextStyle(
              fontSize: 11.5,
              height: 1.4,
              fontStyle: FontStyle.italic,
              color: AppColors.brandMuted,
            ),
          ),
        ],
      ),
    );
  }

  /// Opens the screen a suggestion points at. Every branch goes somewhere real.
  void _follow(
    BuildContext context,
    SuggestedAction action,
    String lessonId,
  ) {
    switch (action) {
      case SuggestedAction.worksheet:
        Navigator.of(context).pushNamed(
          AppRoutes.worksheet,
          arguments: WorksheetGeneratorArgs(lessonId),
        );
      case SuggestedAction.flashcards:
        Navigator.of(context).pushNamed(
          AppRoutes.flashcards,
          arguments: FlashcardsArgs(lessonId: lessonId),
        );
      case SuggestedAction.repeatLesson:
      case SuggestedAction.moveOn:
        Navigator.of(context).pushNamed(
          AppRoutes.lessonDetail,
          arguments: LessonDetailArgs(lessonId),
        );
    }
  }

  Widget _questionRow(QuizQuestion question, QuizResult result, int position) {
    final QuizAnswer? answer = result.answers[question.id];
    final QuizOption? chosen = question.optionById(answer?.selectedOptionId);
    final bool right = answer != null && question.isCorrect(chosen?.id);

    final Color accent = right ? AppColors.setupLiteracy : AppColors.error;

    return Container(
      key: questionKey(question.id),
      padding: const EdgeInsets.fromLTRB(13, 12, 13, 13),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.authFieldBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Icon(
                right ? Icons.check_circle : Icons.cancel,
                size: 19,
                color: accent,
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      '${position + 1}. ${question.prompt}',
                      style: const TextStyle(
                        fontSize: 14,
                        height: 1.35,
                        fontWeight: FontWeight.w700,
                        color: AppColors.brandNavy,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      question.concept.label,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.brandMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: <Widget>[
              _Chip(
                // An unanswered question says so rather than showing a blank.
                label: chosen == null
                    ? 'Not answered'
                    : 'Answered ${chosen.label}',
                colour: accent,
              ),
              if (!right)
                _Chip(
                  label: 'Correct answer ${question.correctOption.label}',
                  colour: AppColors.setupLiteracy,
                ),
              if (answer?.timeTaken != null)
                _Chip(
                  label: '${answer!.timeTaken!.inSeconds} sec',
                  colour: AppColors.brandMuted,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: const TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w800,
          color: AppColors.brandNavy,
        ),
      );
}

class _Figure extends StatelessWidget {
  const _Figure({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: <Widget>[
        // "Time taken" beside "2 min 40 sec" is a few pixels too wide for a
        // narrow phone, so both halves give way rather than overflowing.
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
              color: AppColors.brandMuted,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Flexible(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerRight,
            child: Text(
              value,
              maxLines: 1,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: AppColors.brandNavy,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.colour});

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
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: colour,
        ),
      ),
    );
  }
}

/// Shown when the screen is reached without a result, which can only happen
/// through a bad deep link.
class _NoResult extends StatelessWidget {
  const _NoResult();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(
              Icons.bar_chart,
              size: 42,
              color: AppColors.brandMuted,
            ),
            const SizedBox(height: 14),
            const Text(
              'No assessment result to show.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: AppColors.brandNavy,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'This screen shows the details of an assessment that has just '
              'been finished.',
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
