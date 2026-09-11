import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:gyan_setu_ai/models/resource_manifest.dart';
import 'package:gyan_setu_ai/services/downloads/download_transport.dart';
import 'package:gyan_setu_ai/services/downloads/local_content.dart';

final Map<String, List<int>> samplePacks = <String, List<int>>{
  'a.content': utf8.encode('lesson A full content body'),
  'a.audio': utf8.encode('audio utterance plan for A'),
  'b.content': utf8.encode('lesson B content'),
};

String encodeHex(List<int> bytes) => bytes
    .map((int b) => b.toRadixString(16).padLeft(2, '0'))
    .join();

Future<Map<String, String>> hashesFor(Map<String, List<int>> packs) async =>
    <String, String>{
      for (final MapEntry<String, List<int>> entry in packs.entries)
        entry.key: encodeHex((await Sha256().hash(entry.value)).bytes),
    };

ResourceManifest packManifest(
  String id,
  List<int> bytes,
  Map<String, String> hashes, {
  ResourceKind kind = ResourceKind.content,
  String version = '1',
}) =>
    ResourceManifest(
      id: id,
      kind: kind,
      name: id,
      description: '',
      classNumber: 1,
      subject: 'foundationalLiteracy',
      version: version,
      sizeBytes: bytes.length,
      sha256: hashes[id]!,
      mimeType: 'application/json',
    );

/// Serves manifest bytes and records how transfers overlapped.
class FakePackTransport implements DownloadTransport {
  FakePackTransport(this.packs, {this.latency = const Duration(milliseconds: 1)});

  final Map<String, List<int>> packs;
  final Duration latency;

  bool failWithNetworkError = false;
  String? checksumOverride;
  int contentLengthOverride = -1;

  int activeTransfers = 0;
  int maxConcurrent = 0;
  int fetches = 0;

  @override
  Future<PackDownloadStream> fetch(ResourceManifest manifest) async {
    if (failWithNetworkError) {
      throw const DownloadTransportException('simulated network loss');
    }
    fetches++;
    activeTransfers++;
    if (activeTransfers > maxConcurrent) maxConcurrent = activeTransfers;
    await Future<void>.delayed(latency);
    activeTransfers--;

    final List<int> bytes = packs[manifest.id] ?? <int>[];
    final List<List<int>> chunks = <List<int>>[];
    for (int i = 0; i < bytes.length; i += 17) {
      chunks.add(bytes.sublist(i, (i + 17).clamp(0, bytes.length)));
    }
    return PackDownloadStream(
      bytes: Stream<List<int>>.fromIterable(chunks),
      contentLength:
          contentLengthOverride >= 0 ? contentLengthOverride : bytes.length,
      expectedSha256: checksumOverride ?? manifest.sha256,
    );
  }
}

/// Simulates a platform with no writable content folder (like the web).
class NoRootLocalContentIo implements LocalContentIo {
  @override
  Future<String?> resolveContentRoot() async => null;

  @override
  Future<bool> write(String path, Stream<List<int>> bytes) async => false;

  @override
  Future<bool> rename(String from, String to) async => false;

  @override
  Future<bool> exists(String path) async => false;

  @override
  Future<int?> length(String path) async => null;

  @override
  Stream<String> readLines(String path) => const Stream<String>.empty();

  @override
  Future<String?> sha256(String path) async => null;

  @override
  Future<int> directoryBytes(String path) async => 0;

  @override
  Future<void> delete(String path) async {}
}