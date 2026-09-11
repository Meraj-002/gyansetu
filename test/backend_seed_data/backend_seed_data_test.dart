// The development backend's seeded rows, as the sync catalog and pull documents
// actually emit them, proving the parsed data reaches the models and the lesson
// library (the screen's repository boundary) without any UI changes. The JSON
// shapes below are the literal output of `scripts/seed_dev.py` verified by
// hand against the running FastAPI server.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gyan_setu_ai/app/theme.dart';
import 'package:gyan_setu_ai/features/classroom/models/classroom_session.dart';
import 'package:gyan_setu_ai/features/lessons/lesson_library_screen.dart';
import 'package:gyan_setu_ai/features/lessons/services/recommendation_repository.dart';
import 'package:gyan_setu_ai/features/setup/models/offline_resource_status.dart';
import 'package:gyan_setu_ai/features/setup/services/offline_resource_manager.dart';
import 'package:gyan_setu_ai/models/assessment_result.dart';
import 'package:gyan_setu_ai/models/lesson.dart';
import 'package:gyan_setu_ai/models/progress_event.dart';
import 'package:gyan_setu_ai/models/question.dart';
import 'package:gyan_setu_ai/models/worksheet.dart';
import 'package:gyan_setu_ai/services/connectivity/connectivity_service.dart';
import 'package:gyan_setu_ai/services/storage/secure_storage_service.dart';
import 'package:gyan_setu_ai/services/sync/synced_catalog_store.dart';

import '../lessons/lesson_test_doubles.dart' as fakes;
import '../setup/setup_test_doubles.dart' as setup_doubles;

/// Exactly what `GET /api/v1/lessons` and the sync pull catalog return for the
/// seeded "Counting 1 to 10" lesson.
Map<String, dynamic> _countingLessonJson() => <String, dynamic>{
      'id': 'c1-num-counting-1-10',
      'title': 'Counting 1 to 10',
      'description': 'Count everyday objects from one to ten with the class.',
      'subject': 'numeracy',
      'classNumber': 1,
      'learningOutcome': 'Learners count and name quantities from 1 to 10.',
      'durationMinutes': 30,
      'lessonOrder': 1,
      'thumbnailAsset': null,
      'resourceIds': <String>[
        'c1-num-counting-1-10.content',
        'c1-num-counting-1-10.audio',
      ],
      'concepts': <String>['countingObjects', 'numbers1to5', 'numbers6to10'],
      'audioResourceId': null,
      'worksheetResourceId': 'c1-ws-counting-1-10',
      'flashcardResourceId': null,
      'createdAt': '2026-08-29T22:03:31.580710Z',
      'updatedAt': '2026-08-29T22:03:31.580711Z',
    };

Map<String, dynamic> _santaliLessonJson() => <String, dynamic>{
      'id': 'c1-lit-santali-words',
      'title': 'Counting in Santali',
      'description':
          'The documented Santali numerals one to five, as a language lesson.',
      'subject': 'foundationalLiteracy',
      'classNumber': 1,
      'learningOutcome':
          'Learners hear and say the Santali numerals one to five.',
      'durationMinutes': 30,
      'lessonOrder': 5,
      'thumbnailAsset': null,
      'resourceIds': <String>[
        'c1-lit-santali-words.content',
        'c1-lit-santali-words.audio',
      ],
      'concepts': <String>['vocabulary'],
      'audioResourceId': null,
      'worksheetResourceId': null,
      'flashcardResourceId': null,
      'createdAt': '2026-08-29T22:03:31.581000Z',
      'updatedAt': '2026-08-29T22:03:31.581001Z',
    };

