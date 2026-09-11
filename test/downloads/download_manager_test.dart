import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gyan_setu_ai/models/resource_manifest.dart';
import 'package:gyan_setu_ai/services/downloads/download_manager.dart';
import 'package:gyan_setu_ai/services/storage/secure_storage_service.dart';

import 'download_test_doubles.dart';

void main() {
  late Directory tempDir;
  late InMemorySecureStorageService storage;
  late Map<String, String> hashes;
  late FakePackTransport transport;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('gyansetu_download_tests');
    storage = InMemorySecureStorageService();
    hashes = await hashesFor(samplePacks);
    transport = FakePackTransport(samplePacks);
  });

  tearDown(() async {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  ResourceManifest manifestFor(String id, {int? sizeOverride}) {
    final List<int> bytes = samplePacks[id]!;
    return ResourceManifest(
      id: id,
      kind: ResourceKind.content,
      name: id,
      description: '',
      classNumber: 1,
      subject: 'foundationalLiteracy',
      version: '1',
      sizeBytes: sizeOverride ?? bytes.length,
      sha256: hashes[id]!,
      mimeType: 'application/json',
    );
  }

  DownloadManager manager() => DownloadManager(
        storage: storage,
        transport: transport,
        baseDirectory: tempDir.path,
      );

  String packFile(String id) =>
      '${tempDir.path}/${id.replaceAll('.', '_')}.pack';

  test('streams, verifies and renames a pack, then reports honest bytes', () async {
    final DownloadManager m = manager();
    await m.init();
    final ResourceManifest manifest = manifestFor('a.content');

    await m.enqueue(<ResourceManifest>[manifest]);
    final Map<String, bool> settled = await m.waitFor(<String>{'a.content'});

    expect(settled['a.content'], isTrue);
    expect(m.stateFor('a.content'), ResourceDownloadState.ready);
    expect(m.readyIds, contains('a.content'));
    expect(await m.downloadedBytes(), manifest.sizeBytes);
    expect(transport.maxConcurrent, 1);

    final File file = File(packFile('a.content'));
    expect(await file.exists(), isTrue);
    expect(await file.length(), manifest.sizeBytes);
  });

  test('restores verified packs across restarts without re-downloading', () async {
    final DownloadManager first = manager();
    await first.enqueue(<ResourceManifest>[manifestFor('a.content')]);
    await first.waitFor(<String>{'a.content'});

    final DownloadManager second = manager();
    await second.init();

    expect(second.stateFor('a.content'), ResourceDownloadState.ready);
    expect(second.readyIds, contains('a.content'));
    expect(transport.fetches, 1);
  });

  test('demotes a ready pack whose file vanishes on the next boot', () async {
    final DownloadManager first = manager();
    await first.enqueue(<ResourceManifest>[manifestFor('a.content')]);
    await first.waitFor(<String>{'a.content'});

    // The file disappears behind the scene (a cache cleaner, a wipe).
    await File(packFile('a.content')).delete();

    final DownloadManager second = manager();
    await second.init();
    expect(second.stateFor('a.content'), ResourceDownloadState.missing);
  });

  test('a short body fails verification as corrupted and leaves no file', () async {
    final DownloadManager m = manager();
    await m.init();

    // The catalogue advertises more bytes than the server delivers: the
    // streamed file can never be the pack the manifest promised.
    await m.enqueue(<ResourceManifest>[
      manifestFor('a.content', sizeOverride: samplePacks['a.content']!.length + 100),
    ]);
    final Map<String, bool> settled = await m.waitFor(<String>{'a.content'});

    expect(settled['a.content'], isFalse);
    final ResourceDownloadStatus? status = m.statusFor('a.content');
    expect(status?.state, ResourceDownloadState.failed);
    expect(status?.failure, ResourceDownloadFailure.corrupted);

    expect(await File('${packFile('a.content')}.part').exists(), isFalse);
    expect(await File(packFile('a.content')).exists(), isFalse);
  });

  test('a checksum mismatch fails verification as corrupted', () async {
    transport.checksumOverride = 'not-the-real-checksum';
    final DownloadManager m = manager();
    await m.init();

    await m.enqueue(<ResourceManifest>[manifestFor('a.content')]);
    final Map<String, bool> settled = await m.waitFor(<String>{'a.content'});

    expect(settled['a.content'], isFalse);
    expect(m.statusFor('a.content')?.failure, ResourceDownloadFailure.corrupted);
  });

  test('a network failure is reported, does not block others, and retry works', () async {
    final DownloadManager m = manager();
    await m.init();
    await m.enqueue(<ResourceManifest>[manifestFor('a.content')]);
    await m.waitFor(<String>{'a.content'});

    transport.failWithNetworkError = true;
    await m.retry('a.content');
    final Map<String, bool> retried = await m.waitFor(<String>{'a.content'});
    expect(retried['a.content'], isFalse);
    expect(m.statusFor('a.content')?.failure, ResourceDownloadFailure.network);

    transport.failWithNetworkError = false;
    await m.retry('a.content');
    final Map<String, bool> good = await m.waitFor(<String>{'a.content'});
    expect(good['a.content'], isTrue);
  });

  test('remove deletes the verified file and forgets the pack', () async {
    final DownloadManager m = manager();
    await m.init();
    await m.enqueue(<ResourceManifest>[manifestFor('a.content')]);
    await m.waitFor(<String>{'a.content'});

    await m.remove('a.content');

    expect(m.stateFor('a.content'), ResourceDownloadState.missing);
    expect(m.readyIds, isEmpty);
    expect(await File(packFile('a.content')).exists(), isFalse);
    expect(await m.downloadedBytes(), 0);
  });

  test('transfers one pack at a time in a serial queue', () async {
    final DownloadManager m = manager();
    await m.init();
    await m.enqueue(<ResourceManifest>[
      manifestFor('a.content'),
      manifestFor('a.audio'),
      manifestFor('b.content'),
    ]);

    await m.waitFor(<String>{'a.content', 'a.audio', 'b.content'});
    expect(transport.maxConcurrent, 1);
    expect(m.readyIds, <String>{'a.content', 'a.audio', 'b.content'});
  });

  test('a duplicate enqueue is ignored', () async {
    final DownloadManager m = manager();
    await m.init();
    await m.enqueue(<ResourceManifest>[manifestFor('a.content')]);
    final List<String> second =
        await m.enqueue(<ResourceManifest>[manifestFor('a.content')]);
    expect(second, isEmpty);
    await m.waitFor(<String>{'a.content'});
    expect(m.stateFor('a.content'), ResourceDownloadState.ready);
    expect(transport.fetches, 1);
  });

  test('a platform with no writable storage never queues fake work', () async {
    final DownloadManager m = DownloadManager(
      storage: storage,
      transport: transport,
      io: NoRootLocalContentIo(),
    );
    await m.init();

    final List<String> added =
        await m.enqueue(<ResourceManifest>[manifestFor('a.content')]);
    expect(added, isEmpty);
    expect(m.stateFor('a.content'), ResourceDownloadState.missing);
  });
}