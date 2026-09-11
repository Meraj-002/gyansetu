import 'package:gyan_setu_ai/features/setup/models/classroom_setup.dart';
import 'package:gyan_setu_ai/features/worksheet/services/worksheet_generation_service.dart';
import 'package:gyan_setu_ai/models/question.dart';
import 'package:gyan_setu_ai/models/worksheet.dart';
import 'package:gyan_setu_ai/services/translation/text_translation_service.dart';

const List<String> kCountingConcepts = <String>[
  'Counting 1–10',
  'Number Sequence',
  'After, Before, Between',
];

/// The same request with a different regeneration variant.
extension WorksheetRequestVariant on WorksheetGenerationRequest {
  WorksheetGenerationRequest copyWithVariant(int value) =>
      WorksheetGenerationRequest(
        lessonId: lessonId,
        lessonTitle: lessonTitle,
        learningOutcome: learningOutcome,
        classNumber: classNumber,
        subject: subject,
        teachingLanguage: teachingLanguage,
        targetLanguage: targetLanguage,
        difficulty: difficulty,
        questionTypes: questionTypes,
        numberOfQuestions: numberOfQuestions,
        concepts: concepts,
        visualExamples: visualExamples,
        culturallyFamiliarExamples: culturallyFamiliarExamples,
        variant: value,
      );
}

WorksheetGenerationRequest testRequest({
  String lessonId = 'c1-num-counting-1-10',
  String lessonTitle = 'Counting 1–10',
  String learningOutcome = 'Count and identify numbers 1–10',
  int classNumber = 1,
  WorksheetDifficulty difficulty = WorksheetDifficulty.easy,
  Set<QuestionType>? questionTypes,
  int numberOfQuestions = 10,
  List<VisualExample>? visualExamples,
  bool culturallyFamiliar = true,
  TargetLanguage target = TargetLanguage.santali,
}) =>
    WorksheetGenerationRequest(
      lessonId: lessonId,
      lessonTitle: lessonTitle,
      learningOutcome: learningOutcome,
      classNumber: classNumber,
      subject: ClassroomSubject.numeracy,
      teachingLanguage: TeachingMedium.hindi,
      targetLanguage: target,
      difficulty: difficulty,
      questionTypes: questionTypes ??
          <QuestionType>{
            QuestionType.countingObjects,
            QuestionType.visualIdentification,
          },
      numberOfQuestions: numberOfQuestions,
      concepts: kCountingConcepts,
      visualExamples: visualExamples ?? <VisualExample>[VisualExample.apples],
      culturallyFamiliarExamples: culturallyFamiliar,
    );

/// A copy of [worksheet] with one or two things changed, for testing the
/// validator against output a generator might really produce.
Worksheet worksheetWith(
  Worksheet worksheet, {
  List<WorksheetQuestion>? questions,
  String? lessonId,
  String? learningOutcome,
  GenerationSource? source,
}) =>
    Worksheet(
      id: worksheet.id,
      lessonId: lessonId ?? worksheet.lessonId,
      title: worksheet.title,
      learningOutcome: learningOutcome ?? worksheet.learningOutcome,
      classNumber: worksheet.classNumber,
      subject: worksheet.subject,
      teachingLanguage: worksheet.teachingLanguage,
      targetLanguage: worksheet.targetLanguage,
      difficulty: worksheet.difficulty,
      questions: questions ?? worksheet.questions,
      generatedAt: worksheet.generatedAt,
      generationSource: source ?? worksheet.generationSource,
      visualExamples: worksheet.visualExamples,
      culturallyFamiliarExamples: worksheet.culturallyFamiliarExamples,
      teacherNotes: worksheet.teacherNotes,
      variant: worksheet.variant,
      // Deliberately kept: truncating the questions must not also rewrite what
      // was asked for, or the validator would have nothing to compare against.
      requestedQuestionCount: worksheet.requestedQuestionCount,
    );

/// A translator the test dictates.
class FakeWorksheetTranslator implements TextTranslationService {
  FakeWorksheetTranslator({this.translated = 'translated', this.fails = false});

  String translated;
  bool fails;
  int calls = 0;

  @override
  String get modelVersion => 'fake-worksheet-1';

  @override
  bool get isRealModel => false;

  @override
  bool get requiresNetwork => false;

  @override
  Future<bool> supportsPair(String source, String target) async => !fails;

  @override
  Future<TranslationResult> translate(TranslationRequest request) async {
    calls++;
    if (fails) {
      throw const TextTranslationFailure(
        TranslationFailureReason.notConfigured,
        'not in the phrasebook',
      );
    }
    return TranslationResult(
      translatedText: translated,
      sourceLanguage: request.sourceLanguage,
      targetLanguage: request.targetLanguage,
      modelVersion: modelVersion,
    );
  }
}

/// A generator whose outcome the test chooses.
class FakeWorksheetGenerationService implements WorksheetGenerationService {
  FakeWorksheetGenerationService({
    this.available = true,
    this.failure,
    this.worksheet,
    this.latency = Duration.zero,
    this.sourceOverride,
  });

  bool available;
  WorksheetGenerationFailure? failure;

  /// Returned instead of a generated worksheet, for the invalid-output case.
  Worksheet? worksheet;

  Duration latency;
  GenerationSource? sourceOverride;

  int calls = 0;
  WorksheetGenerationRequest? lastRequest;

  @override
  GenerationSource get source => sourceOverride ?? GenerationSource.localOffline;

  @override
  Future<bool> get isAvailable async => available;

  @override
  Future<Worksheet> generate(WorksheetGenerationRequest request) async {
    calls++;
    lastRequest = request;
    if (latency > Duration.zero) await Future<void>.delayed(latency);

    final WorksheetGenerationFailure? thrown = failure;
    if (thrown != null) throw thrown;

    final Worksheet? fixed = worksheet;
    if (fixed != null) return fixed;

    return Worksheet(
      id: 'ws-${request.lessonId}',
      lessonId: request.lessonId,
      title: '${request.lessonTitle} — Worksheet',
      learningOutcome: request.learningOutcome,
      classNumber: request.classNumber,
      subject: request.subject,
      teachingLanguage: request.teachingLanguage,
      targetLanguage: request.targetLanguage,
      difficulty: request.difficulty,
      generatedAt: DateTime(2026, 8, 29),
      generationSource: source,
      visualExamples: request.visualExamples,
      culturallyFamiliarExamples: request.culturallyFamiliarExamples,
      requestedQuestionCount: request.numberOfQuestions,
      questions: <WorksheetQuestion>[
        for (int i = 0; i < request.numberOfQuestions; i++)
          WorksheetQuestion(
            id: 'q${i + 1}',
            type: request.questionTypes.first,
            questionText: 'कितने सेब हैं?',
            correctAnswer: '${i + 1}',
            order: i + 1,
          ),
      ],
    );
  }
}
