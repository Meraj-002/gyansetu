import '../../core/utils/result.dart';

/// Contract for converting a teacher's or pupil's speech into text.
///
/// Implementations must state whether they run on-device or call the server:
/// classroom dictation has to keep working with no connectivity.
abstract interface class SpeechToTextService {
  /// Whether the microphone permission has been granted.
  Future<bool> hasPermission();

  /// Requests the microphone permission, returning the resulting grant state.
  Future<bool> requestPermission();

  /// Begins listening. Partial transcripts arrive on the returned stream; the
  /// stream closes when [stop] is called or the recogniser times out.
  Future<Result<Stream<String>>> listen({required String localeId});

  Future<Result<void>> stop();
}
