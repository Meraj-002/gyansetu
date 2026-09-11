import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gyan_setu_ai/app/routes.dart';
import 'package:gyan_setu_ai/app/theme.dart';
import 'package:gyan_setu_ai/core/widgets/app_bottom_navigation.dart';
import 'package:gyan_setu_ai/features/auth/services/auth_session_store.dart';
import 'package:gyan_setu_ai/features/lessons/services/lesson_repository.dart';
import 'package:gyan_setu_ai/features/offline/offline_center_screen.dart';
import 'package:gyan_setu_ai/features/setup/models/classroom_setup.dart';
import 'package:gyan_setu_ai/features/setup/models/offline_resource_status.dart';
import 'package:gyan_setu_ai/features/setup/services/classroom_setup_repository.dart';
import 'package:gyan_setu_ai/features/setup/services/offline_resource_manager.dart';
import 'package:gyan_setu_ai/models/lesson.dart';
import 'package:gyan_setu_ai/services/audio/language_audio_service.dart';
import 'package:gyan_setu_ai/services/connectivity/connectivity_service.dart';
import 'package:gyan_setu_ai/services/storage/secure_storage_service.dart';

import 'lessons/lesson_test_doubles.dart';
import 'setup/setup_test_doubles.dart' as setup_doubles;

const OfflineResourceStatus kReadyResources = OfflineResourceStatus(
  readiness: OfflineReadiness.ready,
  resources: <OfflineResource>[
    OfflineResource(kind: OfflineResourceKind.curriculum, available: true),
    OfflineResource(kind: OfflineResourceKind.lessons, available: true),
    OfflineResource(kind: OfflineResourceKind.vocabulary, available: true),
    OfflineResource(kind: OfflineResourceKind.audio, available: true),
    OfflineResource(kind: OfflineResourceKind.worksheets, available: true),
    OfflineResource(kind: OfflineResourceKind.flashcards, available: true),
    OfflineResource(kind: OfflineResourceKind.assessments, available: true),
    OfflineResource(kind: OfflineResourceKind.languageModel, available: true),
  ],
  message: 'Everything this classroom needs is on this device.',
);

ClassroomSetup localTeacherClassroom() => ClassroomSetup(
      teacherId: 'local-teacher',
      schoolName: 'Govt. Primary School, Jama',
      districtId: 'dumka',
      districtName: 'Dumka',
      blockId: 'dumka.jama',
      blockName: 'Jama',
      teachingMedium: TeachingMedium.hindi,
      targetLanguage: TargetLanguage.santali,
      classLevel: 1,
      subjects: const <ClassroomSubject>{
        ClassroomSubject.foundationalLiteracy,
        ClassroomSubject.numeracy,
      },
      setupCompleted: true,
    );

class ThrowingResourceManager implements OfflineResourceManager {
  @override
  Future<OfflineResourceStatus> check(ResourceProfile profile) async =>
      throw StateError('resource check exploded');

  @override
  List<OfflineResourceKind> requiredFor(ResourceProfile profile) =>
      const <OfflineResourceKind>[];

  @override
  Future<OfflineResourceStatus> prepare(ResourceProfile profile) async =>
      throw StateError('prepare exploded');
}

