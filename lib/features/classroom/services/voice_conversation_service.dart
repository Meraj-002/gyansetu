// ignore_for_file: prefer_initializing_formals
// Private fields cannot be initialising formals: a named parameter may not
// start with an underscore.
import 'dart:async';

import '../../../core/utils/app_logger.dart';
import '../../../services/audio/audio_recorder.dart';
import '../../../services/audio/clip_player.dart';
import '../../../services/audio/lesson_audio_service.dart';
import '../../../services/audio/voice_clip_paths.dart';
import '../../../services/connectivity/connectivity_service.dart';
import '../../../services/speech/fallback_speech_recognition_service.dart';
import '../../../services/speech/speech_recognition_service.dart';
import '../../../services/translation/text_translation_service.dart';
import '../../../services/translation/voice_translation_service.dart';
import '../models/classroom_session.dart';
import '../models/classroom_state.dart';
import '../models/conversation_turn.dart';
import '../models/voice_pipeline_metrics.dart';
import 'classroom_session_repository.dart';

/// Something the session wants the UI to know about.
sealed class ConversationEvent {
  const ConversationEvent();
}

final class ConversationStateChanged extends ConversationEvent {
  const ConversationStateChanged(this.state, this.direction);

  final ClassroomState state;
  final ConversationDirection direction;
}

/// A turn was added, or an existing one moved on.
final class ConversationTurnChanged extends ConversationEvent {
  const ConversationTurnChanged(this.turn);

  final ConversationTurn turn;
}

final class ConversationFailureRaised extends ConversationEvent {
  const ConversationFailureRaised(this.failure, {this.turnId});

  final ConversationFailure failure;
  final String? turnId;
}

/// Drives one voice-to-voice turn from microphone to audio.
///
/// The screen observes this and does not sequence anything itself. That split
/// is what lets the pipeline be tested without a widget, and lets the ASR,
/// translation and speech services all be swapped for FastAPI- or model-backed
/// ones without the screen noticing.
abstract interface class VoiceConversationService {
  ClassroomState get state;

  ConversationDirection get direction;

  bool get muted;

  List<ConversationTurn> get turns;

  ClassroomSession get session;

  /// The last turn that produced playable audio, which is what Repeat Last
  /// replays.
  ConversationTurn? get lastAudibleTurn;

  Stream<ConversationEvent> get events;

  /// Microphone level, 0..1, for the waveform.
  Stream<double> get amplitude;

  /// Runs a full turn: listen, recognise, translate, prepare audio.
  Future<void> speak(ConversationDirection direction);

  /// Ends listening early and keeps what was heard.
  Future<void> stopListening();

  /// Abandons the turn in flight.
  Future<void> cancel();

  /// Resumes the turn that failed, from the stage that failed. The teacher does
  /// not have to say the sentence again if the words were already recognised.
  Future<void> retry();

  Future<void> playTurn(String turnId);

  Future<void> repeatLast();

  Future<void> setMuted(bool value);

  /// Empties the visible timeline for this session. Does not touch sessions
  /// already saved from earlier.
  Future<void> clearTimeline();

  /// Stops everything, saves and returns the closed session.
  Future<ClassroomSession> end();

  Future<void> dispose();
}

/// The real orchestrator.
///
/// Latency is measured here rather than inside the services, because the number
/// that matters to a teacher includes this class's own overhead. Every duration
/// reported comes from a stopwatch around a real await; none is estimated.
class LiveVoiceConversationService implements VoiceConversationService {
  LiveVoiceConversationService({
    required SpeechRecognitionService speech,
    required TextTranslationService translator,
    required LessonAudioService audio,
    required ClassroomSessionRepository sessions,
    required ConversationContext context,
    required ClassroomSession initialSession,
    required ConnectivityService connectivity,
    VoiceTranslationService? voice,
    AudioRecorder? recorder,
    ClipPlayer? player,
    DateTime Function()? now,
  })  : _speech = speech,
        _translator = translator,
        _audio = audio,
        _voice = voice,
        _recorder = recorder,
        _player = player,
        _sessions = sessions,
        _context = context,
        _session = initialSession,
        _connectivity = connectivity,
        _now = now ?? DateTime.now {
    _amplitudeSubscription = _speech.amplitude.listen((double level) {
      if (!_amplitude.isClosed) _amplitude.add(level);
    });
    _partialSubscription =
        _speech.partialResults.listen(_onPartialTranscript);
    _playbackSubscription = _audio.states.listen(_onPlaybackState);
    _clipCompleteSubscription = _player?.onComplete.listen((_) => _onClipComplete());
  }

