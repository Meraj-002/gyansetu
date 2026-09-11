import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gyan_setu_ai/app/routes.dart';
import 'package:gyan_setu_ai/app/theme.dart';
import 'package:gyan_setu_ai/core/widgets/app_bottom_navigation.dart';
import 'package:gyan_setu_ai/features/auth/services/auth_session_store.dart';
import 'package:gyan_setu_ai/features/setup/models/classroom_setup.dart';
import 'package:gyan_setu_ai/features/setup/models/offline_resource_status.dart';
import 'package:gyan_setu_ai/features/setup/services/classroom_setup_repository.dart';
import 'package:gyan_setu_ai/features/setup/services/offline_resource_manager.dart';
import 'package:gyan_setu_ai/features/sync/sync_center_screen.dart';
import 'package:gyan_setu_ai/services/connectivity/connectivity_service.dart';
import 'package:gyan_setu_ai/services/storage/secure_storage_service.dart';
import 'package:gyan_setu_ai/services/sync/local_sync_service.dart';
import 'package:gyan_setu_ai/services/sync/sync_metadata_store.dart';
import 'package:gyan_setu_ai/services/sync/sync_service.dart';

import '../setup/setup_test_doubles.dart' as setup_doubles;

/// Short phase delay so each sync state is observable without slowing the
/// suite. Fast enough that `pumpAndSettle` runs a whole sync to completion.
const Duration _stepDelay = Duration(milliseconds: 50);

/// Every pack required by the sample classroom, present on the device.
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

/// A completed setup keyed for the local-teacher fallback the screen uses when
/// the session store reports no account.
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

