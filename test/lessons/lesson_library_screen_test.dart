import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gyan_setu_ai/app/routes.dart';
import 'package:gyan_setu_ai/app/theme.dart';
import 'package:gyan_setu_ai/core/widgets/app_bottom_navigation.dart';
import 'package:gyan_setu_ai/features/lessons/lesson_detail_screen.dart';
import 'package:gyan_setu_ai/features/lessons/lesson_library_screen.dart';
import 'package:gyan_setu_ai/features/lessons/widgets/lesson_cards.dart';
import 'package:gyan_setu_ai/features/lessons/services/lesson_download_service.dart';
import 'package:gyan_setu_ai/features/lessons/services/recommendation_repository.dart';
import 'package:gyan_setu_ai/features/setup/models/classroom_setup.dart';
import 'package:gyan_setu_ai/features/setup/models/offline_resource_status.dart';
import 'package:gyan_setu_ai/features/setup/services/offline_resource_manager.dart';
import 'package:gyan_setu_ai/models/lesson.dart';
import 'package:gyan_setu_ai/services/connectivity/connectivity_service.dart';

import '../setup/setup_test_doubles.dart' as setup_doubles;
import 'lesson_test_doubles.dart';

void main() {
  late FakeLessonRepository lessons;
  late FakeProgressRepository progress;
  late FakeDownloadRepository downloads;
  late FakeDownloadService downloader;
  late setup_doubles.TestRepository classrooms;
  late StaticConnectivityService connectivity;

  setUp(() {
    lessons = FakeLessonRepository(
      catalogue: <Lesson>[
        testLesson(
          id: 'a',
          title: 'Counting 1–10',
          outcome: 'Count objects from 1 to 10.',
          minutes: 10,
          order: 1,
          daysOld: 0,
        ),
        testLesson(
          id: 'b',
          title: 'Swar: A, AA, I',
          subject: ClassroomSubject.foundationalLiteracy,
          outcome: 'Identify and read basic swar letters.',
          minutes: 12,
          order: 2,
          daysOld: 10,
        ),
        testLesson(
          id: 'c',
          title: 'Adding Within 10',
          classNumber: 2,
          outcome: 'Add two numbers.',
          minutes: 20,
          order: 3,
          daysOld: 20,
        ),
      ],
    );
    progress = FakeProgressRepository(<String, int>{'a': 80, 'b': 100});
    downloads = FakeDownloadRepository(<String>{'a', 'b'});
    downloader = FakeDownloadService(downloads: downloads);
    classrooms = setup_doubles.TestRepository(
      existing: _classroomSetup(),
    );
    connectivity = StaticConnectivityService(ConnectionStatus.online);
    lessons.offlineIds = <String>{'a', 'b'};
  });

  Widget harness() => MaterialApp(
        theme: AppTheme.light,
        onGenerateRoute: AppRouter.onGenerateRoute,
        home: LessonLibraryScreen(
          lessons: lessons,
          progress: progress,
          downloads: downloads,
          downloader: downloader,
          recommendations: const RuleBasedRecommendationRepository(),
          classrooms: classrooms,
          resources: const StaticOfflineResourceManager(
            OfflineResourceStatus(readiness: OfflineReadiness.ready),
          ),
          connectivityService: connectivity,
          teacherId: kTeacherId,
        ),
      );

  Future<void> open(WidgetTester tester, {Size? size}) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = size ?? const Size(430, 2600);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();
  }

  Future<void> tapText(WidgetTester tester, String label) async {
    await tester.ensureVisible(find.text(label).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text(label).first);
    await tester.pumpAndSettle();
  }

  /// Titles in the All Lessons list only. The recommendation carousel is
  /// ranked separately and is deliberately not narrowed by the filters.
  List<String> listTitles(WidgetTester tester) => tester
      .widgetList<LessonListCard>(find.byType(LessonListCard))
      .map((LessonListCard c) => c.card.lesson.title)
      .toList();

  List<DownloadState> listDownloads(WidgetTester tester) => tester
      .widgetList<LessonListCard>(find.byType(LessonListCard))
      .map((LessonListCard c) => c.card.download)
      .toList();

  Future<void> type(WidgetTester tester, String value) async {
    await tester.enterText(
      find.byKey(LessonLibraryScreen.searchFieldKey),
      value,
    );
    await tester.pumpAndSettle();
  }

  testWidgets('renders the reference structure with GyanSetu branding',
      (WidgetTester tester) async {
    await open(tester);

    expect(find.textContaining('GyanSetu'), findsWidgets);
    expect(find.textContaining('BhashaSetu'), findsNothing);
    expect(find.text('Lesson Library'), findsOneWidget);
    expect(
      find.text('Find and teach the right lesson, in the right language.'),
      findsOneWidget,
    );
    expect(find.text('Search lessons...'), findsOneWidget);
    expect(find.text('Filters (1)'), findsOneWidget);
    expect(find.text('Recommended for Today'), findsOneWidget);
    expect(find.text('View all'), findsOneWidget);
    expect(find.textContaining('Sort by:'), findsOneWidget);
    expect(find.text('Manage Downloads'), findsOneWidget);
  });

  testWidgets('defaults to the classroom class but stays changeable',
      (WidgetTester tester) async {
    await open(tester);

    expect(find.text('All Lessons (Class 1)'), findsOneWidget);
    expect(listTitles(tester), isNot(contains('Adding Within 10')));

    await tapText(tester, 'Class 1');
    await tapText(tester, 'Class 2');

    expect(find.text('All Lessons (Class 2)'), findsOneWidget);
    expect(listTitles(tester), <String>['Adding Within 10']);
  });

  testWidgets('the language pair comes from the classroom setup',
      (WidgetTester tester) async {
    classrooms = setup_doubles.TestRepository(
      existing: _classroomSetup(
        medium: TeachingMedium.english,
        target: TargetLanguage.mundari,
      ),
    );
    await open(tester);

    expect(find.textContaining('English → Mundari'), findsWidgets);
    expect(find.textContaining('Hindi → Santali'), findsNothing);
  });

  group('search', () {
    testWidgets('narrows the list while typing and can be cleared',
        (WidgetTester tester) async {
      await open(tester);

      await type(tester, 'count');
      expect(listTitles(tester), <String>['Counting 1–10']);

      await tester.tap(find.byTooltip('Clear search'));
      await tester.pumpAndSettle();
      expect(listTitles(tester), contains('Swar: A, AA, I'));
    });

    testWidgets('shows the empty state when nothing matches',
        (WidgetTester tester) async {
      await open(tester);
      await type(tester, 'astrophysics');

      expect(find.text('No lessons found'), findsOneWidget);
      expect(find.text('Try changing your search or filters.'), findsOneWidget);
      expect(find.text('Clear Search'), findsOneWidget);

      await tapText(tester, 'Clear Search');
      expect(find.text('No lessons found'), findsNothing);
    });
  });

  group('filter chips', () {
    testWidgets('Literacy and Numeracy toggle the subject',
        (WidgetTester tester) async {
      await open(tester);

      await tapText(tester, 'Literacy');
      expect(listTitles(tester), <String>['Swar: A, AA, I']);

      await tapText(tester, 'Literacy');
      expect(listTitles(tester), contains('Counting 1–10'));
    });

    testWidgets('Completed and Downloaded narrow by real state',
        (WidgetTester tester) async {
      await open(tester);

      await tapText(tester, 'Completed');
      // 'b' is the only 100% lesson.
      expect(listTitles(tester), <String>['Swar: A, AA, I']);

      await tapText(tester, 'Completed');
      await tapText(tester, 'Downloaded');
      expect(listTitles(tester), contains('Counting 1–10'));
    });
  });

  group('filter sheet', () {
    testWidgets('opens, counts active filters and clears them',
        (WidgetTester tester) async {
      await open(tester);

      // The class default already counts as one filter.
      expect(find.text('Filters (1)'), findsOneWidget);

      await tapText(tester, 'Filters (1)');
      expect(find.text('Clear All'), findsOneWidget);

      await tester.tap(find.text('Numeracy').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Clear All'));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('Show '));
      await tester.pumpAndSettle();

      expect(find.text('Filters'), findsOneWidget);
      expect(find.text('All Lessons'), findsOneWidget);
    });
  });

  testWidgets('sorting reorders the list', (WidgetTester tester) async {
    await open(tester);
    await tapText(tester, 'Class 1');
    await tapText(tester, 'All classes');

    await tapText(tester, 'Sort by: Newest');
    await tapText(tester, 'A–Z');
    await tester.pumpAndSettle();

    expect(find.text('Sort by: A–Z'), findsOneWidget);

    expect(listTitles(tester).first, 'Adding Within 10');
  });

  group('opening a lesson', () {
    testWidgets('Start opens lesson detail with the right lesson',
        (WidgetTester tester) async {
      await open(tester);

      await tapText(tester, 'Start Lesson');

      expect(find.byType(LessonLibraryScreen), findsNothing);
      expect(find.byType(LessonDetailScreen), findsOneWidget);
    });

    testWidgets('the action label follows progress',
        (WidgetTester tester) async {
      await open(tester);

      // 'a' is 80% and 'b' is 100%.
      expect(find.text('Continue'), findsWidgets);
      expect(find.text('Review'), findsWidgets);
    });

    testWidgets('a lesson that is not on the device explains itself',
        (WidgetTester tester) async {
      lessons.offlineIds = <String>{};
      downloads = FakeDownloadRepository(<String>{});
      downloader = FakeDownloadService(downloads: downloads);
      await open(tester);

      await tapText(tester, 'Start Lesson');

      expect(
        find.textContaining("isn't available offline yet"),
        findsOneWidget,
      );
      expect(find.text('Manage Downloads'), findsWidgets);
    });
  });

  group('downloads', () {
    testWidgets('offline first download is refused with an explanation',
        (WidgetTester tester) async {
      downloads = FakeDownloadRepository(<String>{});
      lessons.offlineIds = <String>{};
      downloader = FakeDownloadService(
        downloads: downloads,
        outcome: const DownloadRefused(
          DownloadRefusal.needsConnection,
          'This lesson needs an internet connection for the first download.',
        ),
      );
      connectivity = StaticConnectivityService(ConnectionStatus.offline);
      await open(tester);

      await tester.ensureVisible(find.text('Not downloaded').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Not downloaded').first);
      await tester.pumpAndSettle();

      expect(
        find.text('Internet needed for the first download'),
        findsOneWidget,
      );
      expect(find.text('Connect to Internet'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
    });

    testWidgets('a successful download flips the state',
        (WidgetTester tester) async {
      downloads = FakeDownloadRepository(<String>{});
      lessons.offlineIds = <String>{};
      downloader = FakeDownloadService(downloads: downloads);
      await open(tester);

      expect(listDownloads(tester), everyElement(DownloadState.notDownloaded));

      await tester.ensureVisible(find.text('Not downloaded').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Not downloaded').first);
      await tester.pumpAndSettle();

      expect(downloader.downloadCalls, 1);
      expect(listDownloads(tester), contains(DownloadState.downloaded));
    });

    testWidgets('a failure is reported without losing anything',
        (WidgetTester tester) async {
      downloads = FakeDownloadRepository(<String>{});
      lessons.offlineIds = <String>{};
      downloader = FakeDownloadService(
        downloads: downloads,
        outcome: const DownloadRefused(
          DownloadRefusal.failed,
          'Download failed. Try again.',
        ),
      );
      await open(tester);

      await tester.ensureVisible(find.text('Not downloaded').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Not downloaded').first);
      await tester.pumpAndSettle();

      expect(find.text('Download failed. Try again.'), findsOneWidget);
      expect(find.byType(LessonLibraryScreen), findsOneWidget);
    });
  });

  group('offline status', () {
    testWidgets('says Online when connected', (WidgetTester tester) async {
      await open(tester);
      expect(find.text('Online'), findsOneWidget);
    });

    testWidgets('claims Offline Ready only when everything is on the device',
        (WidgetTester tester) async {
      connectivity = StaticConnectivityService(ConnectionStatus.offline);
      downloads = FakeDownloadRepository(<String>{'a', 'b', 'c'});
      await open(tester);
      expect(find.text('Offline Ready'), findsOneWidget);
    });

    testWidgets('warns when some lessons are missing',
        (WidgetTester tester) async {
      connectivity = StaticConnectivityService(ConnectionStatus.offline);
      downloads = FakeDownloadRepository(<String>{'a'});
      await open(tester);
      expect(
        find.text('Offline — Some lessons unavailable'),
        findsOneWidget,
      );
    });
  });

  testWidgets('Manage Downloads opens the offline centre',
      (WidgetTester tester) async {
    await open(tester);
    await tapText(tester, 'Manage Downloads');
    expect(find.text('Offline Center'), findsWidgets);
  });

  group('shared navigation', () {
    testWidgets('Lessons is selected and styled in gold',
        (WidgetTester tester) async {
      await open(tester);

      final AppBottomNavigation nav =
          tester.widget<AppBottomNavigation>(find.byType(AppBottomNavigation));
      expect(nav.current, AppDestination.lessons);

      final Text label = tester.widget<Text>(
        find.descendant(
          of: find.byType(AppBottomNavigation),
          matching: find.text('Lessons'),
        ),
      );
      expect(label.style?.color, const Color(0xFFE9A227));
    });

    testWidgets('Home navigates back to the dashboard',
        (WidgetTester tester) async {
      await open(tester);

      await tester.tap(
        find.descendant(
          of: find.byType(AppBottomNavigation),
          matching: find.text('Home'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(LessonLibraryScreen), findsNothing);
    });
  });

  group('loading, refresh and errors', () {
    testWidgets('shows a skeleton before the catalogue arrives',
        (WidgetTester tester) async {
      lessons.latency = const Duration(milliseconds: 300);
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(430, 2600);
      addTearDown(tester.view.reset);

      await tester.pumpWidget(harness());
      await tester.pump();

      expect(find.byKey(LessonLibraryScreen.skeletonKey), findsOneWidget);

      // pumpAndSettle does not advance a pending timer on its own.
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      expect(find.byKey(LessonLibraryScreen.skeletonKey), findsNothing);
    });

    testWidgets('a failed load offers a retry and hides the exception',
        (WidgetTester tester) async {
      lessons.throwOnLessons = true;
      await open(tester);

      expect(find.text("Couldn't load lessons."), findsOneWidget);
      expect(find.textContaining('StateError'), findsNothing);

      lessons.throwOnLessons = false;
      await tapText(tester, 'Try Again');
      expect(find.text('Lesson Library'), findsOneWidget);
    });

    testWidgets('pull to refresh reloads and reports being offline',
        (WidgetTester tester) async {
      connectivity = StaticConnectivityService(ConnectionStatus.offline);
      await open(tester, size: const Size(430, 900));

      // From near the top: the ListView's centre sits inside the horizontal
      // recommendation carousel, which muddies the gesture.
      await tester.flingFrom(const Offset(200, 200), const Offset(0, 400), 1000);
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('lessons saved on this device'),
        findsOneWidget,
      );
    });
  });

  testWidgets('lays out on a small handset without overflow',
      (WidgetTester tester) async {
    await open(tester, size: const Size(320, 3000));
    expect(tester.takeException(), isNull);
    expect(find.text('Lesson Library'), findsOneWidget);
  });
}

ClassroomSetup _classroomSetup({
  int classLevel = 1,
  TeachingMedium medium = TeachingMedium.hindi,
  TargetLanguage target = TargetLanguage.santali,
}) =>
    ClassroomSetup(
      teacherId: kTeacherId,
      schoolName: 'Govt. Primary School, Jama',
      districtId: 'dumka',
      districtName: 'Dumka',
      blockId: 'dumka.jama',
      blockName: 'Jama',
      teachingMedium: medium,
      targetLanguage: target,
      classLevel: classLevel,
      subjects: const <ClassroomSubject>{
        ClassroomSubject.foundationalLiteracy,
        ClassroomSubject.numeracy,
      },
      setupCompleted: true,
    );