  final SpeechRecognitionService _speech;
  final TextTranslationService _translator;
  final LessonAudioService _audio;

  /// The speech-to-speech path: a recorded clip in, the mother-tongue sentence
  /// and its spoken WAV out. When [_voice], [_recorder] and [_player] are all
  /// present, a turn records a clip, uploads it and plays the returned WAV
  /// instead of dictating, text-translating and synthesising.
  final VoiceTranslationService? _voice;
  final AudioRecorder? _recorder;
  final ClipPlayer? _player;
  final ClassroomSessionRepository _sessions;
  final ConversationContext _context;
  final ConnectivityService _connectivity;
  final DateTime Function() _now;

  final StreamController<ConversationEvent> _events =
      StreamController<ConversationEvent>.broadcast();
  final StreamController<double> _amplitude =
      StreamController<double>.broadcast();

  StreamSubscription<double>? _amplitudeSubscription;
  StreamSubscription<SpeechRecognitionResult>? _partialSubscription;
  StreamSubscription<PlaybackState>? _playbackSubscription;
  StreamSubscription<void>? _clipCompleteSubscription;

  /// Completes with the recorded clip path once the second microphone tap
  /// closes the clip in the voice path. Created per speech turn in voice mode.
  Completer<String?>? _recordingComplete;

  /// True when a turn should run as recorded-clip -> Adi Vaani -> played WAV
  /// rather than dictation -> text translation -> synthesis.
  bool get _usesVoicePath => _voice != null && _recorder != null && _player != null;

  ClassroomSession _session;
  final List<ConversationTurn> _turns = <ConversationTurn>[];

  ClassroomState _state = ClassroomState.idle;
  ConversationDirection _direction = ConversationDirection.teacherToStudent;
  bool _muted = false;

  /// The turn being built, and its stopwatch. Kept so a retry can resume from
  /// the stage that failed rather than from the microphone.
  ConversationTurn? _active;
  PipelineStopwatch? _clock;
  int _turnCounter = 0;

  @override
  ClassroomState get state => _state;

  @override
  ConversationDirection get direction => _direction;

  @override
  bool get muted => _muted;

  @override
  List<ConversationTurn> get turns => List<ConversationTurn>.unmodifiable(_turns);

  @override
  ClassroomSession get session => _session.copyWith(turns: turns);

  @override
  Stream<ConversationEvent> get events => _events.stream;

  @override
  Stream<double> get amplitude => _amplitude.stream;

  @override
  ConversationTurn? get lastAudibleTurn {
    for (final ConversationTurn turn in _turns.reversed) {
      if (turn.hasAudio || (turn.translatedText ?? '').isNotEmpty) return turn;
    }
    return null;
  }

  /// True when any service in the chain is a development adapter, so every
  /// measurement it produces is stamped as a demo figure.
  bool get _usesMocks {
    if (_usesVoicePath) return false;
    if (!_translator.isRealModel) return true;
    final SpeechRecognitionService speech = _speech;
    // The fallback wrapper is only a mock while the development adapter is the
    // one that actually answered.
    if (speech is FallbackSpeechRecognitionService) return speech.usingFallback;
    return speech is! PlatformSpeechRecognitionService;
  }

  // --- Turn ----------------------------------------------------------------

