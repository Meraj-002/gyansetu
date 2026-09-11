import '../../../models/lesson.dart';
import '../../setup/models/classroom_setup.dart';

/// Chooses which lessons to surface as today's recommendations.
///
/// Behind an interface so a personalised or model-driven ranker can replace the
/// rules below without the library changing.
abstract interface class RecommendationRepository {
  /// Ranked recommendations for [classroom], best first.
  Future<List<LessonCard>> recommend({
    required List<LessonCard> catalogue,
    required ClassroomSetup? classroom,
    int limit = 3,
  });
}

/// Rule-based ranking.
///
/// PROTOTYPE LOGIC, not a model. It scores what the app actually knows today:
/// the teacher's class and subjects, whether a lesson is already on the device,
/// and how far through it they are. Half-finished lessons rank highest —
/// finishing something beats starting something.
///
/// REPLACE WITH: a personalised ranker once there is real progress and
/// assessment history to learn from.
class RuleBasedRecommendationRepository implements RecommendationRepository {
  const RuleBasedRecommendationRepository();

  @override
  Future<List<LessonCard>> recommend({
    required List<LessonCard> catalogue,
    required ClassroomSetup? classroom,
    int limit = 3,
  }) async {
    final List<LessonCard> pool = catalogue
        .where((LessonCard c) => !c.completed)
        .toList();

    pool.sort((LessonCard a, LessonCard b) {
      final int byScore = _score(b, classroom).compareTo(_score(a, classroom));
      if (byScore != 0) return byScore;
      // Stable tie-break so the carousel does not reshuffle between reads.
      return a.lesson.lessonOrder.compareTo(b.lesson.lessonOrder);
    });

    return pool
        .take(limit)
        .map((LessonCard c) => LessonCard(
              lesson: c.lesson,
              completionPercentage: c.completionPercentage,
              download: c.download,
              recommended: true,
            ))
        .toList();
  }

  static int _score(LessonCard card, ClassroomSetup? classroom) {
    int score = 0;

    if (classroom != null) {
      // The teacher's own class matters most: a Class 4 lesson is no use to a
      // Class 1 teacher however good it is.
      if (card.lesson.classNumber == classroom.classLevel) score += 100;
      if (classroom.subjects.contains(card.lesson.subject)) score += 30;
    }

    // Something already started, and close to done, comes first.
    if (card.inProgress) score += 40 + (card.completionPercentage ~/ 5);

    // Usable right now without a connection.
    if (card.downloaded) score += 20;

    // Shorter lessons are easier to fit into a school day.
    score += (30 - card.lesson.durationMinutes).clamp(0, 20);

    return score;
  }
}
