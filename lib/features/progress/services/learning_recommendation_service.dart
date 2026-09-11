import '../../../models/flashcard.dart';
import '../../../models/lesson.dart';
import '../models/learning_insights.dart';

/// What the teacher is being pointed at.
enum LearningActionKind {
  /// Reteach a lesson that covers the weak concept.
  reinforcementLesson,

  /// Go over the words and pictures for it first.
  flashcards,

  /// Nothing is weak. Carry on with the next lesson.
  carryOn,

  /// Nothing has been recorded yet, so there is nothing to suggest.
  needsData,
}

/// One thing to do next, and the screen that does it.
class LearningAction {
  const LearningAction({
    required this.kind,
    required this.headline,
    required this.body,
    this.lessonId,
    this.flashcardCategory,
    this.concept,
  });

  final LearningActionKind kind;
  final String headline;
  final String body;

  /// The lesson to open. Null when none of the class's lessons covers this
  /// concept, in which case the caller opens the lesson library instead of
  /// pretending a lesson exists.
  final String? lessonId;

  /// The deck to practise with, when one fits the concept.
  final FlashcardCategory? flashcardCategory;

  final String? concept;

  /// How this was arrived at. Fixed text, shown to the teacher.
  ///
  /// It is a rule over counts on this phone. It is not a model, it has not read
  /// any child's work, and no screen may present it as AI.
  String get sourceNote =>
      'Worked out on this phone from the records above, by a rule rather than '
      'a model.';
}

/// Decides what a teacher should do about a weak concept.
///
/// An interface because a model could do this better later — reading the
/// lesson plan, the child's answers and the teacher's own notes. Everything
/// that ships today is behind [LocalLearningRecommendationService].
abstract interface class LearningRecommendationService {
  LearningAction recommend({
    required LearningInsights insights,
    required List<Lesson> lessons,
  });
}

/// Rules over the weakest concept and the lesson catalogue.
///
/// Deterministic: the same insights and the same catalogue always give the same
/// action, on any device, with no connection.
class LocalLearningRecommendationService
    implements LearningRecommendationService {
  const LocalLearningRecommendationService();

  @override
  LearningAction recommend({
    required LearningInsights insights,
    required List<Lesson> lessons,
  }) {
    final AttentionGroup? weakest = insights.weakest;

    if (weakest == null) {
      if (!insights.hasAnyHistory) {
        return const LearningAction(
          kind: LearningActionKind.needsData,
          headline: 'Teach a lesson to see suggestions here',
          body: 'Once a lesson has been taught or an assessment recorded, '
              'this will name the concept that needs the most work.',
        );
      }
      return const LearningAction(
        kind: LearningActionKind.carryOn,
        headline: 'Nothing is falling behind',
        body: 'No concept in the recorded work is marked as needing more '
            'practice. Carrying on with the next lesson is reasonable.',
      );
    }

    final Lesson? lesson = _lessonFor(weakest, lessons);
    final FlashcardCategory? deck = _deckFor(weakest.concept);

    // Below half the class, a reteach of the whole lesson costs more than it
    // returns; the few children affected are better served by the pictures.
    final int? roll = insights.studentCount;
    final bool wholeClass =
        roll == null || weakest.count == 0 || weakest.count * 2 >= roll;

    if (!wholeClass && deck != null) {
      return LearningAction(
        kind: LearningActionKind.flashcards,
        headline: 'Practise ${weakest.concept} with flashcards',
        body: 'Only ${weakest.count} of $roll children are behind on this. '
            'Going through the ${deck.label.toLowerCase()} cards with them, '
            'counted aloud, is a smaller step than reteaching the lesson.',
        lessonId: lesson?.id,
        flashcardCategory: deck,
        concept: weakest.concept,
      );
    }

    return LearningAction(
      kind: LearningActionKind.reinforcementLesson,
      headline: lesson == null
          ? 'Reteach ${weakest.concept}'
          : 'Repeat ${lesson.title} using objects and pictures',
      body: lesson == null
          ? 'No lesson in this class covers ${weakest.concept} yet. The lesson '
              'library is the place to find one.'
          : 'Teach ${lesson.title} again with objects from the classroom — '
              'stones, leaves, bottle caps — so ${weakest.concept.toLowerCase()} '
              'is something the children handle rather than only hear.',
      lessonId: lesson?.id,
      flashcardCategory: deck,
      concept: weakest.concept,
    );
  }

  /// The lesson that teaches this concept.
  ///
  /// Prefers the lesson the assessment itself belonged to, then any lesson
  /// naming the concept, and finally gives up rather than guessing.
  static Lesson? _lessonFor(AttentionGroup group, List<Lesson> lessons) {
    final String? id = group.lessonId;
    if (id != null) {
      for (final Lesson l in lessons) {
        if (l.id == id) return l;
      }
    }

    final String needle = group.concept.toLowerCase();
    for (final Lesson l in lessons) {
      for (final String c in l.concepts) {
        if (c.toLowerCase() == needle) return l;
      }
    }
    for (final Lesson l in lessons) {
      for (final String c in l.concepts) {
        if (c.toLowerCase().contains(needle) ||
            needle.contains(c.toLowerCase())) {
          return l;
        }
      }
    }
    return null;
  }

  /// The flashcard deck that matches a concept, or null when none does.
  static FlashcardCategory? _deckFor(String concept) {
    final String lower = concept.toLowerCase();
    if (lower.contains('number') ||
        lower.contains('counting') ||
        lower.contains('one-to-one')) {
      return FlashcardCategory.numbers;
    }
    if (lower.contains('letter') ||
        lower.contains('word') ||
        lower.contains('vowel') ||
        lower.contains('sound')) {
      return FlashcardCategory.objects;
    }
    return null;
  }
}
