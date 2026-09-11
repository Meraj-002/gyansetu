import '../../../models/flashcard.dart';
import '../../../models/lesson.dart';
import '../../setup/models/classroom_setup.dart';

/// Decides which category a teacher should land on, and in what order the
/// cards should appear.
///
/// An interface because the useful version of this reasons about the lesson,
/// the class and what the children have already met. What ships today is a set
/// of local rules, and it says so — nothing here is called AI.
abstract interface class FlashcardRecommendationService {
  /// The category to open on, given where the teacher came from.
  FlashcardCategory openingCategory({
    Lesson? lesson,
    ClassroomSetup? classroom,
    required List<Flashcard> available,
  });

  /// The cards for a category, in the order this teacher should see them.
  List<Flashcard> order(
    List<Flashcard> cards, {
    Lesson? lesson,
    ClassroomSetup? classroom,
  });
}

/// Local rules over the lesson and the classroom.
///
/// NOT AI, and not random either. A counting lesson opens on Numbers because
/// its own subject and concepts say so, and the cards that name that lesson
/// come first.
class LocalFlashcardRecommendationService
    implements FlashcardRecommendationService {
  const LocalFlashcardRecommendationService();

  @override
  FlashcardCategory openingCategory({
    Lesson? lesson,
    ClassroomSetup? classroom,
    required List<Flashcard> available,
  }) {
    final Set<FlashcardCategory> withCards = <FlashcardCategory>{
      for (final Flashcard c in available) c.category,
    };
    if (withCards.isEmpty) return FlashcardCategory.numbers;

    // A card that names this lesson is the strongest signal there is.
    if (lesson != null) {
      for (final Flashcard card in available) {
        if (card.lessonIds.contains(lesson.id)) return card.category;
      }
      // Otherwise the lesson's own subject decides.
      if (lesson.subject == ClassroomSubject.numeracy &&
          withCards.contains(FlashcardCategory.numbers)) {
        return FlashcardCategory.numbers;
      }
      if (lesson.subject == ClassroomSubject.foundationalLiteracy &&
          withCards.contains(FlashcardCategory.objects)) {
        return FlashcardCategory.objects;
      }
    }

    // Never open on a category with nothing in it.
    for (final FlashcardCategory category in FlashcardCategory.values) {
      if (withCards.contains(category)) return category;
    }
    return FlashcardCategory.numbers;
  }

  @override
  List<Flashcard> order(
    List<Flashcard> cards, {
    Lesson? lesson,
    ClassroomSetup? classroom,
  }) {
    final List<Flashcard> ordered = cards.toList()
      ..sort((Flashcard a, Flashcard b) {
        // Cards belonging to the lesson the teacher came from go first.
        final int aLesson = _lessonRank(a, lesson);
        final int bLesson = _lessonRank(b, lesson);
        if (aLesson != bLesson) return aLesson.compareTo(bLesson);

        // Then the class being taught.
        final int aClass = _classRank(a, classroom);
        final int bClass = _classRank(b, classroom);
        if (aClass != bClass) return aClass.compareTo(bClass);

        return a.order.compareTo(b.order);
      });
    return List<Flashcard>.unmodifiable(ordered);
  }

  static int _lessonRank(Flashcard card, Lesson? lesson) =>
      lesson != null && card.lessonIds.contains(lesson.id) ? 0 : 1;

  static int _classRank(Flashcard card, ClassroomSetup? classroom) {
    if (classroom == null || card.classNumber == null) return 1;
    return card.classNumber == classroom.classLevel ? 0 : 1;
  }
}