  @override
  Future<void> speak(ConversationDirection direction) async {
    if (_muted) {
      _raise(
        ConversationFailure.forStage(
          ConversationStage.permission,
          message: 'The session is muted. Unmute to speak.',
          retryable: false,
        ),
      );
      return;
    }
    if (_state.isBusy || _state.isCapturing) return;

    _direction = direction;
    final String sourceLocale = _context.sourceLocaleFor(direction);
    final String targetLocale = _context.targetLocaleFor(direction);

    _clock = PipelineStopwatch(now: _now);
    final ConversationTurn turn = ConversationTurn(
      id: 'turn-${++_turnCounter}',
      sessionId: _session.sessionId,
      speaker: direction == ConversationDirection.teacherToStudent
          ? TurnSpeaker.teacher
          : TurnSpeaker.student,
      sourceLanguage: sourceLocale,
      targetLanguage: targetLocale,
      timestamp: _now(),
      status: TurnStatus.listening,
      // Recorded per turn: a lesson can start on the school wi-fi and finish in
      // the yard, and the result screen reports the mix rather than rounding.
      wasOffline: _connectivity.status == ConnectionStatus.offline,
    );
    _active = turn;
    _turns.add(turn);
    _emitTurn(turn);

    // The voice path has no dictation stage: Adi Vaani returns the transcript
    // alongside the translation, so the whole turn is record -> upload -> play.
    if (_usesVoicePath) {
      await _speakVoiceTurn();
      return;
    }

    // --- Permission ---
    _setState(ClassroomState.requestingPermission);
    final MicrophonePermission permission =
        await _speech.requestPermission();
    if (permission != MicrophonePermission.granted) {
      _failTurn(
        ConversationFailure.forStage(
          ConversationStage.permission,
          retryable: permission != MicrophonePermission.permanentlyDenied,
          permanentlyDenied:
              permission == MicrophonePermission.permanentlyDenied,
        ),
      );
      return;
    }

    // --- Listening ---
    _setState(ClassroomState.listening);
    final SpeechRecognitionResult recognised;
    try {
      recognised = await _speech.startListening(localeId: sourceLocale);
    } on SpeechRecognitionFailure catch (failure) {
      _failTurn(
        ConversationFailure(
          stage: failure.reason == SpeechFailureReason.permission
              ? ConversationStage.permission
              : ConversationStage.recognition,
          message: failure.message,
          retryable:
              failure.reason != SpeechFailureReason.languageUnsupported,
        ),
      );
      return;
    } on Object catch (error) {
      AppLogger.error('listening failed', error: error);
      _failTurn(ConversationFailure.forStage(ConversationStage.listening));
      return;
    }

    // The measured window opens where the microphone closes: everything before
    // this is the teacher talking, which is not the app's latency to own.
    _clock!.speechCaptured();
    _setState(ClassroomState.speechCaptured);
    _clock!.recognitionDone();

    _updateActive(
      (ConversationTurn t) => t.copyWith(
        status: TurnStatus.translating,
        sourceText: recognised.text,
        confidence: recognised.confidence,
      ),
    );

    await _translateAndSpeak();
  }

