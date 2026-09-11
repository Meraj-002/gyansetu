import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gyan_setu_ai/core/errors/app_exception.dart';
import 'package:gyan_setu_ai/core/utils/result.dart';
import 'package:gyan_setu_ai/features/lessons/services/lesson_download_service.dart';
import 'package:gyan_setu_ai/features/setup/models/classroom_setup.dart';
import 'package:gyan_setu_ai/models/lesson.dart';
import 'package:gyan_setu_ai/models/resource_manifest.dart';
import 'package:gyan_setu_ai/services/api/api_client.dart';
import 'package:gyan_setu_ai/services/connectivity/connectivity_service.dart';
import 'package:gyan_setu_ai/services/downloads/download_manager.dart';
import 'package:gyan_setu_ai/services/resources/resource_catalogue_service.dart';
import 'package:gyan_setu_ai/services/storage/secure_storage_service.dart';

import '../downloads/download_test_doubles.dart';
import 'lesson_test_doubles.dart';

/// ApiClient that answers `/resources/{id}` from a canned map, 404ing what is
/// not scripted.
class IdAwareApiClient implements ApiClient {
  final Map<String, Map<String, dynamic>> byId = <String, Map<String, dynamic>>{};
  final List<String> getPaths = <String>[];

  @override
  Future<Result<Map<String, dynamic>>> get(
    String path, {
    Map<String, String>? query,
  }) async {
    getPaths.add(path);
    final String id = path.split('/').last;
    final Map<String, dynamic>? manifest = byId[id];
    if (manifest == null) {
      return Err<Map<String, dynamic>>(
        ServerException('not found', statusCode: 404),
      );
    }
    return Ok<Map<String, dynamic>>(manifest);
  }

  @override
  Future<Result<Map<String, dynamic>>> post(String path, {Object? body}) async =>
      Err<Map<String, dynamic>>(ServerException('unused', statusCode: 500));

  @override
  Future<Result<Map<String, dynamic>>> postMultipart(
    String path, {
    required Map<String, String> fields,
    required String fileField,
    required String filePath,
    String? filename,
  }) async => Err<Map<String, dynamic>>(
      ServerException('unused', statusCode: 500),
    );

  @override
  Future<Result<Map<String, dynamic>>> put(String path, {Object? body}) async =>
      Err<Map<String, dynamic>>(ServerException('unused', statusCode: 500));

  @override
  Future<Result<Map<String, dynamic>>> patch(
    String path, {
    Object? body,
  }) async =>
      Err<Map<String, dynamic>>(ServerException('unused', statusCode: 500));

  @override
  Future<Result<void>> delete(String path) async => const Ok<void>(null);
}

Map<String, dynamic> manifestJson(String id, int sizeBytes, String sha256) =>
    <String, dynamic>{
      'id': id,
      'kind': 'content',
      'name': id,
      'description': '',
      'classNumber': 1,
      'subject': 'foundationalLiteracy',
      'version': '1',
      'sizeBytes': sizeBytes,
      'sha256': sha256,
      'mimeType': 'application/json',
      'lessonId': 'l1',
    };

