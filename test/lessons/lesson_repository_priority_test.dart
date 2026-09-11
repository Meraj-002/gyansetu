// Catalogue source priority: `PreferredSyncedLessonRepository` (the default
// every screen builds) must prefer the synchronized backend catalogue when one
// is cached, and fall back deterministically to the bundled catalogue when the
// store is empty, corrupt, never-synced, or the backend is unavailable.
//
// This is the milestone's test matrix (A–J): local-only, synced available,
// synced empty, sync failure, backend unavailable, offline after sync, detail
// from synced, detail from local fallback, and repository source priority.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gyan_setu_ai/app/theme.dart';
import 'package:gyan_setu_ai/features/lessons/lesson_library_screen.dart';
import 'package:gyan_setu_ai/features/lessons/services/lesson_repository.dart';
import 'package:gyan_setu_ai/features/lessons/services/recommendation_repository.dart';
import 'package:gyan_setu_ai/features/setup/models/classroom_setup.dart';
import 'package:gyan_setu_ai/features/setup/models/offline_resource_status.dart';
import 'package:gyan_setu_ai/features/setup/services/offline_resource_manager.dart';
import 'package:gyan_setu_ai/models/lesson.dart';
import 'package:gyan_setu_ai/services/connectivity/connectivity_service.dart';
import 'package:gyan_setu_ai/services/storage/secure_storage_service.dart';
import 'package:gyan_setu_ai/services/sync/synced_catalog_store.dart';

import 'lesson_test_doubles.dart' as fakes;
import '../setup/setup_test_doubles.dart' as setup_doubles;

/// A synced lesson that exists only in the server catalogue (its id is not in
/// the bundled MockLessons set), so tests can tell the two sources apart.
Lesson _syncedLesson({
  String id = 'c1-num-colors',
  String title = 'Colors Around Us',
  int order = 1,
}) =>
    Lesson(
      id: id,
      title: title,
      description: '$title (from the backend catalogue)',
      subject: ClassroomSubject.numeracy,
      classNumber: 1,
      learningOutcome: 'Name common colours around us.',
      durationMinutes: 12,
      lessonOrder: order,
      createdAt: DateTime(2026, 8, 29),
      updatedAt: DateTime(2026, 8, 29),
    );

/// A lesson that exists only in the bundled data, so the fallback source is
/// unmistakable when it is served.
final Lesson _bundledOnly =
    fakes.testLesson(id: 'c1-lit-swar-a-aa-i', title: 'Swar: A, AA, I');

