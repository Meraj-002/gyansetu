import '../../../models/question.dart';
import '../../../models/worksheet.dart';
import '../../setup/models/classroom_setup.dart';

/// Everything a generator needs in order to write a worksheet for one class.
///
/// Assembled from the lesson and the saved classroom, never from the strings
/// the screen happens to be showing.
class WorksheetGenerationRequest {
  const WorksheetGenerationRequest({
    required this.lessonId,
    required this.lessonTitle,
    required this.learningOutcome,
    required this.classNumber,
    required this.subject,
    required this.teachingLanguage,
    required this.targetLanguage,
    required this.difficulty,
    required this.questionTypes,
    required this.numberOfQuestions,
    this.concepts = const <String>[],
    this.visualExamples = const <VisualExample>[],
    this.culturallyFamiliarExamples = true,
    this.variant = 0,
  });

  final String lessonId;
  final String lessonTitle;

  /// What the worksheet must practise. The generator is not free to wander off
  /// it: a counting lesson does not get a grammar question.
  final String learningOutcome;

  final int classNumber;
  final ClassroomSubject subject;
  final TeachingMedium teachingLanguage;
  final TargetLanguage targetLanguage;
  final WorksheetDifficulty difficulty;

  /// At least one. Enforced before a request is ever built.
  final Set<QuestionType> questionTypes;

  final int numberOfQuestions;

  /// The lesson's own concepts, so each question can name the one it drills.
  final List<String> concepts;

  final List<VisualExample> visualExamples;

  /// Prefer everyday objects a village classroom already has.
  final bool culturallyFamiliarExamples;

  /// Which pass over the same choices this is.
  ///
  /// Regenerating advances it, so the teacher gets a different sheet rather
  /// than the same one again — while a given variant stays reproducible, which
  /// is what lets a worksheet be reprinted exactly.
  final int variant;

  /// What a backend would be sent. Structured fields rather than a prose
  /// prompt, so a model can use them without the request becoming untestable.
  Map<String, dynamic> toJson() => <String, dynamic>{
        'lesson_id': lessonId,
        'lesson_title': lessonTitle,
        'learning_outcome': learningOutcome,
        'class_number': classNumber,
        'subject': subject.name,
        'teaching_language': teachingLanguage.localeId,
        'target_language': targetLanguage.localeId,
        'difficulty': difficulty.name,
        'question_types': <String>[
          for (final QuestionType t in questionTypes) t.name,
        ],
        'number_of_questions': numberOfQuestions,
        'concepts': concepts,
        'visual_examples': <String>[
          for (final VisualExample v in visualExamples) v.name,
        ],
        'culturally_familiar_examples': culturallyFamiliarExamples,
        'variant': variant,
      };
}

/// Why a worksheet could not be produced.
enum WorksheetFailureReason {
  /// The request itself is not usable.
  invalidRequest,

  /// A remote generator was asked and there is no connection.
  needsConnection,

  /// The generator answered with something that failed validation.
  invalidOutput,

  /// The attempt failed.
  failed,
}

class WorksheetGenerationFailure implements Exception {
  const WorksheetGenerationFailure(this.reason, this.message);

  final WorksheetFailureReason reason;

  /// Plain language for the teacher. Never an exception string.
  final String message;

  @override
  String toString() => 'WorksheetGenerationFailure($reason)';
}

/// Writes a worksheet from a request.
///
/// An interface because the useful version of this is a model. The screen holds
/// one of these and knows nothing about where the questions come from, so the
/// local generator can be replaced by a FastAPI-backed one without the UI
/// changing:
///
///   Screen -> WorksheetGenerationService -> FastAPI -> model -> Worksheet
///   Screen -> WorksheetGenerationService -> on-device generator -> Worksheet
abstract interface class WorksheetGenerationService {
  /// Where the questions come from. Read by every "AI-generated" label, so a
  /// deterministic generator can never be presented as a model.
  GenerationSource get source;

  /// Whether this generator can run right now.
  Future<bool> get isAvailable;

  /// Throws [WorksheetGenerationFailure]; the controller turns that into a
  /// message the teacher can retry.
  Future<Worksheet> generate(WorksheetGenerationRequest request);
}
