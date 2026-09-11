/// Where a ready offline pack lives on disk.
///
/// Implemented by [DownloadManager] in production; a thin interface so an
/// offline consumer (for example the phrasebook translation reader) stays
/// testable without the whole download pipeline.
abstract interface class OfflinePackSource {
  /// The absolute path of a verified (ready) pack, or null when this platform
  /// has no writable folder or the pack is missing.
  String? pathForReady(String id);
}