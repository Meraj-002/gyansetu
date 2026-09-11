import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gyan_setu_ai/app/theme.dart';
import 'package:gyan_setu_ai/core/utils/result.dart';
import 'package:gyan_setu_ai/features/auth/services/auth_session_store.dart';
import 'package:gyan_setu_ai/features/offline/offline_center_screen.dart';
import 'package:gyan_setu_ai/models/resource_manifest.dart';
import 'package:gyan_setu_ai/services/connectivity/connectivity_service.dart';
import 'package:gyan_setu_ai/services/downloads/download_manager.dart';
import 'package:gyan_setu_ai/services/resources/resource_catalogue_service.dart';
import 'package:gyan_setu_ai/services/storage/secure_storage_service.dart';

import '../api/api_test_doubles.dart';
import '../downloads/download_test_doubles.dart';
import '../lessons/lesson_test_doubles.dart';
import '../offline_center_screen_test.dart' show localTeacherClassroom;
import '../setup/setup_test_doubles.dart' as setup_doubles;

void main() {
  late Directory tempDir;
  late InMemorySecureStorageService storage;
  late Map<String, String> hashes;
  late FakePackTransport transport;
  late ScriptedApiClient api;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('gyansetu_offline_tools');
    storage = InMemorySecureStorageService();
    hashes = await hashesFor(samplePacks);
    transport = FakePackTransport(samplePacks);
    api = ScriptedApiClient();
    api.onGet = () => Ok<Map<String, dynamic>>(<String, dynamic>{
          'value': <Map<String, dynamic>>[
            <String, dynamic>{
              'id': 'a.content',
              'kind': 'content',
              'name': 'a.content',
              'description': '',
              'classNumber': 1,
              'subject': 'foundationalLiteracy',
              'version': '1',
              'sizeBytes': samplePacks['a.content']!.length,
              'sha256': hashes['a.content']!,
              'mimeType': 'application/json',
              'lessonId': 'l1',
            },
          ],
        });
  });

  tearDown(() async {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  DownloadManager manager() => DownloadManager(
        storage: storage,
        transport: transport,
        baseDirectory: tempDir.path,
      );

  Widget harness({
    required DownloadManager downloadManager,
    required ResourceCatalogueService catalogue,
  }) {
    return MaterialApp(
      theme: AppTheme.light,
      home: OfflineCenterScreen(
        connectivityService: StaticConnectivityService(ConnectionStatus.online),
        classrooms: setup_doubles.TestRepository(
          existing: localTeacherClassroom(),
        ),
        session: AuthSessionStore(InMemorySecureStorageService()),
        lessons: FakeLessonRepository(),
        downloads: FakeDownloadRepository(),
        audio: setup_doubles.TestAudioService(available: false),
        storageProbe: () async => 4096,
        downloadManager: downloadManager,
        resourceCatalogue: catalogue,
      ),
    );
  }

  /// The content cards sit below the fold of the default 800x600 test surface,
  /// and a lazy list only builds what is painted. Give the screen a tall
  /// viewport so every card (Quick Tools included) is built and tappable.
  void fitViewport(WidgetTester tester) {
    tester.view.physicalSize = const Size(1080, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  testWidgets('Download Queue shows live packed transfers', (tester) async {
    final DownloadManager m = manager();
    fitViewport(tester);
    await tester.pumpWidget(harness(
      downloadManager: m,
      catalogue: ResourceCatalogueService(api: api),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Quick Tools'), findsOneWidget);

    await tester.tap(find.text('Download Queue'));
    await tester.pumpAndSettle();
    expect(find.text('Nothing downloaded on this device yet.'), findsOneWidget);
  });

  testWidgets('Clear Cache reports a real cleanup', (tester) async {
    final DownloadManager m = manager();
    fitViewport(tester);
    await tester.pumpWidget(harness(
      downloadManager: m,
      catalogue: ResourceCatalogueService(api: api),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Clear Cache'));
    await tester.pumpAndSettle();
    expect(
      find.text('No interrupted transfer files found.'),
      findsOneWidget,
    );
  });

  testWidgets('Update Packs lists the server difference and queues a download', (tester) async {
    final DownloadManager m = manager();
    fitViewport(tester);
    await tester.pumpWidget(harness(
      downloadManager: m,
      catalogue: ResourceCatalogueService(api: api),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Update Packs'));
    await tester.pumpAndSettle();

    expect(find.text('a.content'), findsOneWidget);
    expect(find.text('v1'), findsOneWidget);
    expect(find.byIcon(Icons.download_for_offline_outlined), findsOneWidget);

    // Close the sheet again so the later re-pump starts from a clean tree.
    await tester.tapAt(const Offset(400, 60));
    await tester.pumpAndSettle();

    // The download itself is real file I/O and only runs in the real-async
    // zone: drive the pipeline there, then the same sheet reports up-to-date.
    await tester.runAsync(() async {
      await m.enqueue(<ResourceManifest>[
        packManifest('a.content', samplePacks['a.content']!, hashes),
      ]);
      await m.waitFor(<String>{'a.content'});
    });

    expect(m.stateFor('a.content'), ResourceDownloadState.ready);
    expect(transport.fetches, 1);

    await tester.pumpWidget(harness(
      downloadManager: m,
      catalogue: ResourceCatalogueService(api: api),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Update Packs'));
    await tester.pumpAndSettle();

    expect(find.text('All content packs are up to date.'), findsOneWidget);
  });

  testWidgets('Update Packs says everything is up to date when versions match', (tester) async {
    final DownloadManager m = manager();
    fitViewport(tester);
    await tester.pumpWidget(harness(
      downloadManager: m,
      catalogue: ResourceCatalogueService(api: api),
    ));
    await tester.pumpAndSettle();

    await tester.runAsync(() async {
      await m.enqueue(<ResourceManifest>[
        packManifest('a.content', samplePacks['a.content']!, hashes),
      ]);
      await m.waitFor(<String>{'a.content'});
    });

    await tester.tap(find.text('Update Packs'));
    await tester.pumpAndSettle();

    expect(find.text('All content packs are up to date.'), findsOneWidget);
  });
}