  /// Translation, synthesis and playback. Entered from [speak] and from
  /// [retry], which is what makes a retry resume rather than restart.
  Future<void> _translateAndSpeak() async {
    final ConversationTurn? turn = _active;
    if (turn == null) return;

    // --- Translation ---
    if ((turn.translatedText ?? '').isEmpty) {
      _setState(ClassroomState.translating);
      final TranslationResult translation;
      try {
        translation = await _translator.translate(
          TranslationRequest(
            sourceText: turn.sourceText,
            sourceLanguage: turn.sourceLanguage,
            targetLanguage: turn.targetLanguage,
            context: _context.toRequestContext(_direction),
          ),
        );
      } on TextTranslationFailure catch (failure) {
        _failTurn(
          ConversationFailure(
            stage: ConversationStage.translation,
            message: failure.message,
            retryable:
                failure.reason != TranslationFailureReason.unsupportedPair,
          ),
        );
        return;
      } on Object catch (error) {
        AppLogger.error('translation failed', error: error);
        _failTurn(
          ConversationFailure.forStage(ConversationStage.translation),
        );
        return;
      }

      _clock?.translationDone();
      _updateActive(
        (ConversationTurn t) => t.copyWith(
          status: TurnStatus.synthesising,
          translatedText: translation.translatedText,
          translatedSpokenText: translation.spokenText,
          confidence: translation.confidence ?? t.confidence,
          source: translation.source,
        ),
      );
    } else {
      _clock?.translationDone();
    }

    // --- Synthesis ---
    _setState(ClassroomState.generatingAudio);
    final SpokenPassage passage = _passageFor(_active!);
    final AudioAvailability availability = await _audio.availability(passage);

    if (!availability.canPlay) {
      _failTurn(
        ConversationFailure(
          stage: ConversationStage.synthesis,
          message: availability.blockedReason ?? "Couldn't generate audio.",
          retryable: false,
        ),
      );
      return;
    }

    // Where the platform can write a clip, one is written and registered, so
    // the same sentence is not re-synthesised and so Repeat Last plays a file
    // rather than asking the engine again. Where it cannot, the engine speaks
    // directly and the turn simply has no cached clip.
    String? audioResourceId;
    final SaveAudioOutcome saved = await _audio.save(passage);
    switch (saved) {
      case AudioSaved(:final resource):
        audioResourceId = resource.audioResourceId;
      case AudioAlreadySaved(:final resource):
        audioResourceId = resource.audioResourceId;
      case SaveBlocked():
      case SaveFailed():
        audioResourceId = null;
    }

    _clock?.audioReadyNow();
    final VoicePipelineMetrics? metrics =
        _clock?.build(measuredWithMocks: _usesMocks);

    _updateActive(
      (ConversationTurn t) => t.copyWith(
        status: TurnStatus.ready,
        audioResourceId: audioResourceId,
        metrics: metrics,
      ),
    );
    _setState(ClassroomState.audioReady);
    await _persist();

    // --- Playback ---
    await _play(_active!);
  }

  /// Text the audio layer is asked to voice.
  ///
  /// The Devanagari form is handed over where the translator supplied one; a
  /// Latin-script tribal sentence is never passed to a Hindi voice, which would
  /// read it as English.
  SpokenPassage _passageFor(ConversationTurn turn) {
    final String text = turn.translatedText ?? '';
    final String? spoken = turn.translatedSpokenText;
    return SpokenPassage(
      lessonId: _context.lessonId,
      label: _context.targetLabelFor(_direction),
      displayText: text,
      localeId: turn.targetLanguage,
      spokenText: spoken,
      spokenScriptLocaleId:
          spoken == null ? null : _context.teachingMedium.localeId,
      textHash: _hash(text),
    );
  }

