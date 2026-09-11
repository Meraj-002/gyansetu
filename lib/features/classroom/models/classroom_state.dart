/// Who is speaking, and therefore which way the pipeline runs.
///
/// One direction enum rather than two screens: Hindi to the mother tongue and
/// the mother tongue back to Hindi are the same pipeline with its ends swapped.
enum ConversationDirection {
  /// Teacher speaks the teaching medium; children hear the mother tongue.
  teacherToStudent,

  /// A child speaks the mother tongue; the teacher hears the teaching medium.
  studentToTeacher;

  ConversationDirection get reversed =>
      this == ConversationDirection.teacherToStudent
          ? ConversationDirection.studentToTeacher
          : ConversationDirection.teacherToStudent;
}

/// Every state the live session can be in.
///
/// A single enum, not a handful of booleans: `isListening && isPlaying` is not
/// a state this feature can be in, and making it unrepresentable is cheaper
/// than defending against it everywhere.
enum ClassroomState {
  /// Nothing running. The microphone is free.
  idle,

  /// Waiting for the operating system's microphone prompt.
  requestingPermission,

  /// The microphone is open and audio is arriving.
  listening,

  /// Listening stopped; the captured speech is about to be recognised.
  speechCaptured,

  /// Speech is being turned into text.
  recognisingSpeech,

  /// Text is being translated.
  translating,

  /// The translated text is being turned into audio.
  generatingAudio,

  /// Audio exists and is ready to play.
  audioReady,

  /// Audio is playing.
  playing,

  /// The session is muted; the microphone will not open.
  muted,

  /// Something failed. The failure says which stage and whether it can be
  /// retried.
  error,

  /// The session is closing.
  ending;

  /// True while the pipeline is doing work the teacher should wait for.
  bool get isBusy => switch (this) {
        ClassroomState.recognisingSpeech ||
        ClassroomState.translating ||
        ClassroomState.generatingAudio ||
        ClassroomState.speechCaptured =>
          true,
        _ => false,
      };

  /// True while the microphone is open.
  bool get isCapturing =>
      this == ClassroomState.listening ||
      this == ClassroomState.requestingPermission;

  /// What the microphone button says underneath itself.
  String get microphoneLabel => switch (this) {
        ClassroomState.idle || ClassroomState.audioReady => 'Tap & Speak',
        ClassroomState.requestingPermission => 'Allow microphone',
        ClassroomState.listening => 'Listening…',
        ClassroomState.speechCaptured => 'Captured',
        ClassroomState.recognisingSpeech => 'Recognising…',
        ClassroomState.translating => 'Translating…',
        ClassroomState.generatingAudio => 'Preparing audio…',
        ClassroomState.playing => 'Playing',
        ClassroomState.muted => 'Muted',
        ClassroomState.error => 'Try again',
        ClassroomState.ending => 'Ending…',
      };
}

/// Which part of the pipeline something went wrong in.
///
/// Carried on the failure so a retry can resume from that stage instead of
/// asking the teacher to say the sentence again.
enum ConversationStage {
  permission,
  listening,
  recognition,
  translation,
  synthesis,
  playback;

  /// What the teacher is told. Never an exception, never a stack trace.
  String get defaultMessage => switch (this) {
        ConversationStage.permission =>
          'Microphone permission is required for Live Classroom.',
        ConversationStage.listening => "Microphone isn't available.",
        ConversationStage.recognition =>
          "Couldn't understand the speech. Please try again.",
        ConversationStage.translation =>
          "Couldn't translate this sentence. Please try again.",
        ConversationStage.synthesis => "Couldn't generate audio.",
        ConversationStage.playback => "Couldn't play the audio.",
      };
}

/// A failure the teacher can act on.
class ConversationFailure {
  const ConversationFailure({
    required this.stage,
    required this.message,
    this.retryable = true,
    this.permanentlyDenied = false,
  });

  ConversationFailure.forStage(
    this.stage, {
    String? message,
    this.retryable = true,
    this.permanentlyDenied = false,
  }) : message = message ?? stage.defaultMessage;

  final ConversationStage stage;
  final String message;

  /// False when retrying cannot possibly help — a language with no recogniser,
  /// for instance.
  final bool retryable;

  /// True when the microphone was refused for good and only the system
  /// settings can undo it.
  final bool permanentlyDenied;
}
