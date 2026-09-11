import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gyan_setu_ai/core/utils/result.dart';
import 'package:gyan_setu_ai/models/resource_manifest.dart';
import 'package:gyan_setu_ai/services/ai/ai_model_manager.dart';
import 'package:gyan_setu_ai/services/downloads/download_manager.dart';
import 'package:gyan_setu_ai/services/resources/resource_catalogue_service.dart';
import 'package:gyan_setu_ai/services/storage/secure_storage_service.dart';

import '../api/api_test_doubles.dart';
import '../downloads/download_test_doubles.dart';

class StubCatalogue extends ResourceCatalogueService {
  StubCatalogue({required this.known})
      : super(api: ScriptedApiClient());

  final Map<String, ResourceManifest> known;

  @override
  Future<Result<ResourceManifest?>> byId(String id) async => Ok(known[id]);
}

void main() {
  late Directory tempDir;
  late InMemorySecureStorageService storage;
  late FakePackTransport transport;
  late Map<String, String> hashes;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('gyansetu_ai_tests');
    storage = InMemorySecureStorageService();
    hashes = await hashesFor(samplePacks);
    transport = FakePackTransport(samplePacks);
  });

  tearDown(() async {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  ResourceManifest manifestFor(String id) => packManifest(
        id,
        samplePacks[id]!,
        hashes,
      );

  DownloadManager manager() => DownloadManager(
        storage: storage,
        transport: transport,
        baseDirectory: tempDir.path,
      );

  test('keeps a pack honestly notInstalled until it is verified on disk',
      () async {
    final DownloadManager downloads = manager();
    await downloads.init();
    final ResourceBackedAiModelManager models = ResourceBackedAiModelManager(
      downloadManager: downloads,
      catalogue: StubCatalogue(known: <String, ResourceManifest>{
        'a.content': manifestFor('a.content'),
      }),
    );

    expect(await models.modelState('a.content'), AiModelState.notInstalled);
    expect(await models.isModelAvailable('a.content'), isFalse);
  });

  test('download() drives the verified pipeline into ready', () async {
    final DownloadManager downloads = manager();
    await downloads.init();
    final ResourceBackedAiModelManager models = ResourceBackedAiModelManager(
      downloadManager: downloads,
      catalogue: StubCatalogue(known: <String, ResourceManifest>{
        'a.content': manifestFor('a.content'),
      }),
    );

    await models.download('a.content');

    expect(await models.modelState('a.content'), AiModelState.ready);
    expect(await models.isModelAvailable('a.content'), isTrue);
    final AiModelInfo? info = await models.modelInfo('a.content');
    expect(info, isNotNull);
    expect(info!.version, '1');
    expect(info.sizeBytes, manifestFor('a.content').sizeBytes);
  });

  test('a pack the server no longer advertises cannot download', () async {
    final DownloadManager downloads = manager();
    await downloads.init();
    final ResourceBackedAiModelManager models = ResourceBackedAiModelManager(
      downloadManager: downloads,
      catalogue: StubCatalogue(known: <String, ResourceManifest>{}),
    );

    await expectLater(
      models.download('b.content'),
      throwsA(isA<StateError>()),
    );
    expect(await models.isModelAvailable('b.content'), isFalse);
  });

  test('load and unload flip only the in-memory flag, not the disk', () async {
    final DownloadManager downloads = manager();
    await downloads.init();
    final ResourceBackedAiModelManager models = ResourceBackedAiModelManager(
      downloadManager: downloads,
      catalogue: StubCatalogue(known: <String, ResourceManifest>{
        'a.content': manifestFor('a.content'),
      }),
    );
    await models.download('a.content');

    await models.loadModel('a.content');
    expect(await models.modelState('a.content'), AiModelState.loaded);

    await models.unloadModel('a.content');
    expect(await models.modelState('a.content'), AiModelState.ready);
  });

  test('load refuses when nothing is verified on disk', () async {
    final DownloadManager downloads = manager();
    await downloads.init();
    final ResourceBackedAiModelManager models = ResourceBackedAiModelManager(
      downloadManager: downloads,
      catalogue: StubCatalogue(known: <String, ResourceManifest>{
        'a.content': manifestFor('a.content'),
      }),
    );

    await expectLater(
      models.loadModel('a.content'),
      throwsA(isA<StateError>()),
    );
  });

  test('a machine with no catalogue honestly stays unavailable', () async {
    final HaltWithoutCatalogueAiModelManager models =
        const HaltWithoutCatalogueAiModelManager();

    expect(await models.modelState('anything'), AiModelState.notInstalled);
    expect(await models.isModelAvailable('anything'), isFalse);
    expect(await models.modelInfo('anything'), isNull);
    await expectLater(
      models.download('anything'),
      throwsA(isA<StateError>()),
    );
  });
}