void main() {
  late Directory tempDir;
  late InMemorySecureStorageService storage;
  late Map<String, String> hashes;
  late FakePackTransport transport;
  late IdAwareApiClient api;
  late FakeDownloadRepository downloads;
  late DownloadManager manager;
  late ResourceCatalogueService catalogue;
  late StaticConnectivityService connectivity;

  Lesson lesson() => Lesson(
        id: 'l1',
        title: 'Counting 1-10',
        description: 'Count together up to ten.',
        subject: ClassroomSubject.numeracy,
        classNumber: 1,
        learningOutcome: 'Counts to ten.',
        durationMinutes: 10,
        lessonOrder: 1,
        createdAt: DateTime(2026, 8, 1),
        updatedAt: DateTime(2026, 8, 1),
        resourceIds: <String>['a.content'],
        audioResourceId: 'a.audio',
      );

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('gyansetu_managed_tests');
    storage = InMemorySecureStorageService();
    hashes = await hashesFor(samplePacks);
    transport = FakePackTransport(samplePacks);
    api = IdAwareApiClient();
    downloads = FakeDownloadRepository();
    manager = DownloadManager(
      storage: storage,
      transport: transport,
      baseDirectory: tempDir.path,
    );
    catalogue = ResourceCatalogueService(api: api);
    connectivity = StaticConnectivityService(ConnectionStatus.online);

    api.byId['a.content'] = manifestJson(
      'a.content',
      samplePacks['a.content']!.length,
      hashes['a.content']!,
    );
    api.byId['a.audio'] = manifestJson(
      'a.audio',
      samplePacks['a.audio']!.length,
      hashes['a.audio']!,
    );
  });

  tearDown(() async {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  ManagedLessonDownloadService build() => ManagedLessonDownloadService(
        downloads: downloads,
        downloadManager: manager,
        catalogue: catalogue,
        connectivity: connectivity,
      );

  test('downloads every needed pack, waits for verification, then marks the lesson', () async {
    final DownloadOutcome outcome = await build().download(lesson());

    expect(outcome, isA<DownloadCompleted>());
    expect(await downloads.downloadedIds(), contains('l1'));
    expect(await manager.downloadedBytes(),
        samplePacks['a.content']!.length + samplePacks['a.audio']!.length);
    expect(manager.stateFor('a.content'), ResourceDownloadState.ready);
    expect(manager.stateFor('a.audio'), ResourceDownloadState.ready);
  });

  test('an already-complete lesson is reported present without re-fetching', () async {
    await manager.enqueue(<ResourceManifest>[
      packManifest('a.content', samplePacks['a.content']!, hashes),
      packManifest('a.audio', samplePacks['a.audio']!, hashes),
    ]);
    await manager.waitFor(<String>{'a.content', 'a.audio'});
    downloads.markDownloaded('l1');
    final int fetches = transport.fetches;

    final DownloadOutcome outcome = await build().download(lesson());

    expect(outcome, isA<DownloadAlreadyPresent>());
    expect(transport.fetches, fetches);
  });

  test('offline on a first download refuses with a connection reason', () async {
    connectivity.set(ConnectionStatus.offline);
    final DownloadOutcome outcome = await build().download(lesson());

    expect(outcome, isA<DownloadRefused>());
    expect((outcome as DownloadRefused).reason, DownloadRefusal.needsConnection);
  });

  test('a device with no storage refuses instead of queuing fake work', () async {
    final DownloadManager noRoot = DownloadManager(
      storage: storage,
      transport: transport,
      io: NoRootLocalContentIo(),
    );
    final ManagedLessonDownloadService service = ManagedLessonDownloadService(
      downloads: downloads,
      downloadManager: noRoot,
      catalogue: catalogue,
      connectivity: connectivity,
    );

    final DownloadOutcome outcome = await service.download(lesson());

    expect(outcome, isA<DownloadRefused>());
    expect(
      (outcome as DownloadRefused).reason,
      DownloadRefusal.insufficientStorage,
    );
    expect(await downloads.downloadedIds(), isEmpty);
  });

  test('a pack missing from the catalogue refuses rather than half-downloading', () async {
    api.byId.remove('a.audio');
    final DownloadOutcome outcome = await build().download(lesson());

    expect(outcome, isA<DownloadRefused>());
    expect((outcome as DownloadRefused).reason, DownloadRefusal.failed);
    expect(await downloads.downloadedIds(), isEmpty);
  });

  test('remove deletes every pack and forgets the lesson', () async {
    await build().download(lesson());
    expect(await downloads.downloadedIds(), contains('l1'));

    await build().remove(lesson());

    expect(await downloads.downloadedIds(), isEmpty);
    expect(manager.stateFor('a.content'), ResourceDownloadState.missing);
    expect(manager.stateFor('a.audio'), ResourceDownloadState.missing);
  });

  test('hasRoomFor is false on a platform with no storage', () async {
    final DownloadManager noRoot = DownloadManager(
      storage: storage,
      transport: transport,
      io: NoRootLocalContentIo(),
    );
    final ManagedLessonDownloadService service = ManagedLessonDownloadService(
      downloads: downloads,
      downloadManager: noRoot,
      catalogue: catalogue,
      connectivity: connectivity,
    );
    expect(await service.hasRoomFor(lesson()), isFalse);
  });
}