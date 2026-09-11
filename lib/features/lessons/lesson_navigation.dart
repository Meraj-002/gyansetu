import '../../models/lesson_plan.dart';
import '../setup/models/classroom_setup.dart';

/// What lesson detail is opened with.
///
/// A typed argument rather than a loose map, so a caller that forgets the
/// lesson id fails to compile. A bare `String` id is still accepted by the
/// screen for callers written before this existed.
class LessonDetailArgs {
  const LessonDetailArgs(this.lessonId);

  final String lessonId;

  /// Reads either form out of a route's arguments.
  static String? lessonIdFrom(Object? arguments) => switch (arguments) {
        LessonDetailArgs(:final String lessonId) => lessonId,
        final String id when id.isNotEmpty => id,
        _ => null,
      };
}

/// What the classroom activity screen is opened with.
class LessonActivityArgs {
  const LessonActivityArgs({
    required this.lessonId,
    required this.lessonTitle,
    required this.activity,
  });

  final String lessonId;
  final String lessonTitle;
  final ClassroomActivity activity;
}

/// What the quick assessment screen is opened with.
class LessonAssessmentArgs {
  const LessonAssessmentArgs({
    required this.lessonId,
    required this.lessonTitle,
    required this.assessment,
    this.previous,
  });

  final String lessonId;
  final String lessonTitle;
  final QuickAssessment assessment;

  /// The last recorded result, so reopening shows what was marked before
  /// rather than a blank sheet.
  final AssessmentResult? previous;
}

/// Everything the live classroom needs in order to start.
///
/// The whole point of this class is that the live classroom is handed real
/// context — this lesson, this class, these two languages — instead of
/// discovering them for itself or being given defaults.
class LiveClassroomArgs {
  const LiveClassroomArgs({
    required this.lessonId,
    required this.lessonTitle,
    required this.learningOutcome,
    required this.classLevel,
    required this.subject,
    required this.teachingMedium,
    required this.targetLanguage,
    this.teacherScript,
    this.translatedScript,
  });

  final String lessonId;
  final String lessonTitle;
  final String learningOutcome;
  final int classLevel;

  /// Part of the classroom context a translation provider is given, so a
  /// numeracy sentence is not translated as if it were a story.
  final ClassroomSubject subject;

  /// What the teacher speaks. The speech recogniser is configured from this.
  final TeachingMedium teachingMedium;

  /// What the children hear. The translation and the voice are configured from
  /// this.
  final TargetLanguage targetLanguage;

  final String? teacherScript;

  /// Passed through when it is already on the device, so the live session does
  /// not have to translate the opening line again.
  final String? translatedScript;
}