/// The seeded worksheet as the sync pull document carries it (camelCase,
/// teacher-owned).
Map<String, dynamic> _countingWorksheetJson() => <String, dynamic>{
      'id': 'c1-ws-counting-1-10',
      'teacherId': 'dev-teacher-1',
      'lessonId': 'c1-num-counting-1-10',
      'title': 'Count 1 to 10 — Worksheet',
      'learningOutcome': 'Learners count and name quantities from 1 to 10.',
      'classNumber': 1,
      'subject': 'numeracy',
      'teachingLanguage': 'hindi',
      'targetLanguage': 'santali',
      'difficulty': 'easy',
      'questions': <Map<String, dynamic>>[
        <String, dynamic>{
          'id': 'c1-q-count-1',
          'type': 'countingObjects',
          'questionText': 'Count the objects. How many apples?',
          'correctAnswer': '5',
          'order': 1,
          'translatedQuestionText': 'गिनो। कितने सेब हैं?',
          'options': <String>['3', '4', '5', '6'],
          'explanation': null,
          'visualAsset': 'apples',
          'visualCount': 5,
          'concept': 'countingObjects',
        },
        <String, dynamic>{
          'id': 'c1-q-count-2',
          'type': 'countingObjects',
          'questionText': 'Count the objects. How many trees?',
          'correctAnswer': '3',
          'order': 2,
          'translatedQuestionText': 'गिनो। कितने पेड़ हैं?',
          'options': <String>['2', '3', '4', '5'],
          'explanation': null,
          'visualAsset': 'trees',
          'visualCount': 3,
          'concept': 'countingObjects',
        },
      ],
      'visualExamples': <String>[],
      'culturallyFamiliarExamples': true,
      'teacherNotes': 'Authored development sheet: count bundled picture sets.',
      'variant': 0,
      'requestedQuestionCount': 4,
      'generationSource': 'localOffline',
      'generatedAt': '2026-08-29T22:08:00.000000Z',
      'createdAt': '2026-08-29T22:08:00.000Z',
      'updatedAt': '2026-08-29T22:08:00.000Z',
    };

/// The seeded progress trail as restored from `GET /api/v1/progress`.
List<Map<String, dynamic>> _progressEventsJson() => <Map<String, dynamic>>[
      <String, dynamic>{
        'id': 'lessonStarted#c1-num-counting-1-10',
        'type': 'lessonStarted',
        'occurredAt': '2026-08-29T21:05:00.000Z',
        'lessonId': 'c1-num-counting-1-10',
        'metadata': <String, dynamic>{},
        'createdAt': '2026-08-29T21:05:00.000Z',
        'updatedAt': '2026-08-29T21:05:00.000Z',
      },
      <String, dynamic>{
        'id': 'lessonCompleted#c1-num-counting-1-10',
        'type': 'lessonCompleted',
        'occurredAt': '2026-08-29T21:10:00.000Z',
        'lessonId': 'c1-num-counting-1-10',
        'metadata': <String, dynamic>{},
        'createdAt': '2026-08-29T21:10:00.000Z',
        'updatedAt': '2026-08-29T21:10:00.000Z',
      },
      <String, dynamic>{
        'id': 'assessmentCompleted#c1-num-counting-1-10',
        'type': 'assessmentCompleted',
        'occurredAt': '2026-08-29T21:15:00.000Z',
        'lessonId': 'c1-num-counting-1-10',
        'metadata': <String, dynamic>{'score': '3'},
        'createdAt': '2026-08-29T21:15:00.000Z',
        'updatedAt': '2026-08-29T21:15:00.000Z',
      },
    ];

/// The seeded classroom session as the sync pull emits it.
Map<String, dynamic> _sessionJson() => <String, dynamic>{
      'sessionId': 'DEV-CLS-COUNTING-1-10',
      'teacherId': 'dev-teacher-1',
      'lessonId': 'c1-num-counting-1-10',
      'lessonTitle': 'Counting 1 to 10',
      'classNumber': 1,
      'subject': 'numeracy',
      'teachingLanguage': 'hindi',
      'targetLanguage': 'santali',
      'startedAt': '2026-08-29T21:00:00.000Z',
      'endedAt': '2026-08-29T21:30:00.000Z',
      'completed': true,
      'savedAt': '2026-08-29T21:30:01.000Z',
      'syncStatus': 'synced',
      'turns': <Map<String, dynamic>>[
        <String, dynamic>{
          'id': 'dev-turn-1',
          'sessionId': 'DEV-CLS-COUNTING-1-10',
          'speaker': 'teacher',
          'sourceLanguage': 'hindi',
          'targetLanguage': 'santali',
          'timestamp': '2026-08-29T21:00:05.000Z',
          'status': 'played',
          'sourceText': 'Count the apples.',
          'translatedText': 'सेबों को गिनो।',
        },
        <String, dynamic>{
          'id': 'dev-turn-2',
          'sessionId': 'DEV-CLS-COUNTING-1-10',
          'speaker': 'teacher',
          'sourceLanguage': 'hindi',
          'targetLanguage': 'santali',
          'timestamp': '2026-08-29T21:00:10.000Z',
          'status': 'played',
          'sourceText': 'How many apples are there?',
          'translatedText': 'कितने सेब हैं?',
        },
      ],
    };

