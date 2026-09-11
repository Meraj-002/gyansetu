import '../../../data/lesson_plans.dart';
import '../../../models/lesson.dart';
import '../../../models/lesson_plan.dart';
import '../../../models/lesson_translation.dart';
import '../../setup/models/classroom_setup.dart';

/// What came back from asking the AI layer for content.
///
/// A sealed result rather than an exception: every caller has to decide what to
/// show when the answer is "not for this lesson, not in this language, not on
/// this device", and a `switch` makes forgetting one impossible.
sealed class AiContentResult<T> {
  const AiContentResult();
}

final class AiContent<T> extends AiContentResult<T> {
  const AiContent(this.value);

  final T value;
}

/// The request is understood but cannot be served right now.
final class AiContentUnavailable<T> extends AiContentResult<T> {
  const AiContentUnavailable(this.reason, this.message);

  final AiUnavailableReason reason;

  /// Plain language for the teacher. Never an exception string.
  final String message;
}

enum AiUnavailableReason {
  /// No provider is configured for this operation in this build.
  notConfigured,

  /// A provider exists but the device has no connection and nothing is cached.
  needsConnection,

  /// The provider was asked and refused or failed.
  failed,

  /// Nothing exists for this lesson or this language yet.
  noContent,
}

/// The single door between this app and any language model.
///
/// Every generation and translation the product needs is declared here, so the
/// screens can be written against operations that do not exist yet. Lesson
/// detail uses three of them; the rest are the contract the worksheet,
/// flashcard and live-classroom features will call.
///
/// IMPORTANT: no widget may call an implementation of this directly. Screens
/// go through a repository or a controller, so swapping a local adapter for
/// FastAPI never touches the UI.
abstract interface class AiContentService {
  /// Whether a real provider is wired up. False in this build.
  bool get hasProvider;

  /// Builds a whole plan from a learning outcome and classroom context.
  Future<AiContentResult<LessonPlan>> generateLesson({
    required Lesson lesson,
    required ClassroomSetup classroom,
  });

  /// Reworks an existing plan for a different class, medium or context, while
  /// keeping the approved learning outcome fixed.
  Future<AiContentResult<LessonPlan>> adaptLesson({
    required LessonPlan plan,
    required ClassroomSetup classroom,
  });

  /// Translates a teacher script into the classroom's mother tongue.
  Future<AiContentResult<LessonTranslation>> translateLesson({
    required Lesson lesson,
    required LessonPlan plan,
    required TargetLanguage target,
  });

  Future<AiContentResult<ClassroomActivity>> generateActivity({
    required Lesson lesson,
    required ClassroomSetup classroom,
  });

  Future<AiContentResult<QuickAssessment>> generateAssessment({
    required Lesson lesson,
    required ClassroomSetup classroom,
  });

  Future<AiContentResult<TeachingTip>> generateTeachingTip({
    required Lesson lesson,
    required ClassroomSetup classroom,
  });

  /// Returns a worksheet resource id once the worksheet feature exists.
  Future<AiContentResult<String>> generateWorksheet({
    required Lesson lesson,
    required ClassroomSetup classroom,
  });

  /// Returns a flashcard resource id once the flashcard feature exists.
  Future<AiContentResult<String>> generateFlashcards({
    required Lesson lesson,
    required ClassroomSetup classroom,
  });
}

/// Serves the curated prototype content, and refuses everything else.
///
/// DEVELOPMENT ADAPTER. There is no model behind this class and it does not
/// pretend there is: [hasProvider] is false, generation returns
/// [AiUnavailableReason.notConfigured], and the content it does return is
/// hand-written and reports itself as [ContentProvenance.authored]. That is why
/// lesson detail can show an "AI-generated" badge at all — the badge reads
/// provenance, and this adapter never claims a provenance it did not earn.
///
/// REPLACE WITH: `FastApiAiContentService` posting to the FastAPI content
/// endpoints, or `OnDeviceAiContentService` once a small local model ships.
class DevelopmentAiContentService implements AiContentService {
  DevelopmentAiContentService({
    Map<String, LessonPlan>? plans,
    Map<String, LessonTranslation>? translations,
  })  : _plans = plans ?? CuratedLessonContent.plans(),
        _translations = translations ?? CuratedLessonContent.translations();

  final Map<String, LessonPlan> _plans;
  final Map<String, LessonTranslation> _translations;

  static const String _notConfigured =
      'AI lesson generation is not switched on in this build.';

  @override
  bool get hasProvider => false;

  /// The curated plan for a lesson, or null when none was written.
  LessonPlan? curatedPlan(String lessonId) => _plans[lessonId];

  @override
  Future<AiContentResult<LessonPlan>> generateLesson({
    required Lesson lesson,
    required ClassroomSetup classroom,
  }) async {
    final LessonPlan? existing = _plans[lesson.id];
    if (existing != null) return AiContent<LessonPlan>(existing);
    return const AiContentUnavailable<LessonPlan>(
      AiUnavailableReason.notConfigured,
      _notConfigured,
    );
  }

  @override
  Future<AiContentResult<LessonPlan>> adaptLesson({
    required LessonPlan plan,
    required ClassroomSetup classroom,
  }) async =>
      const AiContentUnavailable<LessonPlan>(
        AiUnavailableReason.notConfigured,
        _notConfigured,
      );

  @override
  Future<AiContentResult<LessonTranslation>> translateLesson({
    required Lesson lesson,
    required LessonPlan plan,
    required TargetLanguage target,
  }) async {
    final LessonTranslation? curated =
        _translations[LessonTranslation.cacheKeyFor(lesson.id, target)];
    if (curated != null) return AiContent<LessonTranslation>(curated);

    return AiContentUnavailable<LessonTranslation>(
      AiUnavailableReason.noContent,
      'This lesson has not been translated into ${target.label} yet.',
    );
  }

  @override
  Future<AiContentResult<ClassroomActivity>> generateActivity({
    required Lesson lesson,
    required ClassroomSetup classroom,
  }) async =>
      const AiContentUnavailable<ClassroomActivity>(
        AiUnavailableReason.notConfigured,
        _notConfigured,
      );

  @override
  Future<AiContentResult<QuickAssessment>> generateAssessment({
    required Lesson lesson,
    required ClassroomSetup classroom,
  }) async =>
      const AiContentUnavailable<QuickAssessment>(
        AiUnavailableReason.notConfigured,
        _notConfigured,
      );

  @override
  Future<AiContentResult<TeachingTip>> generateTeachingTip({
    required Lesson lesson,
    required ClassroomSetup classroom,
  }) async =>
      const AiContentUnavailable<TeachingTip>(
        AiUnavailableReason.notConfigured,
        _notConfigured,
      );

  @override
  Future<AiContentResult<String>> generateWorksheet({
    required Lesson lesson,
    required ClassroomSetup classroom,
  }) async =>
      const AiContentUnavailable<String>(
        AiUnavailableReason.notConfigured,
        _notConfigured,
      );

  @override
  Future<AiContentResult<String>> generateFlashcards({
    required Lesson lesson,
    required ClassroomSetup classroom,
  }) async =>
      const AiContentUnavailable<String>(
        AiUnavailableReason.notConfigured,
        _notConfigured,
      );
}
