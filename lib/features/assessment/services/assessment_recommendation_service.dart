import '../../../models/assessment_result.dart';

/// Something the teacher can do next, that this app can actually open.
///
/// A suggestion that named a feature which does not exist would be worse than
/// no suggestion, so this is a closed set the result screen knows how to route.
enum SuggestedAction {
  /// Print a practice sheet for the concepts that were shaky.
  worksheet(label: 'Create a worksheet'),

  /// Go back over the words and pictures for those concepts.
  flashcards(label: 'Open flashcards'),

  /// Teach the lesson again before moving on.
  repeatLesson(label: 'Open the lesson again'),

  /// Nothing to fix. Carry on.
  moveOn(label: 'Back to the lesson');

  const SuggestedAction({required this.label});

  final String label;
}

/// What to do after an assessment.
class PracticeSuggestion {
  const PracticeSuggestion({
    required this.headline,
    required this.body,
    required this.action,
    this.concepts = const <QuizConceptLabel>[],
  });

  final String headline;
  final String body;
  final SuggestedAction action;

  /// The concepts the suggestion is about, so the screen can name them without
  /// re-deriving them from the result.
  final List<QuizConceptLabel> concepts;

  /// How this suggestion was arrived at.
  ///
  /// Fixed, and shown to the teacher. This is a rule that compares counts on
  /// this phone — it is not a model, it did not read the child's work, and the
  /// screen must never present it as one. If a language model ever writes these
  /// instead, this becomes a field and the label changes with it.
  String get sourceNote =>
      'Chosen by a rule on this phone from the answers above. Not written by '
      'a model.';
}

/// A concept name paired with how it was answered, for the suggestion text.
typedef QuizConceptLabel = ({String label, int correct, int total});

/// Decides what to practise next.
///
/// An interface, because this is exactly the kind of thing a model could do
/// better later. Everything shipping today is behind
/// [LocalAssessmentRecommendationService], which is arithmetic.
abstract interface class AssessmentRecommendationService {
  PracticeSuggestion suggest(QuizResult result);
}

/// Deterministic rules over the concept counts.
///
/// Given the same result this returns the same suggestion, every time, on every
/// device, with no connection. That is the whole implementation: there is no
/// inference here and nothing in the UI may call it AI.
class LocalAssessmentRecommendationService
    implements AssessmentRecommendationService {
  const LocalAssessmentRecommendationService();

  @override
  PracticeSuggestion suggest(QuizResult result) {
    final List<ConceptPerformance> weak = result.needsReinforcement;

    if (result.total == 0) {
      return const PracticeSuggestion(
        headline: 'Nothing to suggest yet',
        body: 'No questions were answered, so there is nothing to go on.',
        action: SuggestedAction.moveOn,
      );
    }

    final List<QuizConceptLabel> labels = <QuizConceptLabel>[
      for (final ConceptPerformance c in weak)
        (label: c.concept.label, correct: c.correct, total: c.total),
    ];

    if (weak.isEmpty) {
      return const PracticeSuggestion(
        headline: 'Ready for the next lesson',
        body: 'Every concept in this assessment was answered correctly. '
            'Moving on is reasonable; a short revision at the start of the '
            'next class still helps it stick.',
        action: SuggestedAction.moveOn,
      );
    }

    final String named = _list(
      <String>[for (final ConceptPerformance c in weak) c.concept.label],
    );

    // Most of it landed: a printed sheet on the one or two shaky concepts is
    // the smallest useful next step.
    if (result.percentage >= 70) {
      return PracticeSuggestion(
        headline: 'Practise $named',
        body: 'Most of this assessment was answered correctly. A worksheet on '
            '$named would cover what is left without repeating the whole '
            'lesson.',
        action: SuggestedAction.worksheet,
        concepts: labels,
      );
    }

    // Half of it landed: go back to pictures and words before more written
    // practice, which is what a child who is still counting on their fingers
    // needs.
    if (result.percentage >= 40) {
      return PracticeSuggestion(
        headline: 'Go over $named again',
        body: 'About half the questions were answered correctly. Flashcards '
            'for $named, counted aloud together, are usually a better next '
            'step than another written sheet.',
        action: SuggestedAction.flashcards,
        concepts: labels,
      );
    }

    return PracticeSuggestion(
      headline: 'Teach this lesson again',
      body: 'Most of the questions were not answered correctly, across '
          '$named. Repeating the lesson with objects from the classroom is '
          'likely to help more than any practice sheet.',
      action: SuggestedAction.repeatLesson,
      concepts: labels,
    );
  }

  /// "A", "A and B", "A, B and C".
  static String _list(List<String> items) => switch (items.length) {
        0 => '',
        1 => items.first,
        2 => '${items[0]} and ${items[1]}',
        _ => '${items.sublist(0, items.length - 1).join(', ')} and ${items.last}',
      };
}
