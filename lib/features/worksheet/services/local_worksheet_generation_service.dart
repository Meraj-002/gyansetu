// ignore_for_file: prefer_initializing_formals
// Private fields cannot be initialising formals: a named parameter may not
// start with an underscore.
import '../../../core/utils/app_logger.dart';
import '../../../models/question.dart';
import '../../../models/worksheet.dart';
import '../../../services/translation/text_translation_service.dart';
import 'worksheet_generation_service.dart';

/// DEVELOPMENT OFFLINE FALLBACK.
/// Replace with `FastApiWorksheetGenerationService` posting the same
/// [WorksheetGenerationRequest] to the backend's generation endpoint. Nothing
/// above [WorksheetGenerationService] changes when it is.
///
/// This is a deterministic generator, NOT a model. It builds questions from
/// templates around the lesson's own number range and concepts, so the output
/// is curriculum-aligned and repeatable — the same request always produces the
/// same worksheet. It reports [GenerationSource.localOffline], and every label
/// in the app reads that, so nothing it writes is ever presented as AI.
///
/// It needs no connection, which is the point: a teacher in a village school
/// can make a worksheet on the walk to class.
class LocalWorksheetGenerationService implements WorksheetGenerationService {
  LocalWorksheetGenerationService({TextTranslationService? translator})
      : _translator = translator;

  /// Used to put the mother tongue beside each question where a translation
  /// genuinely exists. Where it does not, the question stays in one language
  /// and the worksheet says so — an invented second line would be printed and
  /// sent home with a child.
  final TextTranslationService? _translator;

  @override
  GenerationSource get source => GenerationSource.localOffline;

  @override
  Future<bool> get isAvailable async => true;

  @override
  Future<Worksheet> generate(WorksheetGenerationRequest request) async {
    if (request.questionTypes.isEmpty) {
      throw const WorksheetGenerationFailure(
        WorksheetFailureReason.invalidRequest,
        'Choose at least one question type.',
      );
    }
    if (request.numberOfQuestions <= 0) {
      throw const WorksheetGenerationFailure(
        WorksheetFailureReason.invalidRequest,
        'Choose how many questions the worksheet should have.',
      );
    }

    final int ceiling = numberCeilingFor(request);
    final List<VisualExample> objects = _objectsFor(request);
    final List<QuestionType> types = request.questionTypes.toList()
      ..sort((QuestionType a, QuestionType b) => a.index.compareTo(b.index));

    final List<WorksheetQuestion> questions = <WorksheetQuestion>[];
    for (int i = 0; i < request.numberOfQuestions; i++) {
      // Types are cycled rather than drawn at random, so a teacher who asks
      // for two kinds gets both in equal measure instead of by luck.
      final QuestionType type = types[i % types.length];
      final VisualExample object = objects[i % objects.length];
      questions.add(
        _build(
          request: request,
          type: type,
          object: object,
          ceiling: ceiling,
          index: i,
        ),
      );
    }

    final List<WorksheetQuestion> translated =
        await _translateAll(questions, request);

    return Worksheet(
      id: 'ws-${request.lessonId}-${DateTime.now().millisecondsSinceEpoch}',
      lessonId: request.lessonId,
      title: '${request.lessonTitle} — Worksheet',
      learningOutcome: request.learningOutcome,
      classNumber: request.classNumber,
      subject: request.subject,
      teachingLanguage: request.teachingLanguage,
      targetLanguage: request.targetLanguage,
      difficulty: request.difficulty,
      questions: translated,
      generatedAt: DateTime.now(),
      generationSource: source,
      visualExamples: objects,
      culturallyFamiliarExamples: request.culturallyFamiliarExamples,
      teacherNotes: _teacherNotes(request, ceiling),
      variant: request.variant,
      requestedQuestionCount: request.numberOfQuestions,
    );
  }

  // --- Curriculum alignment ------------------------------------------------