  /// The speech-to-speech turn. Instead of dictating, text-translating and
  /// synthesising, it records a clip into a private temp file, uploads it and
  /// plays whatever Adi Vaani returns.
  Future<void> _speakVoiceTurn() async {
    final ConversationTurn? turn = _active;
    if (turn == null) return;

    final AudioRecorder recorder = _recorder!;
    final VoiceTranslationService voice = _voice!;

    // --- Permission ---
    if (!await recorder.hasPermission()) {
      _failTurn(
        ConversationFailure.forStage(ConversationStage.permission),
      );
      return;
    }

    // --- Record ---
    _setState(ClassroomState.requestingPermission);
    AppLogger.debug('[LIVE] recording started');
    final String recordingPath;
    try {
      recordingPath = await VoiceClipPaths.recording();
      await recorder.startRecording(targetPath: recordingPath);
    } on Object catch (error) {
      AppLogger.error('recording failed', error: error);
      _failTurn(ConversationFailure.forStage(ConversationStage.listening));
      return;
    }
    _recordingComplete = Completer<String?>();
    _setState(ClassroomState.listening);

    // --- Close the clip on the second tap ---
    final String? capturedPath = await _recordingComplete!.future;

    if (capturedPath == null) {
      // Recording was abandoned (mute/cancel/end) and the turn is already
      // handled or the session is being torn down.
      return;
    }
    AppLogger.debug('[LIVE] recording stopped');

    _clock!.speechCaptured();
    _setState(ClassroomState.speechCaptured);
    _clock!.recognitionDone();

    // --- Upload and translate ---
    _setState(ClassroomState.translating);
    _updateActive(
      (ConversationTurn t) => t.copyWith(status: TurnStatus.translating),
    );
    final VoiceTranslationResult result;
    try {
      result = await voice.translateVoice(audioPath: capturedPath);
    } on VoiceTranslationFailure catch (failure) {
      _failTurn(
        ConversationFailure(
          stage: ConversationStage.translation,
          message: failure.message,
          retryable:
              failure.reason != VoiceTranslationFailureReason.unauthorized,
        ),
      );
      return;
    } on Object catch (error) {
      AppLogger.error('voice translation failed', error: error);
      _failTurn(
        ConversationFailure.forStage(ConversationStage.translation),
      );
      return;
    }

    _clock!.translationDone();
    _clock!.audioReadyNow();
    final VoicePipelineMetrics? metrics =
        _clock?.build(measuredWithMocks: _usesMocks);

    _updateActive(
      (ConversationTurn t) => t.copyWith(
        status: TurnStatus.ready,
        sourceText: result.transcript,
        translatedText: result.translatedText,
        translatedSpokenText: result.translatedText,
        audioResourceId: result.audioPath,
        source: TranslationSource.onlineBackend,
        metrics: metrics,
      ),
    );
    _setState(ClassroomState.audioReady);
    await _persist();

    // --- Playback ---
    await _playVoice(_active!);
  }

  Future<void> _playVoice(ConversationTurn turn) async {
    final ClipPlayer player = _player!;
    final String? audioPath = turn.audioResourceId;
    if (audioPath == null) {
      _setState(ClassroomState.audioReady);
      _raise(
        ConversationFailure(
          stage: ConversationStage.playback,
          message: 'The spoken translation could not be played.',
        ),
        turnId: turn.id,
      );
      return;
    }
    _setState(ClassroomState.playing);
    AppLogger.debug('[LIVE] AudioPlayer.play called -> $audioPath');
    try {
      await player.playFile(audioPath);
      _replace(turn.copyWith(status: TurnStatus.played));
    } on Object catch (error) {
      AppLogger.error('voice clip playback failed', error: error);
      _setState(ClassroomState.audioReady);
      _raise(
        ConversationFailure(
          stage: ConversationStage.playback,
          message: 'The spoken translation could not be played.',
        ),
        turnId: turn.id,
      );
    }
  }

  Future<void> _play(ConversationTurn turn) async {
    final AudioRequestOutcome outcome = await _audio.play(_passageFor(turn));
    switch (outcome) {
      case AudioStarted():
        _setState(ClassroomState.playing);
        _replace(turn.copyWith(status: TurnStatus.played));
      case AudioBlocked(:final String message):
        _setState(ClassroomState.audioReady);
        _raise(
          ConversationFailure(
            stage: ConversationStage.playback,
            message: message,
            retryable: false,
          ),
          turnId: turn.id,
        );
      case AudioFailed(:final String message):
        _setState(ClassroomState.audioReady);
        _raise(
          ConversationFailure(
            stage: ConversationStage.playback,
            message: message,
          ),
          turnId: turn.id,
        );
    }
  }

  // --- Controls ------------------------------------------------------------

  @override
  Future<void> stopListening() async {
    if (!_state.isCapturing) return;
    if (_usesVoicePath) {
      // The second tap closes the clip: stop the recorder and release the
      // turn-building future with the recorded path.
      final String? path = await _recorder!.stopRecording();
      _recordingComplete?.complete(path);
      _recordingComplete = null;
      return;
    }
    await _speech.stopListening();
  }