void main() {
  late setup_doubles.TestRepository classrooms;

  setUp(() {
    classrooms = setup_doubles.TestRepository(existing: localTeacherClassroom());
  });

  (InMemorySecureStorageService, AuthSessionStore, SyncMetadataStore) wiring() {
    final InMemorySecureStorageService storage =
        InMemorySecureStorageService();
    return (
      storage,
      AuthSessionStore(storage),
      LocalSyncMetadataStore(storage),
    );
  }

  Widget harness({
    ConnectivityService? connectivity,
    SyncService? syncService,
    SyncMetadataStore? syncMetadata,
    AuthSessionStore? session,
    ClassroomSetupRepository? classroomRepo,
    OfflineResourceManager? resources,
  }) {
    return MaterialApp(
      theme: AppTheme.light,
      onGenerateRoute: AppRouter.onGenerateRoute,
      home: SyncCenterScreen(
        connectivityService:
            connectivity ?? StaticConnectivityService(ConnectionStatus.online),
        syncService:
            syncService ?? DevSyncService(metadata: syncMetadata!),
        syncMetadata: syncMetadata,
        session: session,
        classrooms: classroomRepo ?? classrooms,
        resources: resources ?? const BundledOfflineResourceManager(),
      ),
    );
  }

  Future<void> open(
    WidgetTester tester, {
    Size? size,
    ConnectivityService? connectivity,
    SyncService? syncService,
    SyncMetadataStore? syncMetadata,
    AuthSessionStore? session,
    ClassroomSetupRepository? classroomRepo,
    OfflineResourceManager? resources,
  }) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = size ?? const Size(430, 2400);
    addTearDown(tester.view.reset);

    if (syncMetadata == null) {
      final (InMemorySecureStorageService storage, AuthSessionStore s,
          SyncMetadataStore m) = wiring();
      session = session ?? s;
      syncMetadata = m;
      syncService =
          syncService ?? DevSyncService(metadata: m, stepDelay: _stepDelay);
    }

    await tester.pumpWidget(
      harness(
        connectivity: connectivity,
        syncService: syncService,
        syncMetadata: syncMetadata,
        session: session,
        classroomRepo: classroomRepo,
        resources: resources,
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

  testWidgets('renders title, subtitle, status card, Sync Now and sections',
      (WidgetTester tester) async {
    await open(tester);

    expect(find.text('Content Sync'), findsOneWidget);
    expect(
      find.text('Keep your classroom content up to date.'),
      findsOneWidget,
    );
    expect(find.text('Current Status'), findsOneWidget);
    expect(find.text('Sync Now'), findsOneWidget);
    expect(find.text('What Gets Synced'), findsOneWidget);
    expect(find.text('Curriculum'), findsOneWidget);
    expect(find.text('Santali Language Pack'), findsOneWidget);
    expect(find.text('Audio Resources'), findsOneWidget);
    expect(find.text('Worksheets'), findsOneWidget);
    expect(find.text('AI Vocabulary'), findsOneWidget);
    expect(find.text('Models'), findsOneWidget);
    expect(find.text('Data-friendly sync'), findsOneWidget);
    expect(tester.takeException(), isNull);

    final AppBottomNavigation nav =
        tester.widget<AppBottomNavigation>(find.byType(AppBottomNavigation));
    expect(nav.current, AppDestination.offline);
  });

  testWidgets('shows the online pill when connected', (WidgetTester tester) async {
    await open(tester);

    expect(find.text('Online'), findsOneWidget);
    expect(find.text('No internet connection'), findsNothing);
  });

  testWidgets('offline shows offline mode, banner and keeps resources message',
      (WidgetTester tester) async {
    await open(
      tester,
      connectivity: StaticConnectivityService(ConnectionStatus.offline),
    );

    expect(find.text('Offline Mode'), findsOneWidget);
    expect(find.text('No internet connection'), findsOneWidget);
    expect(
      find.text('Your downloaded classroom resources remain available.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('offline Sync Now refuses and never claims a run',
      (WidgetTester tester) async {
    await open(
      tester,
      connectivity: StaticConnectivityService(ConnectionStatus.offline),
    );

    await tapText(tester, 'Sync Now');
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('No internet connection.'), findsOneWidget);
    expect(find.text('Checking for updates…'), findsNothing);
    expect(find.text('Not synced yet'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('online Sync Now walks checking, uploading, downloading, done',
      (WidgetTester tester) async {
    await open(tester);

    await tester.tap(find.text('Sync Now'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));

    expect(find.text('Checking for updates…'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 60));
    expect(find.text('Uploading local changes…'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 60));
    expect(find.text('Downloading updates…'), findsOneWidget);

    await tester.pumpAndSettle();
    expect(find.text('Sync completed'), findsOneWidget);
    expect(find.text('Never'), findsNothing);
    expect(find.textContaining('Today, '), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a failed run shows Sync failed, then a retry completes',
      (WidgetTester tester) async {
    final (_, AuthSessionStore session, SyncMetadataStore metadata) = wiring();
    final DevSyncService failing = DevSyncService(
      metadata: metadata,
      stepDelay: _stepDelay,
      failTimes: 1,
    );
    await open(
      tester,
      syncService: failing,
      session: session,
      syncMetadata: metadata,
    );

    await tester.tap(find.text('Sync Now'));
    await tester.pump();
    await tester.pump(_stepDelay + const Duration(milliseconds: 20));

    expect(find.text('Sync failed'), findsOneWidget);
    expect(
      find.text('Could not reach the sync server.'),
      findsWidgets,
    );

    await tester.tap(find.text('Sync Now'));
    await tester.pumpAndSettle();

    expect(find.text('Sync failed'), findsNothing);
    expect(find.text('Sync completed'), findsOneWidget);
    expect(find.textContaining('Today, '), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('restores the last-synced timestamp from local persistence',
      (WidgetTester tester) async {
    final (InMemorySecureStorageService storage, AuthSessionStore session,
        SyncMetadataStore metadata) = wiring();
    final DateTime lastTime = DateTime.now()
        .subtract(const Duration(days: 10))
        .copyWith(hour: 9, minute: 42, second: 0, millisecond: 0);
    await storage.write(
      'sync.last_synced_at',
      lastTime.toIso8601String(),
    );

    await open(
      tester,
      session: session,
      syncMetadata: metadata,
    );

    expect(find.textContaining('9:42 AM'), findsOneWidget);
    expect(find.text('Never'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a build with no packs reports need-update honestly, never fake',
      (WidgetTester tester) async {
    await open(tester);

    expect(find.text('Needs update'), findsWidgets);
    expect(find.text('Up to date'), findsNothing);
    // AI Vocabulary has no probe yet: the UI says so instead of inventing a
    // state.
    expect(find.text('Unavailable offline'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('ready resource packs are reported Up to date per category',
      (WidgetTester tester) async {
    await open(
      tester,
      resources: const StaticOfflineResourceManager(kReadyResources),
    );

    expect(find.text('Up to date'), findsNWidgets(5));
    expect(find.text('Needs update'), findsNothing);
    // Only the probe-less AI Vocabulary keeps its honest placeholder.
    expect(find.text('Unavailable offline'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a category opens the resource detail sheet with real values',
      (WidgetTester tester) async {
    await open(tester);

    await tapText(tester, 'Santali Language Pack');

    expect(find.text('Status'), findsOneWidget);
    expect(find.text('Offline'), findsOneWidget);
    expect(find.text('Local size'), findsOneWidget);
    expect(find.text('Last updated'), findsOneWidget);
    expect(find.text('Not available offline'), findsWidgets);
    // Local size and last-updated are genuinely unknown until a backend
    // reports them.
    expect(find.text('Information unavailable'), findsNWidgets(2));
    // Offered the action the state calls for while online.
    expect(find.text('Sync Now'), findsNWidgets(2));
    expect(tester.takeException(), isNull);

    await tester.drag(find.byType(BottomSheet), const Offset(0, 300));
    await tester.pumpAndSettle();
  });

  testWidgets('back button pops the pushed sync screen', (WidgetTester tester) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(430, 2400);
    addTearDown(tester.view.reset);

    final (_, AuthSessionStore session, SyncMetadataStore metadata) = wiring();

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        builder: (BuildContext context, Widget? child) =>
            Scaffold(body: child),
        home: Builder(
          builder: (BuildContext context) => Center(
            child: TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (BuildContext context) => SyncCenterScreen(
                    connectivityService:
                        StaticConnectivityService(ConnectionStatus.online),
                    syncService:
                        DevSyncService(metadata: metadata, stepDelay: _stepDelay),
                    syncMetadata: metadata,
                    session: session,
                    classrooms: classrooms,
                    resources: const BundledOfflineResourceManager(),
                  ),
                ),
              ),
              child: const Text('go'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    expect(find.text('Content Sync'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.arrow_back_rounded));
    await tester.pumpAndSettle();
    expect(find.text('Content Sync'), findsNothing);
    expect(find.text('go'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('bottom navigation leaves the sync screen for Home',
      (WidgetTester tester) async {
    await open(tester);

    await tester.tap(
      find.descendant(
        of: find.byType(AppBottomNavigation),
        matching: find.text('Home'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(SyncCenterScreen), findsNothing);
  });

  testWidgets('lays out without overflow on common phone widths',
      (WidgetTester tester) async {
    for (final double width in <double>[360, 375, 390, 412]) {
      await open(tester, size: Size(width, 2600));
      await tester.drag(find.byType(ListView), const Offset(0, -3000));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'width $width overflowed');
    }
  });

  testWidgets('lays out without overflow on a wide tablet surface',
      (WidgetTester tester) async {
    await open(tester, size: const Size(900, 1600));

    await tester.drag(find.byType(ListView), const Offset(0, -2000));
    await tester.pumpAndSettle();

    expect(find.text('Data-friendly sync'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}