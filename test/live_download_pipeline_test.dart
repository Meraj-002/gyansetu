import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gyan_setu_ai/core/config/api_config.dart';
import 'package:gyan_setu_ai/core/utils/result.dart';
import 'package:gyan_setu_ai/features/lessons/services/lesson_download_service.dart';
import 'package:gyan_setu_ai/features/lessons/services/lesson_repository.dart';
import 'package:gyan_setu_ai/features/setup/models/classroom_setup.dart';
import 'package:gyan_setu_ai/models/lesson.dart';
import 'package:gyan_setu_ai/models/resource_manifest.dart';
import 'package:gyan_setu_ai/services/api/http_api_client.dart';
import 'package:gyan_setu_ai/services/connectivity/connectivity_service.dart';
import 'package:gyan_setu_ai/services/downloads/download_manager.dart';
import 'package:gyan_setu_ai/services/downloads/download_transport.dart';
import 'package:gyan_setu_ai/services/resources/resource_catalogue_service.dart';
import 'package:gyan_setu_ai/services/storage/secure_storage_service.dart';

/// End-to-end verification of the real content-pack pipeline against the
/// running FastAPI backend: the catalogue list endpoint, the streaming content
/// endpoint, byte-for-byte SHA-256 verification on disk, lesson marking, and
/// removal. Nothing is faked and no code path is stubbed.
///
/// Run it with uvicorn up on [ApiConfig.baseUrl]:
///
///     flutter test --dart-define=LIVE_BACKEND=true test/live_download_pipeline_test.dart
const bool live = bool.fromEnvironment('LIVE_BACKEND');

void main() {
  if (!live) {
    test(
      'live download pipeline is skipped unless LIVE_BACKEND is set',
      () {},
      skip: 'not a live run',
    );
    return;
  }

  debugDefaultTargetPlatformOverride = TargetPlatform.macOS;

  test('catalogue -> streamed download -> verified Ready -> remove', () async {
    final Directory dir =
        await Directory.systemTemp.createTemp('gyansetu_live_pack');
    addTearDown(() async {
      if (await dir.exists()) await dir.delete(recursive: true);
    });

    final DownloadManager manager = DownloadManager(
      storage: InMemorySecureStorageService(),
      transport: HttpDownloadTransport(baseUrl: ApiConfig.baseUrl),
      baseDirectory: dir.path,
    );
    await manager.init();

    // The real catalogue served by the running backend.
    final ResourceCatalogueService catalogue = ResourceCatalogueService(
      api: HttpApiClient(baseUrl: ApiConfig.baseUrl),
    );
    final Result<List<ResourceManifest>> all = await catalogue.all();
    expect(all, isA<Ok<List<ResourceManifest>>>(), reason: 'catalogue list');
    final List<ResourceManifest> manifests = (all as Ok).value;
    expect(manifests, isNotEmpty);

    final ResourceManifest pack = manifests.firstWhere(
      (ResourceManifest m) => m.id == 'c1-num-counting-1-10.content',
    );
    expect(pack.sizeBytes, greaterThan(0));

    final String packFilename =
        '${dir.path}/${pack.id.replaceAll('.', '_')}.pack';

    // Stream it off the server, verify, and only then is it Ready.
    await manager.enqueue(<ResourceManifest>[pack]);
    final Map<String, bool> settled =
        await manager.waitFor(<String>{pack.id});
    expect(settled[pack.id], isTrue, reason: 'live transfer verified');
    expect(
      manager.statusFor(pack.id)!.state,
      ResourceDownloadState.ready,
    );
    expect(await manager.downloadedBytes(), pack.sizeBytes);
    expect(await File(packFilename).exists(), isTrue);
    expect(await File(packFilename).length(), pack.sizeBytes);

    // Remove restores Missing and deletes the verified file.
    await manager.remove(pack.id);
    expect(manager.stateFor(pack.id), ResourceDownloadState.missing);
    expect(await File(packFilename).exists(), isFalse);
  });

  test('register -> lesson download marks only after every pack verifies', () async {
    final Directory dir =
        await Directory.systemTemp.createTemp('gyansetu_live_lesson');
    addTearDown(() async {
      if (await dir.exists()) await dir.delete(recursive: true);
    });

    final InMemorySecureStorageService storage =
        InMemorySecureStorageService();
    final DownloadManager manager = DownloadManager(
      storage: storage,
      transport: HttpDownloadTransport(baseUrl: ApiConfig.baseUrl),
      baseDirectory: dir.path,
    );
    await manager.init();

    final ResourceCatalogueService catalogue = ResourceCatalogueService(
      api: HttpApiClient(baseUrl: ApiConfig.baseUrl),
    );
    final LessonDownloadRepository downloads =
        LocalLessonDownloadRepository(storage);
    final ManagedLessonDownloadService service = ManagedLessonDownloadService(
      downloads: downloads,
      downloadManager: manager,
      catalogue: catalogue,
      connectivity: StaticConnectivityService(ConnectionStatus.online),
    );

    // The seeded lesson the app's own synced catalogue carries.
    final Lesson lesson = Lesson(
      id: 'c1-num-counting-1-10',
      title: 'Counting 1 to 10',
      description: 'Count everyday objects from one to ten with the class.',
      subject: ClassroomSubject.numeracy,
      classNumber: 1,
      learningOutcome: 'Learners count and name quantities from 1 to 10.',
      durationMinutes: 30,
      lessonOrder: 1,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
      resourceIds: const <String>[
        'c1-num-counting-1-10.content',
        'c1-num-counting-1-10.audio',
      ],
      audioResourceId: 'c1-num-counting-1-10.audio',
      worksheetResourceId: 'c1-ws-counting-1-10',
    );

    final DownloadOutcome outcome = await service.download(lesson);
    expect(
      outcome,
      isA<DownloadCompleted>(),
      reason: outcome is DownloadRefused
          ? '${outcome.reason}: ${outcome.message}'
          : '',
    );
    expect(await downloads.downloadedIds(), contains(lesson.id));
    expect(
      manager.stateFor('c1-num-counting-1-10.content'),
      ResourceDownloadState.ready,
    );
    expect(
      manager.stateFor('c1-num-counting-1-10.audio'),
      ResourceDownloadState.ready,
    );
    expect(
      manager.stateFor('c1-ws-counting-1-10'),
      ResourceDownloadState.ready,
    );

    // A second request finds nothing to fetch.
    expect(await service.download(lesson), isA<DownloadAlreadyPresent>());

    // Remove deletes every pack and forgets the lesson.
    await service.remove(lesson);
    expect(await downloads.downloadedIds(), isNot(contains(lesson.id)));
    expect(
      manager.stateFor('c1-num-counting-1-10.content'),
      ResourceDownloadState.missing,
    );
  });
}