  /// The largest number this worksheet may use.
  ///
  /// Read out of the lesson's own outcome and title first — "Count objects
  /// from 1 to 10" means ten, and nothing on the sheet may go past it. Only
  /// when the lesson says nothing does the class level decide.
  static int numberCeilingFor(WorksheetGenerationRequest request) {
    final Iterable<RegExpMatch> matches = RegExp(r'\d+')
        .allMatches('${request.learningOutcome} ${request.lessonTitle}');
    int highest = 0;
    for (final RegExpMatch match in matches) {
      final int? value = int.tryParse(match.group(0) ?? '');
      if (value != null && value > highest && value <= 100) highest = value;
    }
    if (highest >= 5) return highest;

    // A sensible ceiling per class, used only when the lesson names no range.
    return switch (request.classNumber) {
      <= 1 => 10,
      2 => 20,
      3 => 50,
      _ => 100,
    };
  }

  /// The objects the questions draw.
  ///
  /// The teacher's choice wins. With nothing chosen and familiar examples on,
  /// it falls back to things a village classroom already has to hand.
  static List<VisualExample> _objectsFor(WorksheetGenerationRequest request) {
    if (request.visualExamples.isNotEmpty) return request.visualExamples;
    return request.culturallyFamiliarExamples
        ? const <VisualExample>[
            VisualExample.trees,
            VisualExample.householdObjects,
            VisualExample.animals,
          ]
        : const <VisualExample>[VisualExample.apples];
  }

  /// Difficulty changes the numbers, the gaps and the distractors — not just a
  /// label. Two worksheets asked for at different levels are different sheets.
  ({int low, int high, int step, int optionCount}) _bandFor(
    WorksheetDifficulty difficulty,
    int ceiling,
  ) =>
      switch (difficulty) {
        WorksheetDifficulty.easy => (
            low: 1,
            high: ceiling <= 5 ? ceiling : (ceiling / 2).round(),
            step: 1,
            optionCount: 2,
          ),
        WorksheetDifficulty.medium => (
            low: 2,
            high: ceiling,
            step: 1,
            optionCount: 3,
          ),
        WorksheetDifficulty.advanced => (
            low: 2,
            high: ceiling,
            step: 2,
            optionCount: 4,
          ),
      };

  WorksheetQuestion _build({
    required WorksheetGenerationRequest request,
    required QuestionType type,
    required VisualExample object,
    required int ceiling,
    required int index,
  }) {
    final ({int low, int high, int step, int optionCount}) band =
        _bandFor(request.difficulty, ceiling);
    final int span = (band.high - band.low + 1).clamp(1, 100);

    // Deterministic: the same request always produces the same sheet, which is
    // what makes the output testable and reprintable.
    final int value = band.low + (_seed(request, index) % span);
    final String concept = request.concepts.isEmpty
        ? request.lessonTitle
        : request.concepts[index % request.concepts.length];
    final String id = 'q${index + 1}-${type.name}';

    switch (type) {
      case QuestionType.countingObjects:
        return WorksheetQuestion(
          id: id,
          type: type,
          questionText: '${object.hindiLabel} गिनकर संख्या लिखो।',
          correctAnswer: '$value',
          explanation: 'There are $value ${object.label.toLowerCase()}.',
          visualAsset: object.name,
          visualCount: value,
          concept: concept,
          order: index + 1,
        );

      case QuestionType.matchNumbers:
        final int other = value == band.high ? band.low : value + 1;
        return WorksheetQuestion(
          id: id,
          type: type,
          questionText: 'संख्या $value को सही समूह से मिलाओ।',
          options: <String>['$value', '$other'],
          correctAnswer: '$value',
          explanation: 'The group with $value '
              '${object.label.toLowerCase()} matches $value.',
          visualAsset: object.name,
          visualCount: value,
          concept: concept,
          order: index + 1,
        );

      case QuestionType.fillInTheBlanks:
        final int start = value.clamp(band.low, (band.high - band.step * 3)
            .clamp(band.low, band.high));
        final int missing = start + band.step * 2;
        final String sequence = <String>[
          '$start',
          '${start + band.step}',
          '__',
          '${start + band.step * 3}',
        ].join(', ');
        return WorksheetQuestion(
          id: id,
          type: type,
          questionText: 'क्रम पूरा करो: $sequence',
          correctAnswer: '$missing',
          explanation: 'The sequence goes up by ${band.step}, so the missing '
              'number is $missing.',
          concept: concept,
          order: index + 1,
        );

      case QuestionType.visualIdentification:
        return WorksheetQuestion(
          id: id,
          type: type,
          questionText: 'कितने ${object.hindiLabel} हैं? सही संख्या चुनो।',
          options: _distractors(value, band.optionCount, ceiling),
          correctAnswer: '$value',
          explanation: 'Counting them gives $value.',
          visualAsset: object.name,
          visualCount: value,
          concept: concept,
          order: index + 1,
        );
    }
  }