void main() {
  late InMemorySecureStorageService storage;
  late SyncedCatalogStore store;

  setUp(() {
    storage = InMemorySecureStorageService();
    store = SyncedCatalogStore(storage);
  });

  PreferredSyncedLessonRepository repository() =>
      PreferredSyncedLessonRepository(
        synced: store,
        fallback: LocalLessonRepository(
          downloads: fakes.FakeDownloadRepository(<String>{
            'c1-num-counting-1-10',
          }),
        ),
      );

  group('catalogue source priority', () {
    test('A/F. local-only catalogue: an empty store serves the bundled set',
        () async {
      final List<Lesson> lessons = await repository().lessons();

      expect(lessons, isNotEmpty);
      // Served from the fallback: the bundled (local) lessons, not the synced
      // ones. 'Colors Around Us' exists only in the synced fixture, and it is
      // absent here.
      expect(
        lessons.map((Lesson l) => l.title),
        isNot(contains('Colors Around Us')),
      );
      expect(
        lessons.map((Lesson l) => l.title),
        contains('Counting 1–10'),
      );
    });

    test('B. synced catalogue available: it is preferred over the bundled set',
        () async {
      await store.saveLessons(<Lesson>[_syncedLesson()]);

      final List<Lesson> lessons = await repository().lessons();
      final List<String> titles = lessons.map((Lesson l) => l.title).toList();

      expect(titles, contains('Colors Around Us'));
      // The bundled-only lesson is not in the synced catalogue, so it is not
      // served while the synced catalogue is the source.
      expect(titles, isNot(contains('Swar: A, AA, I')));
    });

    test('C. backend returned an empty catalogue: still falls back', () async {
      // A successful pull with zero lessons stores exactly []; that must not
      // be mistaken for "no data" being usable — the library stays populated.
      await store.saveLessons(const <Lesson>[]);

      final List<Lesson> lessons = await repository().lessons();
      expect(
        lessons.map((Lesson l) => l.title),
        contains('Counting 1–10'),
      );
    });

    test('D. sync failure leaves the fallback intact (corrupt cached bytes)',
        () async {
      await storage.write('sync.catalog.lessons', '{"not":"a-list"}');

      final List<Lesson> lessons = await repository().lessons();
      expect(
        lessons.map((Lesson l) => l.title),
        contains('Counting 1–10'),
      );
    });

    test('E. backend unavailable (or never reached) behaves like never synced',
        () async {
      // The store key simply was never written — identical to a sync that
      // failed before the pull. Nothing throws and the local catalogue shows.
      final List<Lesson> lessons = await repository().lessons();
      expect(lessons, isNotEmpty);
      expect(
        lessons.map((Lesson l) => l.title),
        contains('Counting 1–10'),
      );
    });

    test('G. synced content persists for offline use after a successful sync',
        () async {
      await store.saveLessons(<Lesson>[_syncedLesson()]);

      final PreferredSyncedLessonRepository repo = repository();
      // A second read (a later app start, offline) still sees the cached
      // catalogue because it lives in secure storage, not in memory.
      expect(
        (await repo.lessons()).map((Lesson l) => l.title),
        contains('Colors Around Us'),
      );
    });
  });

  group('lesson detail resolution', () {
    test('H. lessonById resolves a synced lesson from the synced catalogue',
        () async {
      await store.saveLessons(<Lesson>[_syncedLesson()]);

      final Lesson? found = await repository().lessonById('c1-num-colors');
      expect(found, isNotNull);
      expect(found!.title, 'Colors Around Us');
    });

    test('I. lessonById falls back to the bundled set when the synced '
        'catalogue does not contain the id', () async {
      await store.saveLessons(<Lesson>[_syncedLesson()]);

      final Lesson? found =
          await repository().lessonById(_bundledOnly.id);
      expect(found, isNotNull);
      expect(found!.title, 'Swar: A, AA, I');
    });

    test('I. lessonById falls back when the synced catalogue is empty',
        () async {
      final Lesson? found = await repository().lessonById('c1-num-counting-1-10');
      expect(found, isNotNull);
      expect(found!.title, 'Counting 1–10');
    });
  });

  group('J. repository source priority (today + offline availability)', () {
    test('lessonForToday is planned from the effective (synced) catalogue',
        () async {
      await store.saveLessons(<Lesson>[
        _syncedLesson(id: 'c1-lit-santali-words', title: 'Counting in Santali'),
      ]);

      final Lesson? today = await repository().lessonForToday(
        fakes.testClassroom(),
        on: DateTime(2026, 8, 1),
      );
      expect(today, isNotNull);
      expect(today!.id, 'c1-lit-santali-words');
    });

    test(
        'lessonForToday uses the bundled catalogue when nothing is synced',
        () async {
      final Lesson? today = await repository().lessonForToday(
        fakes.testClassroom(),
        on: DateTime(2026, 8, 1),
      );
      // From MockLessons' Class 1 set (order 1 under the default sort path it
      // still comes from the local catalogue, not from a server fixture).
      expect(today, isNotNull);
      expect(today!.title, isNot('Counting in Santali'));
    });

    test('isAvailableOffline always reads the device download state', () async {
      await store.saveLessons(<Lesson>[_syncedLesson()]);
      final PreferredSyncedLessonRepository repo = repository();

      // c1-num-counting-1-10 is marked downloaded on this device.
      expect(await repo.isAvailableOffline('c1-num-counting-1-10'), isTrue);
      // A synced-only lesson has no local pack yet.
      expect(await repo.isAvailableOffline('c1-num-colors'), isFalse);
    });
  });

  group('the lesson library renders through the composed repository', () {
    Future<void> pumpLibrary(
      WidgetTester tester,
      LessonRepository lessons, {
      ConnectionStatus online = ConnectionStatus.online,
    }) async {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(430, 2600);
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: LessonLibraryScreen(
            lessons: lessons,
            progress: fakes.FakeProgressRepository(),
            downloads: fakes.FakeDownloadRepository(),
            downloader: fakes.FakeDownloadService(),
            recommendations: const RuleBasedRecommendationRepository(),
            classrooms: setup_doubles.TestRepository(
              existing: fakes.testClassroom(),
            ),
            resources: const StaticOfflineResourceManager(
              OfflineResourceStatus(readiness: OfflineReadiness.ready),
            ),
            connectivityService: StaticConnectivityService(online),
            teacherId: fakes.kTeacherId,
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('synced catalogue is listed when a pull has cached it',
        (WidgetTester tester) async {
      await store.saveLessons(<Lesson>[_syncedLesson()]);
      final LessonRepository lessons = repository();

      await pumpLibrary(tester, lessons);

      expect(find.text('Colors Around Us'), findsWidgets);
      // The bundled-only lesson is not shown while the synced catalogue wins.
      expect(find.text('Swar: A, AA, I'), findsNothing);
    });

    testWidgets('an empty synced catalogue keeps the local lessons listed',
        (WidgetTester tester) async {
      await store.saveLessons(const <Lesson>[]);

      await pumpLibrary(tester, repository());

      expect(find.text('Counting 1–10'), findsWidgets);
    });

    testWidgets(
        'after a successful sync, going offline still lists the synced '
        'lessons (no network involved)', (WidgetTester tester) async {
      await store.saveLessons(<Lesson>[_syncedLesson()]);

      await pumpLibrary(
        tester,
        repository(),
        online: ConnectionStatus.offline,
      );

      expect(find.text('Colors Around Us'), findsWidgets);
    });
  });
}