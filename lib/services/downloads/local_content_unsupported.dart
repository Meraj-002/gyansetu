/// No writable folder is exposed on this platform (the web).
///
/// Every operation reports the honest "not available here" answer: a null
/// root, failed writes, missing files. The download manager surfaces these as
/// a storage-unavailable refusal rather than inventing a successful download.
abstract interface class LocalContentIo {
  Future<String?> resolveContentRoot();

  Future<bool> write(String path, Stream<List<int>> bytes);
  Future<bool> rename(String from, String to);
  Future<bool> exists(String path);
  Future<int?> length(String path);
  Stream<String> readLines(String path);
  Future<String?> sha256(String path);
  Future<int> directoryBytes(String path);
  Future<void> delete(String path);
}

class UnsupportedLocalContentIo implements LocalContentIo {
  const UnsupportedLocalContentIo();

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

/// The instance every platform caller uses. On the web this always reports
/// unavailable.
final LocalContentIo deviceLocalContentIo = UnsupportedLocalContentIo();