void main() {
  late FakeLessonRepository lessons;
  late FakeDownloadRepository downloads;
  late setup_doubles.TestRepository classrooms;

  setUp(() {
    lessons = FakeLessonRepository(
      catalogue: <Lesson>[
        testLesson(id: 'a', title: 'Counting 1-10'),
        testLesson(
          id: 'b',
          title: 'Swar: A, AA, I',
          subject: ClassroomSubject.foundationalLiteracy,
        ),
      ],
    );
    downloads = FakeDownloadRepository(<String>{'a'});
    classrooms = setup_doubles.TestRepository(existing: localTeacherClassroom());
  });

  Widget harness({
    ConnectivityService? connectivity,
    OfflineResourceManager? resources,
    ClassroomSetupRepository? classroomRepo,
    AuthSessionStore? session,
    LessonRepository? lessonRepo,
    LessonDownloadRepository? downloadRepo,
    LanguageAudioService? audio,
    Future<int?> Function()? storageProbe,
  }) {
    return MaterialApp(
      theme: AppTheme.light,
      onGenerateRoute: AppRouter.onGenerateRoute,
      home: OfflineCenterScreen(
        connectivityService: connectivity ?? StaticConnectivityService(ConnectionStatus.online),
        resources: resources ?? const BundledOfflineResourceManager(),
        classrooms: classroomRepo ?? classrooms,
        session: session ?? AuthSessionStore(InMemorySecureStorageService()),
        lessons: lessonRepo ?? lessons,
        downloads: downloadRepo ?? downloads,
        audio: audio ?? setup_doubles.TestAudioService(available: false),
        storageProbe: storageProbe ?? () async => 4096,
      ),
    );
  }

  Future<void> open(
    WidgetTester tester, {
    Size? size,
    ConnectivityService? connectivity,
    OfflineResourceManager? resources,
    ClassroomSetupRepository? classroomRepo,
    AuthSessionStore? session,
    LessonRepository? lessonRepo,
    LessonDownloadRepository? downloadRepo,
    LanguageAudioService? audio,
    Future<int?> Function()? storageProbe,
  }) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = size ?? const Size(430, 2600);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      harness(
        connectivity: connectivity,
        resources: resources,
        classroomRepo: classroomRepo,
        session: session,
        lessonRepo: lessonRepo,
        downloadRepo: downloadRepo,
        audio: audio,
        storageProbe: storageProbe,
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> tapText(WidgetTester tester, String label) async {
    await tester.ensureVisible(find.text(label).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text(label).first);
    await tester.pumpAndSettle();
  }

  testWidgets('renders title, subtitle and every required section',
      (WidgetTester tester) async {
    await open(tester);

    expect(find.text('Offline Center'), findsOneWidget);
    expect(
      find.text('All your teaching resources, available offline.'),
      findsOneWidget,
    );
    expect(find.text('Downloaded Language Pack'), findsOneWidget);
    expect(find.text('Downloaded Lessons'), findsOneWidget);
    expect(find.text('Audio Library'), findsOneWidget);
    expect(find.text('AI Models'), findsOneWidget);
    expect(find.text('Device Storage'), findsOneWidget);
    expect(find.text('Manage Downloads'), findsOneWidget);
    expect(find.text('Test Offline Mode'), findsOneWidget);
    expect(find.text('Quick Tools'), findsOneWidget);
    expect(tester.takeException(), isNull);

    final AppBottomNavigation nav =
        tester.widget<AppBottomNavigation>(find.byType(AppBottomNavigation));
    expect(nav.current, AppDestination.offline);
  });

  testWidgets('shows the truthful connection pill when online',
      (WidgetTester tester) async {
    await open(
      tester,
      size: const Size(430, 2600),
    );
    expect(find.text('Online'), findsOneWidget);
  });

  testWidgets('shows Wi-Fi OFF pill when the device has no interface',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      harness(connectivity: StaticConnectivityService(ConnectionStatus.offline)),
    );
    await tester.pumpAndSettle();

    expect(find.text('Wi-Fi OFF'), findsOneWidget);
  });

  testWidgets('shows an honest message when storage cannot be measured',
      (WidgetTester tester) async {
    await open(tester, storageProbe: () async => null);

    expect(find.text('Unavailable on this platform'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('shows READY FOR OFFLINE TEACHING when everything is present',
      (WidgetTester tester) async {
    await open(
      tester,
      resources: const StaticOfflineResourceManager(kReadyResources),
      audio: setup_doubles.TestAudioService(available: true),
    );

    expect(find.text('READY FOR OFFLINE TEACHING'), findsOneWidget);
    expect(find.text('Offline AI ready'), findsOneWidget);
    expect(
      find.text('Downloaded Language Pack'),
      findsOneWidget,
    );
  });

  testWidgets('shows OFFLINE SETUP INCOMPLETE when the build ships no packs',
      (WidgetTester tester) async {
    await open(tester);

    expect(find.text('OFFLINE SETUP INCOMPLETE'), findsOneWidget);
    expect(find.text('Offline AI — not installed'), findsOneWidget);
  });

  testWidgets('Test Offline Mode reports READY for a fully stocked device',
      (WidgetTester tester) async {
    await open(
      tester,
      resources: const StaticOfflineResourceManager(kReadyResources),
      audio: setup_doubles.TestAudioService(available: true),
    );

    await tapText(tester, 'Test Offline Mode');

    expect(find.text('Offline Mode Check'), findsOneWidget);
    expect(find.text('Verdict: READY'), findsOneWidget);
  });

  testWidgets('Test Offline Mode reports INCOMPLETE when packs are missing',
      (WidgetTester tester) async {
    await open(tester);

    await tapText(tester, 'Test Offline Mode');

    expect(find.text('Offline Mode Check'), findsOneWidget);
    expect(find.text('Verdict: INCOMPLETE'), findsOneWidget);
  });

  testWidgets('Manage Downloads lists a lesson and removes it',
      (WidgetTester tester) async {
    await open(tester);

    await tapText(tester, 'Manage Downloads');

    expect(find.text('1 lesson entries are marked for offline use.'), findsOneWidget);
    expect(find.text('Counting 1-10'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pumpAndSettle();

    expect(find.text('Counting 1-10'), findsNothing);
    expect(find.text('Lesson removed from offline list.'), findsOneWidget);
    expect(await downloads.downloadedIds(), isEmpty);
  });

  testWidgets('bottom navigation navigates home', (WidgetTester tester) async {
    await open(tester);

    await tester.tap(
      find.descendant(
        of: find.byType(AppBottomNavigation),
        matching: find.text('Home'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(OfflineCenterScreen), findsNothing);
  });

  testWidgets('a failing resource check narrows to its own cards',
      (WidgetTester tester) async {
    await open(
      tester,
      resources: ThrowingResourceManager(),
    );

    expect(find.text('OFFLINE CHECK FAILED'), findsOneWidget);
    expect(find.text('Downloaded Lessons'), findsOneWidget);
    expect(find.text('Ready'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a failing lesson inventory isolates to the lessons card',
      (WidgetTester tester) async {
    lessons.throwOnLessons = true;

    await open(
      tester,
      resources: const StaticOfflineResourceManager(kReadyResources),
      lessonRepo: lessons,
    );

    expect(find.text('READY FOR OFFLINE TEACHING'), findsOneWidget);
    expect(find.text('Downloaded Lessons'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('lays out without overflow on a narrow phone',
      (WidgetTester tester) async {
    await open(tester, size: const Size(320, 2600));

    await tester.drag(find.byType(ListView), const Offset(0, -3000));
    await tester.pumpAndSettle();

    expect(find.text('Quick Tools'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('lays out without overflow on a two-column tablet surface',
      (WidgetTester tester) async {
    await open(
      tester,
      size: const Size(900, 1400),
      resources: const StaticOfflineResourceManager(kReadyResources),
      audio: setup_doubles.TestAudioService(available: true),
    );

    expect(find.text('READY FOR OFFLINE TEACHING'), findsOneWidget);
    expect(find.text('Downloaded Language Pack'), findsOneWidget);
    expect(find.text('Audio Library'), findsOneWidget);

    await tester.drag(find.byType(ListView), const Offset(0, -2000));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}