  @override
  Future<void> cancel() async {
    if (_usesVoicePath) {
      _abandonRecording();
      await _player?.stop();
    } else {
      await _speech.cancelListening();
      await _audio.stop();
    }
    final ConversationTurn? turn = _active;
    if (turn != null && turn.status != TurnStatus.ready) {
      _turns.removeWhere((ConversationTurn t) => t.id == turn.id);
    }
    _active = null;
    _clock = null;
    _setState(_muted ? ClassroomState.muted : ClassroomState.idle);
  }

  @override
  Future<void> retry() async {
    final ConversationTurn? turn = _active;
    if (turn == null) {
      // Nothing half-done to resume: start a fresh turn in the same direction.
      await speak(_direction);
      return;
    }
    if (turn.sourceText.trim().isEmpty) {
      _turns.removeWhere((ConversationTurn t) => t.id == turn.id);
      _active = null;
      await speak(_direction);
      return;
    }
    // The words are already recognised, so only what failed after that is run
    // again. Re-recording the teacher would be the lazy answer and a worse one.
    _updateActive((ConversationTurn t) => t.copyWith(status: TurnStatus.translating));
    await _translateAndSpeak();
  }

  @override
  Future<void> playTurn(String turnId) async {
    final ConversationTurn? turn = _find(turnId);
    if (turn == null || (turn.translatedText ?? '').isEmpty) return;
    if (_usesVoicePath) {
      await _player?.stop();
      await _playVoice(turn);
      return;
    }
    await _audio.stop();
    await _play(turn);
  }

  @override
  Future<void> repeatLast() async {
    final ConversationTurn? turn = lastAudibleTurn;
    if (turn == null) {
      _raise(
        ConversationFailure(
          stage: ConversationStage.playback,
          message: 'No previous translation available.',
          retryable: false,
        ),
      );
      return;
    }
    if (_usesVoicePath) {
      await _player?.stop();
      await _playVoice(turn);
      return;
    }
    await _audio.stop();
    await _play(turn);
  }

  @override
  Future<void> setMuted(bool value) async {
    if (_muted == value) return;
    _muted = value;
    if (value) {
      // Muting stops the microphone, not just the label: a microphone left open
      // in a classroom is a privacy problem, not a cosmetic one.
      if (_usesVoicePath) {
        _abandonRecording();
        await _player?.stop();
      } else {
        await _speech.cancelListening();
        await _audio.stop();
      }
      _active = null;
      _setState(ClassroomState.muted);
    } else {
      _setState(ClassroomState.idle);
    }
  }

  @override
  Future<void> clearTimeline() async {
    if (_usesVoicePath) {
      _abandonRecording();
      await _player?.stop();
    } else {
      await _audio.stop();
    }
    _turns.clear();
    _active = null;
    _session = _session.copyWith(turns: const <ConversationTurn>[]);
    await _persist();
    _setState(_muted ? ClassroomState.muted : ClassroomState.idle);
  }

  @override
  Future<ClassroomSession> end() async {
    _setState(ClassroomState.ending);
    if (_usesVoicePath) {
      _abandonRecording();
      await _player?.stop();
    } else {
      await _speech.cancelListening();
      await _audio.stop();
    }

    _session = _session.copyWith(
      turns: turns,
      endedAt: _now(),
      completed: true,
    );
    await _sessions.save(_session);
    return _session;
  }

  // --- Plumbing ------------------------------------------------------------

  void _onPartialTranscript(SpeechRecognitionResult result) {
    final ConversationTurn? turn = _active;
    if (turn == null || result.isFinal) return;
    // Shows the words as they are heard, without advancing the turn's status:
    // a partial transcript is not a recognised sentence.
    _replace(turn.copyWith(sourceText: result.text));
  }

