import '../../../models/question.dart';
import '../../../models/worksheet.dart';
import 'worksheet_generation_service.dart';

/// Something wrong with a generated worksheet.
class WorksheetProblem {
  const WorksheetProblem(this.message, {this.questionId});

  /// Plain language, because some of these reach the teacher.
  final String message;

  final String? questionId;

  @override
  String toString() =>
      questionId == null ? message : '$questionId: $message';
}

/// Checks a worksheet before anybody sees it.
///
/// A generator that miscounts, leaves a question blank or answers its own
/// question with nothing is a generator that would otherwise put a broken sheet
/// in front of a class. This runs on every worksheet, whoever produced it —
/// the local generator today, a model tomorrow — because a model is exactly the
/// kind of thing that returns nine questions when asked for ten.
abstract final class WorksheetValidator {
  static List<WorksheetProblem> validate(
    Worksheet worksheet,
    WorksheetGenerationRequest request,
  ) {
    final List<WorksheetProblem> problems = <WorksheetProblem>[];

    if (worksheet.questions.length != request.numberOfQuestions) {
      problems.add(
        WorksheetProblem(
          'The worksheet has ${worksheet.questions.length} questions but '
          '${request.numberOfQuestions} were asked for.',
        ),
      );
    }

    if (worksheet.lessonId != request.lessonId) {
      problems.add(
        const WorksheetProblem(
          'The worksheet was built for a different lesson.',
        ),
      );
    }

    if (worksheet.learningOutcome.trim().isEmpty) {
      problems.add(
        const WorksheetProblem('The worksheet has no learning outcome.'),
      );
    }

    final Set<String> seenIds = <String>{};
    for (final WorksheetQuestion question in worksheet.questions) {
      if (!seenIds.add(question.id)) {
        problems.add(
          WorksheetProblem(
            'Two questions share an id.',
            questionId: question.id,
          ),
        );
      }
      if (question.questionText.trim().isEmpty) {
        problems.add(
          WorksheetProblem('The question is empty.', questionId: question.id),
        );
      }
      if (question.correctAnswer.trim().isEmpty) {
        problems.add(
          WorksheetProblem(
            'The question has no answer.',
            questionId: question.id,
          ),
        );
      }
      if (!request.questionTypes.contains(question.type)) {
        problems.add(
          WorksheetProblem(
            'The question is a kind the teacher did not ask for.',
            questionId: question.id,
          ),
        );
      }
      // A multiple-choice question whose answer is not among its options is
      // unanswerable, which is worse than having no options at all.
      if (question.options.isNotEmpty &&
          !question.options.contains(question.correctAnswer)) {
        problems.add(
          WorksheetProblem(
            'The answer is not one of the options.',
            questionId: question.id,
          ),
        );
      }
    }

    return problems;
  }

  /// True when the worksheet is fit to show.
  static bool isValid(
    Worksheet worksheet,
    WorksheetGenerationRequest request,
  ) =>
      validate(worksheet, request).isEmpty;
}