void main() {
  group('seeded backend data parses into app models', () {
    test('lesson catalogue', () {
      final Lesson counting = Lesson.fromJson(_countingLessonJson());
      expect(counting.id, 'c1-num-counting-1-10');
      expect(counting.title, 'Counting 1 to 10');
      expect(counting.classNumber, 1);
      expect(counting.subject.name, 'numeracy');
      expect(counting.worksheetResourceId, 'c1-ws-counting-1-10');
      expect(counting.concepts, contains('countingObjects'));

      final Lesson santali = Lesson.fromJson(_santaliLessonJson());
      expect(santali.subject.name, 'foundationalLiteracy');
      expect(santali.lessonOrder, 5);
    });

    test('round-trips through the SyncedCatalogStore the pull writes', () async {
      final SyncedCatalogStore store =
          SyncedCatalogStore(InMemorySecureStorageService());
      await store.saveLessons(<Lesson>[
        Lesson.fromJson(_countingLessonJson()),
        Lesson.fromJson(_santaliLessonJson()),
      ]);
      final List<Lesson> restored = await store.lessons();
      expect(restored, hasLength(2));
      expect(
        restored.map((Lesson l) => l.id),
        containsAll(<String>[
          'c1-num-counting-1-10',
          'c1-lit-santali-words',
        ]),
      );
    });

    test('worksheets with their questions', () {
      final Worksheet sheet = Worksheet.fromJson(_countingWorksheetJson());
      expect(sheet.id, 'c1-ws-counting-1-10');
      expect(sheet.lessonId, 'c1-num-counting-1-10');
      expect(sheet.difficulty.name, 'easy');
      expect(sheet.generationSource.name, 'localOffline'); // honestly authored
      expect(sheet.isAiGenerated, isFalse);
      expect(sheet.questions, hasLength(2));

      final WorksheetQuestion first = sheet.questions.first;
      expect(first.type, QuestionType.countingObjects);
      expect(first.correctAnswer, '5'); // a String, as the model requires
      expect(first.options, <String>['3', '4', '5', '6']);
      expect(first.visualCount, 5);
      expect(first.isBilingual, isTrue);
      expect(VisualExample.byName(first.visualAsset), VisualExample.apples);
      expect(sheet.isFullyBilingual, isTrue);
    });

    test('progress events', () {
      final List<ProgressEvent> events = <ProgressEvent>[
        for (final Map<String, dynamic> json in _progressEventsJson())
          ProgressEvent.fromJson(json),
      ];
      expect(events, hasLength(3));
      expect(events[0].type, ProgressEventType.lessonStarted);
      expect(events[1].type, ProgressEventType.lessonCompleted);
      final ProgressEvent assessment = events[2];
      expect(assessment.type, ProgressEventType.assessmentCompleted);
      expect(assessment.intValue('score'), 3);
      expect(assessment.type.isClassroomActivity, isTrue);
    });

    test('saved classroom session with its turns', () {
      final ClassroomSession session = ClassroomSession.fromJson(_sessionJson());
      expect(session.sessionId, 'DEV-CLS-COUNTING-1-10');
      expect(session.totalTurns, 2);
      expect(session.interactionsCompleted, 2); // both turns reached "played"
      expect(session.completed, isTrue);
      expect(session.syncStatus.name, 'synced');
    });

    test('assessment answers now parse (canonical map shape), and a legacy '
        'list is still refused at the pull boundary', () {
      final Map<String, dynamic> assessmentJson = <String, dynamic>{
        'id': 'assessment-c1-num-counting-1-10',
        'teacherId': 'dev-teacher-1',
        'lessonId': 'c1-num-counting-1-10',
        'score': 3,
        'total': 4,
        'concepts': <Map<String, dynamic>>[
          <String, dynamic>{'concept': 'countingObjects', 'correct': 3, 'total': 4},
        ],
        'startedAt': '2026-08-29T21:14:00.000Z',
        'finishedAt': '2026-08-29T21:16:05.000Z',
        // The canonical shape both ends agree on: answers is a map keyed by
        // question id, exactly what QuizResult.toJson()/fromJson() use.
        'answers': <String, dynamic>{
          'c1-q-count-1': <String, dynamic>{
            'questionId': 'c1-q-count-1',
            'selectedOptionId': '5',
            'correct': true,
            'answeredAt': '2026-08-29T21:14:40.000Z',
            'timeTakenMs': 9000,
          },
          'c1-q-count-2': <String, dynamic>{
            'questionId': 'c1-q-count-2',
            'selectedOptionId': '2',
            'correct': false,
            'answeredAt': '2026-08-29T21:15:10.000Z',
            'timeTakenMs': 11000,
          },
          'c1-q-count-3': <String, dynamic>{
            'questionId': 'c1-q-count-3',
            'selectedOptionId': '4',
            'correct': true,
            'answeredAt': '2026-08-29T21:15:35.000Z',
            'timeTakenMs': 8000,
          },
          'c1-q-count-4': <String, dynamic>{
            'questionId': 'c1-q-count-4',
            'selectedOptionId': '5',
            'correct': true,
            'answeredAt': '2026-08-29T21:16:00.000Z',
            'timeTakenMs': 6500,
          },
        },
      };

      final QuizResult result = QuizResult.fromJson(assessmentJson);
      expect(result.lessonId, 'c1-num-counting-1-10');
      expect(result.score, 3);
      expect(result.total, 4);
      expect(result.percentage, 75);
      expect(result.answers, hasLength(4));
      expect(result.answers['c1-q-count-1']!.selectedOptionId, '5');
      expect(result.answers['c1-q-count-1']!.correct, isTrue);
      expect(result.answers['c1-q-count-2']!.correct, isFalse);

      final ConceptPerformance concept = result.concepts.first;
      expect(concept.concept.name, 'countingObjects');
      expect(concept.correct, 3);
      expect(concept.total, 4);
      expect(concept.needsReinforcement, isTrue);

      // Regression guard on the old disagreement: a list-shaped answers value
      // must still not map into QuizResult, so a legacy row stays server-side
      // and the device keeps its own result instead of crashing the pull.
      final Map<String, dynamic> legacy =
          Map<String, dynamic>.from(assessmentJson)
            ..['answers'] = <dynamic>[];
      expect(
        () => QuizResult.fromJson(legacy),
        throwsA(isA<TypeError>()),
      );
    });
  });

  group('seeded catalogue feeds the lesson library the screen reads', () {
    testWidgets('the library lists the seeded lessons', (WidgetTester tester) async {
      final List<Lesson> catalog = <Lesson>[
        Lesson.fromJson(_countingLessonJson()),
        Lesson.fromJson(_santaliLessonJson()),
      ];

      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(430, 2600);
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: LessonLibraryScreen(
            lessons: fakes.FakeLessonRepository(catalogue: catalog),
            progress: fakes.FakeProgressRepository(),
            downloads: fakes.FakeDownloadRepository(),
            downloader: fakes.FakeDownloadService(),
            recommendations: const RuleBasedRecommendationRepository(),
            classrooms: setup_doubles.TestRepository(existing: fakes.testClassroom()),
            resources: const StaticOfflineResourceManager(
              OfflineResourceStatus(readiness: OfflineReadiness.ready),
            ),
            connectivityService:
                StaticConnectivityService(ConnectionStatus.online),
            teacherId: fakes.kTeacherId,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Shown in the All Lessons list (and possibly the recommendation
      // carousel too), but never by a hard-coded catalogue.
      expect(find.text('Counting 1 to 10'), findsWidgets);
      expect(find.text('Counting in Santali'), findsWidgets);
    });
  });
}