  /// Wrong answers that are close enough to be worth thinking about, and never
  /// outside the lesson's number range.
  static List<String> _distractors(int answer, int count, int ceiling) {
    final Set<int> values = <int>{answer};
    int offset = 1;
    while (values.length < count && offset <= ceiling) {
      for (final int candidate in <int>[answer - offset, answer + offset]) {
        if (candidate >= 1 && candidate <= ceiling) values.add(candidate);
        if (values.length >= count) break;
      }
      offset++;
    }
    final List<int> ordered = values.toList()..sort();
    return <String>[for (final int v in ordered) '$v'];
  }

  /// A small, stable pseudo-random value. Not cryptographic and not meant to
  /// be: it only has to spread the numbers across the band the same way twice.
  static int _seed(WorksheetGenerationRequest request, int index) {
    int hash = 0x811c9dc5;
    for (final int unit in '${request.lessonId}'
            '${request.difficulty.name}'
            '${request.variant}'
            '$index'
        .codeUnits) {
      hash = (hash ^ unit) * 0x01000193 & 0xFFFFFFFF;
    }
    return hash % 1000;
  }

  String _teacherNotes(WorksheetGenerationRequest request, int ceiling) =>
      'Numbers stay within 1 to $ceiling, from the lesson outcome. '
      'Difficulty: ${request.difficulty.label}. '
      'Answers are on the answer key below each question.';

  // --- Bilingual content ---------------------------------------------------

  /// Asks the translation service for each question, once per distinct string.
  ///
  /// Where it has no answer the question stays in one language. Nothing is
  /// invented here: a worksheet is printed and taken home, and a guessed
  /// sentence on it is worse than a missing one.
  Future<List<WorksheetQuestion>> _translateAll(
    List<WorksheetQuestion> questions,
    WorksheetGenerationRequest request,
  ) async {
    final TextTranslationService? translator = _translator;
    if (translator == null) return questions;

    final Map<String, String?> seen = <String, String?>{};
    final List<WorksheetQuestion> out = <WorksheetQuestion>[];

    for (final WorksheetQuestion question in questions) {
      if (!seen.containsKey(question.questionText)) {
        seen[question.questionText] = await _translate(
          translator,
          question.questionText,
          request,
        );
      }
      final String? translated = seen[question.questionText];
      out.add(
        translated == null
            ? question
            : WorksheetQuestion(
                id: question.id,
                type: question.type,
                questionText: question.questionText,
                translatedQuestionText: translated,
                options: question.options,
                correctAnswer: question.correctAnswer,
                explanation: question.explanation,
                visualAsset: question.visualAsset,
                visualCount: question.visualCount,
                concept: question.concept,
                order: question.order,
              ),
      );
    }
    return out;
  }

  Future<String?> _translate(
    TextTranslationService translator,
    String text,
    WorksheetGenerationRequest request,
  ) async {
    try {
      final TranslationResult result = await translator.translate(
        TranslationRequest(
          sourceText: text,
          sourceLanguage: request.teachingLanguage.localeId,
          targetLanguage: request.targetLanguage.localeId,
          context: <String, dynamic>{
            'lesson_id': request.lessonId,
            'lesson_title': request.lessonTitle,
            'learning_outcome': request.learningOutcome,
            'class_level': request.classNumber,
            'register': 'worksheet',
          },
        ),
      );
      return result.translatedText;
    } on TextTranslationFailure {
      // Expected for anything the phrasebook has not been taught. Not an
      // error worth showing the teacher per question; the worksheet reports
      // how many lines carry both languages.
      return null;
    } on Object catch (error) {
      AppLogger.error('worksheet translation failed', error: error);
      return null;
    }
  }
}
