import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gyan_setu_ai/app/app_settings.dart';
import 'package:gyan_setu_ai/app/routes.dart';
import 'package:gyan_setu_ai/app/theme.dart';
import 'package:gyan_setu_ai/core/widgets/app_bottom_navigation.dart';
import 'package:gyan_setu_ai/features/home/home_screen.dart';
import 'package:gyan_setu_ai/features/home/models/home_dashboard.dart';
import 'package:gyan_setu_ai/features/home/services/home_controller.dart';
import 'package:gyan_setu_ai/features/progress/progress_screen.dart';
import 'package:gyan_setu_ai/features/setup/models/classroom_setup.dart';
import 'package:gyan_setu_ai/features/setup/setup_screen.dart';
import 'package:gyan_setu_ai/services/connectivity/connectivity_service.dart';
import 'package:provider/provider.dart';

import 'home_test_doubles.dart';

void main() {
  late FakeHomeRepository repository;
  late FakeLessonRepository lessons;
  late FakeHomeAudioService audio;
  late StaticConnectivityService connectivity;
  DateTime clockValue = DateTime(2026, 8, 29, 9);

  setUp(() {
    repository = FakeHomeRepository();
    lessons = FakeLessonRepository();
    audio = FakeHomeAudioService();
    connectivity = StaticConnectivityService(ConnectionStatus.online);
    clockValue = DateTime(2026, 8, 29, 9);
  });

  Widget harness() => ChangeNotifierProvider<AppSettings>(
    create: (_) => AppSettings(),
    child: MaterialApp(
      theme: AppTheme.light,
      onGenerateRoute: AppRouter.onGenerateRoute,
      home: HomeScreen(
        repository: repository,
        lessons: lessons,
        audio: audio,
        connectivityService: connectivity,
        clock: () => clockValue,
      ),
    ),
  );

  Future<void> open(WidgetTester tester, {Size? size}) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = size ?? const Size(430, 2400);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();
  }

  /// RefreshIndicator needs the fling plus explicit timed pumps: its arm and
  /// settle animations do not complete on pumpAndSettle alone.
  Future<void> pullToRefresh(WidgetTester tester) async {
    await tester.fling(find.byType(ListView), const Offset(0, 400), 1000);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
  }

  Future<void> tapText(WidgetTester tester, String label) async {
    await tester.ensureVisible(find.text(label).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text(label).first);
    await tester.pumpAndSettle();
  }

  group('greeting', () {
    test('follows the device clock', () {
      expect(DayPart.at(DateTime(2026, 1, 1, 6)), DayPart.morning);
      expect(DayPart.at(DateTime(2026, 1, 1, 11, 59)), DayPart.morning);
      expect(DayPart.at(DateTime(2026, 1, 1, 12)), DayPart.afternoon);
      expect(DayPart.at(DateTime(2026, 1, 1, 16, 59)), DayPart.afternoon);
      expect(DayPart.at(DateTime(2026, 1, 1, 17)), DayPart.evening);
      expect(DayPart.at(DateTime(2026, 1, 1, 23)), DayPart.evening);
    });

    testWidgets('uses the signed-in name and the time of day', (
      WidgetTester tester,
    ) async {
      await open(tester);
      expect(find.textContaining('Good Morning, Meraj'), findsOneWidget);
    });

    testWidgets('falls back to Teacher when no name is stored', (
      WidgetTester tester,
    ) async {
      repository.teacherName = null;
      clockValue = DateTime(2026, 8, 29, 19);
      await open(tester);
      expect(find.textContaining('Good Evening, Teacher'), findsOneWidget);
    });
  });

  testWidgets('renders the reference structure with GyanSetu branding', (
    WidgetTester tester,
  ) async {
    await open(tester);

    expect(find.textContaining('GyanSetu'), findsWidgets);
    expect(find.textContaining('BhashaSetu'), findsNothing);
    expect(find.text('Bridging Languages. Building Futures.'), findsOneWidget);
    expect(find.text("Let's make today's lesson easier."), findsOneWidget);
    expect(find.text("TODAY'S LESSON"), findsOneWidget);
    expect(find.text('Quick Actions'), findsOneWidget);
    expect(find.text('View all'), findsOneWidget);
    expect(find.text("Today's Progress"), findsOneWidget);
    expect(find.textContaining('AI-Powered'), findsOneWidget);
  });

  testWidgets('classroom strip shows the saved class and target language', (
    WidgetTester tester,
  ) async {
    repository.classroom = testClassroom(
      classLevel: 4,
      target: TargetLanguage.mundari,
    );
    await open(tester);

    expect(find.textContaining('Class 4'), findsWidgets);
    expect(find.textContaining('Mundari'), findsWidgets);
    expect(find.textContaining('Class 1  •  Santali'), findsNothing);
  });

  testWidgets('missing classroom shows the setup prompt, not fake data', (
    WidgetTester tester,
  ) async {
    repository.classroom = null;
    await open(tester);

    expect(find.text('Complete your classroom setup'), findsOneWidget);
    expect(find.text('Set Up Classroom'), findsOneWidget);
    expect(find.text("TODAY'S LESSON"), findsNothing);
    expect(find.text("Today's Progress"), findsNothing);

    await tapText(tester, 'Set Up Classroom');
    expect(find.byType(SetupScreen), findsOneWidget);
  });

  group("today's lesson", () {
    testWidgets('shows the lesson from the repository', (
      WidgetTester tester,
    ) async {
      await open(tester);
      expect(find.text('Counting 1–10'), findsOneWidget);
      expect(
        find.text('Child can count objects from 1 to 10.'),
        findsOneWidget,
      );
    });

    testWidgets('shows an empty state when nothing is planned', (
      WidgetTester tester,
    ) async {
      repository.lesson = null;
      await open(tester);

      expect(find.text('No lesson planned for today'), findsOneWidget);
      expect(find.text('Choose a lesson'), findsOneWidget);
      expect(find.text('Start Lesson'), findsNothing);
    });

    testWidgets('Start Lesson refuses to open content that is not on device', (
      WidgetTester tester,
    ) async {
      lessons.availableOffline = false;
      await open(tester);

      await tapText(tester, 'Start Lesson');

      expect(lessons.availabilityChecks, 1);
      expect(find.textContaining('not on your device yet'), findsOneWidget);
      expect(find.byType(HomeScreen), findsOneWidget);
    });

    testWidgets('Start Lesson opens the lesson when it is available', (
      WidgetTester tester,
    ) async {
      lessons.availableOffline = true;
      await open(tester);

      await tapText(tester, 'Start Lesson');

      expect(find.text('Lesson'), findsWidgets);
    });
  });

  group('listen', () {
    testWidgets('names the classroom target language', (
      WidgetTester tester,
    ) async {
      repository.classroom = testClassroom(target: TargetLanguage.ho);
      await open(tester);
      expect(find.text('Listen in Ho'), findsOneWidget);
    });

    testWidgets('says so when no audio exists rather than faking playback', (
      WidgetTester tester,
    ) async {
      await open(tester);

      await tapText(tester, 'Listen in Santali');

      expect(audio.playCalls, 1);
      expect(find.textContaining('not on this device yet'), findsOneWidget);
      expect(find.text('No audio yet'), findsOneWidget);
    });

    testWidgets('plays and stops when audio is available', (
      WidgetTester tester,
    ) async {
      audio.available = true;
      await open(tester);

      await tapText(tester, 'Listen in Santali');
      expect(find.text('Stop'), findsOneWidget);

      await tapText(tester, 'Stop');
      expect(find.text('Listen in Santali'), findsOneWidget);
      expect(audio.stopCalls, greaterThanOrEqualTo(1));
    });
  });

  group('quick actions', () {
    testWidgets('Translate names the classroom language pair', (
      WidgetTester tester,
    ) async {
      repository.classroom = testClassroom(
        medium: TeachingMedium.english,
        target: TargetLanguage.mundari,
      );
      await open(tester);
      expect(find.text('English ↔ Mundari'), findsOneWidget);
    });

    for (final (String label, String destination) in <(String, String)>[
      ('Assessment', 'Quick Assessment'),
      ('Translate', 'Translate'),
    ]) {
      testWidgets('$label opens $destination', (WidgetTester tester) async {
        await open(tester);
        await tapText(tester, label);
        expect(find.text(destination), findsWidgets);
      });
    }

    testWidgets('Flashcards opens the deck for the lesson', (
      WidgetTester tester,
    ) async {
      await open(tester);
      await tapText(tester, 'Flashcards');

      // The deck opens with the lesson, so cards belonging to it come first
      // and can be added to it.
      expect(find.text('Visual Flashcards'), findsOneWidget);
    });

    testWidgets('Create Worksheet opens the generator for the lesson', (
      WidgetTester tester,
    ) async {
      await open(tester);
      await tapText(tester, 'Create Worksheet');

      // The generator is opened with the lesson, not empty: without one it
      // would have nothing to align a worksheet to.
      expect(find.text('Create Worksheet'), findsWidgets);
      expect(find.text('No lesson was chosen.'), findsNothing);
    });

    testWidgets('View all opens the flashcards section', (
      WidgetTester tester,
    ) async {
      await open(tester);
      await tapText(tester, 'View all');
      expect(find.text('Visual Flashcards'), findsWidgets);
    });
  });

  group('progress', () {
    testWidgets('shows the values the repository supplies', (
      WidgetTester tester,
    ) async {
      await open(tester);

      expect(find.text('2/3'), findsOneWidget);
      expect(find.text('24'), findsOneWidget);
      expect(find.text('78%'), findsOneWidget);
    });

    test('lesson fraction is derived, not stored', () {
      expect(
        const LearningProgress(
          lessonsCompleted: 2,
          lessonsPlanned: 3,
          studentsEngaged: 0,
          assessmentPercent: null,
        ).lessonFraction,
        closeTo(2 / 3, 0.001),
      );
      expect(const LearningProgress.empty().lessonFraction, 0);
      expect(const LearningProgress.empty().hasData, isFalse);
    });

    testWidgets('empty progress explains itself instead of showing zeros', (
      WidgetTester tester,
    ) async {
      repository.progress = const LearningProgress.empty();
      await open(tester);

      expect(find.text('Nothing recorded yet today.'), findsOneWidget);
      expect(find.text('2/3'), findsNothing);
    });

    testWidgets('View detailed report opens Learning Insights', (
      WidgetTester tester,
    ) async {
      await open(tester);
      await tapText(tester, 'View detailed report');

      // The screen itself, not its title: reading the signed-in teacher goes
      // through secure storage, which no test binding answers, so the screen
      // is still calculating when this assertion runs.
      expect(find.byType(ProgressScreen), findsOneWidget);
      expect(find.byKey(ProgressScreen.skeletonKey), findsOneWidget);
    });
  });

  group('offline state', () {
    testWidgets('claims Offline Ready only when resources are present', (
      WidgetTester tester,
    ) async {
      await open(tester);
      expect(find.text('Offline Ready'), findsOneWidget);
      expect(find.text('Offline Mode Ready'), findsOneWidget);
    });

    testWidgets('reports partial stock honestly', (WidgetTester tester) async {
      repository.offlineState = HomeOfflineState.partial;
      await open(tester);

      expect(find.text('Offline Ready'), findsNothing);
      expect(find.text('Offline setup incomplete'), findsWidgets);
      expect(
        find.text('Some classroom resources still need to be prepared.'),
        findsOneWidget,
      );
    });

    testWidgets('offers sync when online and content is missing', (
      WidgetTester tester,
    ) async {
      repository.offlineState = HomeOfflineState.onlineSyncAvailable;
      await open(tester);
      expect(find.text('Sync available'), findsWidgets);
    });

    testWidgets('Manage Offline Content opens the offline centre', (
      WidgetTester tester,
    ) async {
      await open(tester);
      await tapText(tester, 'Manage Offline Content');
      expect(find.text('Offline Center'), findsWidgets);
    });
  });

  group('header actions', () {
    testWidgets('the bell shows unread count and opens notifications', (
      WidgetTester tester,
    ) async {
      repository.unread = 3;
      await open(tester);

      expect(find.text('3'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.notifications_none_rounded));
      await tester.pumpAndSettle();
      expect(find.text('Notifications'), findsWidgets);
    });

    testWidgets('no badge when nothing is unread', (WidgetTester tester) async {
      await open(tester);
      expect(find.byIcon(Icons.notifications_none_rounded), findsOneWidget);
      expect(find.text('0'), findsNothing);
    });

    testWidgets('the avatar opens Profile', (WidgetTester tester) async {
      await open(tester);
      await tester.tap(find.byIcon(Icons.person));
      // Bounded pumps: Profile runs a live connectivity service whose
      // "checking connection" banner carries an indefinite spinner, so
      // pumpAndSettle would time out.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('Profile'), findsWidgets);
    });
  });

  group('bottom navigation', () {
    testWidgets('Home is the selected destination and styled in gold', (
      WidgetTester tester,
    ) async {
      await open(tester);

      final AppBottomNavigation nav = tester.widget<AppBottomNavigation>(
        find.byType(AppBottomNavigation),
      );
      expect(nav.current, AppDestination.home);

      // The selected label takes the warm gold accent; the others do not.
      final Text homeLabel = tester.widget<Text>(
        find.descendant(
          of: find.byType(AppBottomNavigation),
          matching: find.text('Home'),
        ),
      );
      expect(homeLabel.style?.color, const Color(0xFFE9A227));

      final Text lessonsLabel = tester.widget<Text>(
        find.descendant(
          of: find.byType(AppBottomNavigation),
          matching: find.text('Lessons'),
        ),
      );
      expect(lessonsLabel.style?.color, isNot(const Color(0xFFE9A227)));
    });

    for (final (String label, String destination) in <(String, String)>[
      ('Lessons', 'Lessons'),
      ('Offline', 'Offline Center'),
      ('Flashcards', 'Visual Flashcards'),
      ('Profile', 'Profile'),
    ]) {
      testWidgets('$label navigates away from Home', (
        WidgetTester tester,
      ) async {
        await open(tester);

        await tester.tap(
          find.descendant(
            of: find.byType(AppBottomNavigation),
            matching: find.text(label),
          ),
        );
        if (label == 'Profile') {
          // Profile's live connectivity banner spins indefinitely while
          // checking, so bounded pumps instead of pumpAndSettle; extra time
          // lets the pushed route finish its transition and drop HomeScreen.
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 300));
          await tester.pump(const Duration(milliseconds: 300));
          await tester.pump(const Duration(milliseconds: 300));
        } else {
          await tester.pumpAndSettle();
        }

        expect(find.byType(HomeScreen), findsNothing);
        expect(find.text(destination), findsWidgets);
      });
    }

    testWidgets('tapping Home again stays put', (WidgetTester tester) async {
      await open(tester);
      await tester.tap(
        find.descendant(
          of: find.byType(AppBottomNavigation),
          matching: find.text('Home'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(HomeScreen), findsOneWidget);
    });
  });

  group('loading, refresh and errors', () {
    testWidgets('shows a skeleton before the first read completes', (
      WidgetTester tester,
    ) async {
      repository.latency = const Duration(milliseconds: 300);
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(430, 2400);
      addTearDown(tester.view.reset);

      await tester.pumpWidget(harness());
      await tester.pump();

      expect(find.byKey(HomeScreen.skeletonKey), findsOneWidget);

      // pumpAndSettle does not advance a pending timer on its own.
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      expect(find.byKey(HomeScreen.skeletonKey), findsNothing);
    });

    testWidgets('pull to refresh re-reads local data', (
      WidgetTester tester,
    ) async {
      // A realistic phone viewport: the tall one the other tests use leaves
      // the list unscrolled, and the gesture never becomes an overscroll.
      await open(tester, size: const Size(430, 900));
      expect(repository.loadCalls, 1);

      await pullToRefresh(tester);

      expect(repository.loadCalls, 2);
    });

    testWidgets('refreshing offline says so', (WidgetTester tester) async {
      connectivity = StaticConnectivityService(ConnectionStatus.offline);
      await open(tester, size: const Size(430, 900));

      await pullToRefresh(tester);

      expect(
        find.textContaining('latest saved classroom data'),
        findsOneWidget,
      );
    });

    testWidgets('a failed load offers a retry and hides no exception', (
      WidgetTester tester,
    ) async {
      repository.throwOnLoad = true;
      await open(tester);

      expect(
        find.text("Some dashboard information couldn't be loaded."),
        findsOneWidget,
      );
      expect(find.textContaining('StateError'), findsNothing);

      repository.throwOnLoad = false;
      await tapText(tester, 'Try Again');
      expect(find.textContaining('Good Morning'), findsOneWidget);
    });
  });

  testWidgets('lays out on a small handset without overflow', (
    WidgetTester tester,
  ) async {
    await open(tester, size: const Size(320, 2600));
    expect(tester.takeException(), isNull);
    expect(find.textContaining('Good Morning'), findsOneWidget);
  });
}
