/// A file this app wrote to the device.
class SavedFile {
  const SavedFile({
    required this.path,
    required this.fileName,
    required this.bytes,
  });

  final String path;
  final String fileName;

  /// Size on disk. Checked after writing, so a save can only be reported when
  /// there is really something there.
  final int bytes;
}
