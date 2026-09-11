/// Where a recorded microphone clip lives.
///
/// The recorder is told exactly where to write, so tests inject a fake path and
/// the device build hands over a temp file from the app's audio directory.
/// Kept narrow so the recording engine (today `record`) can be swapped without
/// touching anything above.
abstract interface class AudioRecorder {
  /// True when the microphone may be used right now.
  Future<bool> hasPermission();

  /// Starts recording to [targetPath]. Throws [AudioRecorderException] when the
  /// microphone cannot open.
  Future<void> startRecording({required String targetPath});

  /// Stops and returns the path the clip was written to, or null when nothing
  /// was captured.
  Future<String?> stopRecording();

  Future<void> dispose();
}

/// Thrown when the microphone could not be opened or read.
class AudioRecorderException implements Exception {
  AudioRecorderException(this.message);

  final String message;

  @override
  String toString() => 'AudioRecorderException($message)';
}