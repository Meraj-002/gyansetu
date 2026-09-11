import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:path_provider/path_provider.dart';

/// File operations the offline download pipeline needs on a platform that has
/// a writable filesystem (all non-web targets).
///
/// Every method takes absolute paths so tests can point the manager at a
/// temporary directory without touching plugins; only [resolveContentRoot]
/// consults `path_provider`.
abstract interface class LocalContentIo {
  /// The directory content packs are kept in, or null when this platform has
  /// no writable app folder.
  Future<String?> resolveContentRoot();

  /// Streams [bytes] into [path], replacing anything there. True only when the
  /// whole stream was written and flushed successfully.
  Future<bool> write(String path, Stream<List<int>> bytes);

  Future<bool> rename(String from, String to);
  Future<bool> exists(String path);
  Future<int?> length(String path);

  /// Streams the (UTF-8) lines of the file at [path] lazily, so a large
  /// phrasebook is read line-by-line instead of ever sitting whole in memory.
  /// Emits nothing (closes immediately) when the file cannot be read.
  Stream<String> readLines(String path);

  /// Hex sha256 of the file at [path], or null when it cannot be read.
  Future<String?> sha256(String path);

  Future<int> directoryBytes(String path);
  Future<void> delete(String path);
}

class DeviceLocalContentIo implements LocalContentIo {
  const DeviceLocalContentIo();

  static const String _folder = 'gyansetu/content';

  @override
  Future<String?> resolveContentRoot() async {
    try {
      final Directory base = await getApplicationDocumentsDirectory();
      final Directory root = Directory('${base.path}/$_folder');
      await root.create(recursive: true);
      return root.path;
    } on Object {
      return null;
    }
  }

  @override
  Future<bool> write(String path, Stream<List<int>> bytes) async {
    try {
      final File file = File(path);
      await file.parent.create(recursive: true);
      final IOSink sink = file.openWrite();
      try {
        await sink.addStream(bytes);
      } finally {
        await sink.close();
      }
      return true;
    } on Object {
      return false;
    }
  }

  @override
  Future<bool> rename(String from, String to) async {
    try {
      await File(from).parent.create(recursive: true);
      await File(from).rename(to);
      return true;
    } on Object {
      return false;
    }
  }

  @override
  Future<bool> exists(String path) async {
    try {
      return await File(path).exists();
    } on Object {
      return false;
    }
  }

  @override
  Future<int?> length(String path) async {
    try {
      return await File(path).length();
    } on Object {
      return null;
    }
  }

  @override
  Stream<String> readLines(String path) async* {
    try {
      final Stream<String> lines =
          File(path).openRead().transform(utf8.decoder).transform(const LineSplitter());
      await for (final String line in lines) {
        yield line;
      }
    } on Object {
      // The caller sees the stream end and reports "not available" honestly.
    }
  }

  @override
  Future<String?> sha256(String path) async {
    try {
      final HashSink sink = Sha256().newHashSink();
      await for (final List<int> chunk in File(path).openRead()) {
        sink.add(chunk);
      }
      sink.close();
      final Hash hash = await sink.hash();
      return _bytesToHex(hash.bytes);
    } on Object {
      return null;
    }
  }

  @override
  Future<int> directoryBytes(String path) async {
    int total = 0;
    try {
      final Directory directory = Directory(path);
      if (!await directory.exists()) return 0;
      await for (final FileSystemEntity entity
          in directory.list(recursive: true, followLinks: false)) {
        if (entity is File) {
          try {
            total += await entity.length();
          } on Object {
            // One unreadable cache file must not break the whole inventory.
          }
        }
      }
    } on Object {
      return total;
    }
    return total;
  }

  @override
  Future<void> delete(String path) async {
    try {
      final File file = File(path);
      if (await file.exists()) await file.delete();
    } on Object {
      // A failed delete must not take the whole pipeline down.
    }
  }
}

/// The instance every platform caller uses.
final LocalContentIo deviceLocalContentIo = DeviceLocalContentIo();

String _bytesToHex(List<int> bytes) => bytes
    .map((int b) => b.toRadixString(16).padLeft(2, '0'))
    .join();