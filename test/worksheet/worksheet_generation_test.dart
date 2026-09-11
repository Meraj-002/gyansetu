import 'package:flutter_test/flutter_test.dart';
import 'package:gyan_setu_ai/features/setup/models/classroom_setup.dart';
import 'package:gyan_setu_ai/features/worksheet/services/local_worksheet_generation_service.dart';
import 'package:gyan_setu_ai/features/worksheet/services/worksheet_generation_service.dart';
import 'package:gyan_setu_ai/features/worksheet/services/worksheet_repository.dart';
import 'package:gyan_setu_ai/features/worksheet/services/worksheet_validator.dart';
import 'package:gyan_setu_ai/models/question.dart';
import 'package:gyan_setu_ai/models/worksheet.dart';

import 'worksheet_doubles.dart';

void main() {
  late LocalWorksheetGenerationService generator;

  setUp(() => generator = LocalWorksheetGenerationService());

  group('curriculum alignment', () {
    test('takes its number range from the lesson outcome', () {
      expect(
        LocalWorksheetGenerationService.numberCeilingFor(testRequest()),
        10,
      );
      expect(
        LocalWorksheetGenerationService.numberCeilingFor(
          testRequest(
            lessonTitle: 'Counting 1–20',
            learningOutcome: 'Count objects from 1 to 20.',
          ),
        ),
        20,
      );
    });

    test('falls back to the class level when the lesson names no range', () {
      expect(
        LocalWorksheetGenerationService.numberCeilingFor(
          testRequest(
            lessonTitle: 'Shapes Around Us',
            learningOutcome: 'Identify and name common shapes.',
            classNumber: 2,
          ),
        ),
        20,
      );
    });

    test('never uses a number past the lesson range', () async {
      final Worksheet worksheet = await generator.generate(
        testRequest(numberOfQuestions: 15),
      );

      for (final WorksheetQuestion question in worksheet.questions) {
        final Iterable<int> numbers = RegExp(r'\d+')
            .allMatches(
              '${question.correctAnswer} ${question.options.join(' ')}',
            )
            .map((RegExpMatch m) => int.parse(m.group(0)!));
        for (final int value in numbers) {
          expect(value, lessThanOrEqualTo(10));
        }
      }
    });

    test('names the lesson concept each question drills', () async {
      final Worksheet worksheet = await generator.generate(testRequest());

      for (final WorksheetQuestion question in worksheet.questions) {
        expect(question.concept, isNotNull);
        expect(kCountingConcepts, contains(question.concept));
      }
    });
  });

  group('generation', () {
    test('produces exactly the number of questions asked for', () async {
      for (final int count in <int>[5, 10, 15]) {
        final Worksheet worksheet =
            await generator.generate(testRequest(numberOfQuestions: count));
        expect(worksheet.questionCount, count);
      }
    });

    test('uses every question type the teacher chose', () async {
      final Worksheet worksheet = await generator.generate(
        testRequest(
          questionTypes: <QuestionType>{
            QuestionType.countingObjects,
            QuestionType.fillInTheBlanks,
          },
          numberOfQuestions: 10,
        ),
      );

      final Set<QuestionType> used = worksheet.questions
          .map((WorksheetQuestion q) => q.type)
          .toSet();
      expect(used, <QuestionType>{
        QuestionType.countingObjects,
        QuestionType.fillInTheBlanks,
      });
    });

    test('never uses a type the teacher did not choose', () async {
      final Worksheet worksheet = await generator.generate(
        testRequest(
          questionTypes: <QuestionType>{QuestionType.matchNumbers},
        ),
      );

      for (final WorksheetQuestion question in worksheet.questions) {
        expect(question.type, QuestionType.matchNumbers);
      }
    });

    test('difficulty changes the worksheet, not only a label', () async {
      final Worksheet easy = await generator.generate(
        testRequest(difficulty: WorksheetDifficulty.easy),
      );
      final Worksheet advanced = await generator.generate(
        testRequest(difficulty: WorksheetDifficulty.advanced),
      );

      // The stem of a counting question is the same at any level; what
      // changes is the numbers behind it, which is where difficulty lives.
      final List<String> easyAnswers = <String>[
        for (final WorksheetQuestion q in easy.questions) q.correctAnswer,
      ];
      final List<String> advancedAnswers = <String>[
        for (final WorksheetQuestion q in advanced.questions) q.correctAnswer,
      ];
      expect(easyAnswers, isNot(equals(advancedAnswers)));

      // Advanced offers more to choose between.
      final WorksheetQuestion advancedChoice = advanced.questions.firstWhere(
        (WorksheetQuestion q) => q.options.isNotEmpty,
      );
      final WorksheetQuestion easyChoice = easy.questions.firstWhere(
        (WorksheetQuestion q) => q.options.isNotEmpty,
      );
      expect(
        advancedChoice.options.length,
        greaterThan(easyChoice.options.length),
      );
    });

    test('is deterministic, so the same choices reprint the same sheet',
        () async {
      final Worksheet first = await generator.generate(testRequest());
      final Worksheet second = await generator.generate(testRequest());

      expect(
        <String>[for (final WorksheetQuestion q in first.questions) q.questionText],
        <String>[for (final WorksheetQuestion q in second.questions) q.questionText],
      );
      expect(
        <String>[for (final WorksheetQuestion q in first.questions) q.correctAnswer],
        <String>[for (final WorksheetQuestion q in second.questions) q.correctAnswer],
      );
    });

    test('draws the objects the teacher chose', () async {
      final Worksheet worksheet = await generator.generate(
        testRequest(
          visualExamples: <VisualExample>[VisualExample.trees],
          questionTypes: <QuestionType>{QuestionType.countingObjects},
        ),
      );

      for (final WorksheetQuestion question in worksheet.questions) {
        expect(question.visualAsset, VisualExample.trees.name);
      }
      expect(worksheet.visualExamples, <VisualExample>[VisualExample.trees]);
    });

    test('every answer to a multiple-choice question is among its options',
        () async {
      final Worksheet worksheet = await generator.generate(
        testRequest(
          questionTypes: <QuestionType>{QuestionType.visualIdentification},
          difficulty: WorksheetDifficulty.advanced,
        ),
      );

      for (final WorksheetQuestion question in worksheet.questions) {
        expect(question.options, contains(question.correctAnswer));
      }
    });

    test('reports itself as locally generated, never as AI', () async {
      final Worksheet worksheet = await generator.generate(testRequest());

      expect(worksheet.generationSource, GenerationSource.localOffline);
      expect(worksheet.isAiGenerated, isFalse);
      expect(generator.source.isAi, isFalse);
    });

    test('refuses a request with no question types', () async {
      expect(
        () => generator.generate(
          testRequest(questionTypes: <QuestionType>{}),
        ),
        throwsA(isA<WorksheetGenerationFailure>()),
      );
    });

    test('carries the classroom languages through to the worksheet', () async {
      final Worksheet worksheet = await generator.generate(
        testRequest(target: TargetLanguage.mundari),
      );

      expect(worksheet.targetLanguage, TargetLanguage.mundari);
      expect(worksheet.teachingLanguage, TeachingMedium.hindi);
      expect(worksheet.languagePair, 'Hindi + Mundari');
    });
  });

  group('bilingual content', () {
    test('adds the mother tongue where a translation exists', () async {
      final LocalWorksheetGenerationService withTranslator =
          LocalWorksheetGenerationService(
        translator: FakeWorksheetTranslator(translated: 'Kete ul menaka?'),
      );

      final Worksheet worksheet =
          await withTranslator.generate(testRequest(numberOfQuestions: 5));

      expect(worksheet.isFullyBilingual, isTrue);
      expect(worksheet.questions.first.translatedQuestionText,
          'Kete ul menaka?');
    });

    test('leaves a question in one language rather than inventing a line',
        () async {
      final LocalWorksheetGenerationService withTranslator =
          LocalWorksheetGenerationService(
        translator: FakeWorksheetTranslator(fails: true),
      );

      final Worksheet worksheet =
          await withTranslator.generate(testRequest(numberOfQuestions: 5));

      expect(worksheet.bilingualCount, 0);
      for (final WorksheetQuestion question in worksheet.questions) {
        expect(question.translatedQuestionText, isNull);
        expect(question.questionText, isNotEmpty);
      }
    });

    test('asks the translator once per distinct question', () async {
      final FakeWorksheetTranslator translator =
          FakeWorksheetTranslator(translated: 'x');
      final LocalWorksheetGenerationService withTranslator =
          LocalWorksheetGenerationService(translator: translator);

      await withTranslator.generate(
        testRequest(
          numberOfQuestions: 10,
          questionTypes: <QuestionType>{QuestionType.countingObjects},
          visualExamples: <VisualExample>[VisualExample.apples],
        ),
      );

      // Ten counting questions about apples share one question sentence.
      expect(translator.calls, 1);
    });
  });

  group('validation', () {
    test('accepts a well-formed worksheet', () async {
      final WorksheetGenerationRequest request = testRequest();
      final Worksheet worksheet = await generator.generate(request);

      expect(WorksheetValidator.validate(worksheet, request), isEmpty);
    });

    test('catches the wrong number of questions', () async {
      final WorksheetGenerationRequest request = testRequest();
      final Worksheet worksheet = await generator.generate(request);
      final Worksheet short = worksheetWith(
        worksheet,
        questions: worksheet.questions.take(3).toList(),
      );

      expect(
        WorksheetValidator.validate(short, request).first.message,
        contains('3 questions but 10 were asked for'),
      );
    });

    test('catches an empty question', () async {
      final WorksheetGenerationRequest request = testRequest();
      final Worksheet worksheet = await generator.generate(request);
      final Worksheet broken = worksheetWith(
        worksheet,
        questions: <WorksheetQuestion>[
          ...worksheet.questions.skip(1),
          WorksheetQuestion(
            id: 'blank',
            type: QuestionType.countingObjects,
            questionText: '   ',
            correctAnswer: '3',
            order: 1,
          ),
        ],
      );

      expect(
        WorksheetValidator.validate(broken, request)
            .map((WorksheetProblem p) => p.message),
        contains('The question is empty.'),
      );
    });

    test('catches an answer that is not among the options', () async {
      final WorksheetGenerationRequest request = testRequest();
      final Worksheet worksheet = await generator.generate(request);
      final Worksheet broken = worksheetWith(
        worksheet,
        questions: <WorksheetQuestion>[
          ...worksheet.questions.skip(1),
          const WorksheetQuestion(
            id: 'bad-options',
            type: QuestionType.countingObjects,
            questionText: 'How many?',
            options: <String>['1', '2'],
            correctAnswer: '9',
            order: 1,
          ),
        ],
      );

      expect(
        WorksheetValidator.validate(broken, request)
            .map((WorksheetProblem p) => p.message),
        contains('The answer is not one of the options.'),
      );
    });

    test('catches duplicate question ids', () async {
      final WorksheetGenerationRequest request = testRequest();
      final Worksheet worksheet = await generator.generate(request);
      final Worksheet broken = worksheetWith(
        worksheet,
        questions: <WorksheetQuestion>[
          worksheet.questions.first,
          ...worksheet.questions.skip(1).take(8),
          worksheet.questions.first,
        ],
      );

      expect(
        WorksheetValidator.validate(broken, request)
            .map((WorksheetProblem p) => p.message),
        contains('Two questions share an id.'),
      );
    });

    test('catches a worksheet built for the wrong lesson', () async {
      final WorksheetGenerationRequest request = testRequest();
      final Worksheet worksheet = await generator.generate(request);
      final Worksheet broken = worksheetWith(worksheet, lessonId: 'other');

      expect(
        WorksheetValidator.validate(broken, request)
            .map((WorksheetProblem p) => p.message),
        contains('The worksheet was built for a different lesson.'),
      );
    });
  });

  group('persistence', () {
    test('a saved worksheet reads back with every question', () async {
      final InMemoryWorksheetRepository repository =
          InMemoryWorksheetRepository();
      final Worksheet worksheet = await generator.generate(testRequest());

      await repository.save(worksheet);
      final Worksheet? reopened = await repository.byId(worksheet.id);

      expect(reopened, isNotNull);
      expect(reopened!.questionCount, worksheet.questionCount);
    });

    test('survives a round trip through JSON', () async {
      final Worksheet worksheet = await generator.generate(testRequest());
      final Worksheet decoded = Worksheet.fromJson(worksheet.toJson());

      expect(decoded.id, worksheet.id);
      expect(decoded.lessonId, worksheet.lessonId);
      expect(decoded.questionCount, worksheet.questionCount);
      expect(decoded.difficulty, worksheet.difficulty);
      expect(decoded.targetLanguage, worksheet.targetLanguage);
      expect(decoded.generationSource, worksheet.generationSource);
      expect(
        decoded.questions.first.correctAnswer,
        worksheet.questions.first.correctAnswer,
      );
    });

    test('lists worksheets for one lesson', () async {
      final InMemoryWorksheetRepository repository =
          InMemoryWorksheetRepository();
      await repository.save(await generator.generate(testRequest()));
      await repository.save(
        await generator.generate(testRequest(lessonId: 'other-lesson')),
      );

      final List<Worksheet> forLesson =
          await repository.forLesson('c1-num-counting-1-10');
      expect(forLesson, hasLength(1));
    });
  });
}
