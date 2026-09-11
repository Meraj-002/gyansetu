/// One speech-to-speech turn: a recorded Hindi clip in, the mother-tongue
/// sentence and its spoken WAV out.
///
/// The service talks to GyanSetu's backend, which proxies the public Adi Vaani
/// ISTS endpoint. The device sees three honest outputs — what was heard
/// ([VoiceTranslationResult.transcript]), the translated text, and a local
/// path to the returned audio so the speaker control can replay it without
/// asking the network twice.
abstract interface class VoiceTranslationService {
  /// Uploads [audioPath] and returns the spoken translation.
  ///
  /// Throws [VoiceTranslationFailure]; never fabricates a transcript, a
  /// translation, or audio.
  Future<VoiceTranslationResult> translateVoice({
    required String audioPath,
  });
}

class VoiceTranslationResult {
  VoiceTranslationResult({
    required this.transcript,
    required this.translatedText,
    required this.audioPath,
    this.contentType = 'audio/wav',
    this.provider = 'adivaani',
  });

  /// The sentence Adi Vaani heard in Hindi.
  final String transcript;

  /// The Santali sentence it produced.
  final String translatedText;

  /// Absolute path on this device to the spoken translation (WAV), written
  /// from the provider's payload so the speaker button replays it locally.
  final String audioPath;

  final String contentType;
  final String provider;
}

enum VoiceTranslationFailureReason {
  /// The provider answered, but the body was unusable (no text or no audio).
  failed,

  /// The network is not available, or the backend/Adi Vaani could not be
  /// reached in time.
  needsConnection,

  /// The server rejected the stored session credential.
  unauthorized,
}

class VoiceTranslationFailure implements Exception {
  const VoiceTranslationFailure(this.reason, this.message);

  final VoiceTranslationFailureReason reason;
  final String message;

  @override
  String toString() => 'VoiceTranslationFailure($reason)';
}