  void _onPlaybackState(PlaybackState state) {
    if (state == PlaybackState.completed &&
        _state == ClassroomState.playing) {
      _setState(_muted ? ClassroomState.muted : ClassroomState.idle);
      _active = null;
    }
  }

  /// Voice-path recording ends (idle) or is abandoned (turn already handled).
  void _onClipComplete() {
    if (_state == ClassroomState.playing) {
      _setState(_muted ? ClassroomState.muted : ClassroomState.idle);
      _active = null;
    }
  }

  /// Stops the recorder (without waiting for it) and releases the turn-building
  /// future with null so [_speakVoiceTurn] can return and let the caller own
  /// the failure/teardown. Used when muting, cancelling or ending mid-recording.
  Future<void> _abandonRecording() async {
    final Completer<String?>? pending = _recordingComplete;
    _recordingComplete = null;
    try {
      await _recorder?.stopRecording();
    } on Object catch (error) {
      AppLogger.error('recorder could not be stopped', error: error);
    }
    if (pending != null && !pending.isCompleted) pending.complete(null);
  }

  ConversationTurn? _find(String id) {
    for (final ConversationTurn turn in _turns) {
      if (turn.id == id) return turn;
    }
    return null;
  }

  void _updateActive(ConversationTurn Function(ConversationTurn) change) {
    final ConversationTurn? turn = _active;
    if (turn == null) return;
    final ConversationTurn next = change(turn);
    _active = next;
    _replace(next);
  }

  void _replace(ConversationTurn turn) {
    final int index =
        _turns.indexWhere((ConversationTurn t) => t.id == turn.id);
    if (index >= 0) {
      _turns[index] = turn;
    } else {
      _turns.add(turn);
    }
    if (_active?.id == turn.id) _active = turn;
    _emitTurn(turn);
  }

  void _failTurn(ConversationFailure failure) {
    final ConversationTurn? turn = _active;
    if (turn != null) {
      _replace(
        turn.copyWith(
          status: TurnStatus.failed,
          failureMessage: failure.message,
        ),
      );
    }
    _setState(ClassroomState.error);
    _raise(failure, turnId: turn?.id);
  }

  void _setState(ClassroomState next) {
    if (_state == next) return;
    _state = next;
    _emit(ConversationStateChanged(next, _direction));
  }

  void _emitTurn(ConversationTurn turn) =>
      _emit(ConversationTurnChanged(turn));

  void _raise(ConversationFailure failure, {String? turnId}) =>
      _emit(ConversationFailureRaised(failure, turnId: turnId));

  void _emit(ConversationEvent event) {
    if (!_events.isClosed) _events.add(event);
  }

  Future<void> _persist() async {
    _session = _session.copyWith(turns: turns);
    try {
      await _sessions.save(_session);
    } on Object catch (error) {
      // A storage failure must not interrupt a lesson in progress.
      AppLogger.error('session could not be saved', error: error);
    }
  }

  /// A short, stable key for a sentence. Not a cryptographic hash and not used
  /// as one: it only has to tell two classroom sentences apart in a cache.
  static String _hash(String value) {
    int hash = 0x811c9dc5;
    for (final int unit in value.trim().toLowerCase().codeUnits) {
      hash = (hash ^ unit) * 0x01000193 & 0xFFFFFFFF;
    }
    return hash.toRadixString(16).padLeft(8, '0');
  }

  @override
  Future<void> dispose() async {
    await _amplitudeSubscription?.cancel();
    await _partialSubscription?.cancel();
    await _playbackSubscription?.cancel();
    await _clipCompleteSubscription?.cancel();
    // The microphone and the speaker are released here and nowhere else, so
    // leaving the screen can never leave either running.
    if (_usesVoicePath) {
      await _recorder?.dispose();
      await _player?.dispose();
    } else {
      await _speech.cancelListening();
      await _audio.stop();
    }
    await _events.close();
    await _amplitude.close();
  }
}
