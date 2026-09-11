// ignore_for_file: prefer_initializing_formals
// Private fields cannot be initialising formals: a named parameter may not
// start with an underscore.
import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../core/models/app_language.dart';
import '../../../core/utils/app_logger.dart';
import '../../../services/audio/audio_recorder.dart';
import '../../../services/audio/clip_player.dart';
import '../../../services/audio/text_to_speech_service.dart';
import '../../../services/audio/voice_clip_paths.dart';
import '../../../services/speech/speech_recognition_service.dart';
import '../../../services/translation/text_translation_service.dart';
import '../../../services/translation/voice_translation_service.dart';

/// What the translate screen is showing.
enum TranslateStatus { idle, loading, success, error }

/// Drives the translate screen against the offline-first translator, and wires
/// the real speech -> translation -> speech pipeline without faking a link:
///
///  - a microphone button dictates into the sentence; a language nothing can
///    recognise is reported unavailable instead of opening a dead microphone,
///  - a speaker button reads the result aloud; a language with no voice is
///    reported unavailable instead of being read by the wrong voice.
///
/// Never accepts a half truth: every success carries the source the translator
/// honestly reported (phrasebook / offline model / online / cached), and every
/// failure carries the reason (including the exact offline message) so the
/// screen says what happened instead of inventing an answer.
class TranslateController extends ChangeNotifier {
  TranslateController({
    required TextTranslationService translator,
    SpeechRecognitionService? speech,
    TextToSpeechService? tts,
    VoiceTranslationService? voice,
    AudioRecorder? recorder,
    ClipPlayer? player,
    Future<String> Function()? recordingPath,
  }) : _translator = translator,
       speech = speech,
       tts = tts,
       _voice = voice,
       _recorder = recorder,
       _player = player,
       _recordingPath = recordingPath ?? VoiceClipPaths.recording {
    if (tts != null) {
      _ttsSubscription = tts.events.listen((SpeechEvent event) {
        if (event == SpeechEvent.started) {
          isSpeaking = true;
          notifyListeners();
        } else if (event == SpeechEvent.completed ||
            event == SpeechEvent.cancelled ||
            event == SpeechEvent.failed) {
          isSpeaking = false;
          notifyListeners();
        }
      });
    }
  }

  final TextTranslationService _translator;

  /// The recognised-speech service, when the environment provides one. Null in
  /// a build with no recogniser — the microphone control then says so.
  final SpeechRecognitionService? speech;

  /// The speech-synthesis service, when the environment provides one.
  final TextToSpeechService? tts;

  /// The speech-to-speech path, when the environment provides one. When both
  /// [speech] (on-device dictation) and [voice] (recorded -> translated audio)
  /// exist, the microphone performs voice translation end to end.
  final VoiceTranslationService? _voice;

  /// The microphone recorder, for the voice-translation path.
  final AudioRecorder? _recorder;

  /// The local audio player, for replaying the translated clip. Null in a
  /// build with no player — the speaker control then stays on the TTS engine.
  final ClipPlayer? _player;

  /// Where a recorded Hindi clip is written, before it is uploaded.
  final Future<String> Function() _recordingPath;

  /// The spoken clip path returned by the last voice translation, cached so
  /// the speaker button replays it without asking the network again.
  String? _voiceClipPath;

  StreamSubscription<SpeechEvent>? _ttsSubscription;
  StreamSubscription<void>? _clipCompleteSubscription;

  TranslateStatus status = TranslateStatus.idle;

  AppLanguage sourceLanguage = AppLanguage.hindi;
  AppLanguage targetLanguage = AppLanguage.santali;

  TranslationResult? result;
  String? errorMessage;

  /// A plain-language note about a capability that is honestly unavailable
  /// (no recogniser, no voice), distinct from a translation error.
  String? availabilityNote;

  bool isListening = false;
  bool isRecording = false;
  bool isSpeaking = false;

  void swapLanguages() {
    final AppLanguage held = sourceLanguage;
    sourceLanguage = targetLanguage;
    targetLanguage = held;
    availabilityNote = null;
    notifyListeners();
  }

  void setSourceLanguage(AppLanguage language) {
    sourceLanguage = language;
    availabilityNote = null;
    notifyListeners();
  }

  void setTargetLanguage(AppLanguage language) {
    targetLanguage = language;
    availabilityNote = null;
    notifyListeners();
  }

  Future<void> translate(String text) async {
    final String trimmed = text.trim();
    if (trimmed.isEmpty) {
      status = TranslateStatus.error;
      errorMessage = 'Type a sentence to translate first.';
      notifyListeners();
      return;
    }

    status = TranslateStatus.loading;
    result = null;
    errorMessage = null;
    availabilityNote = null;
    notifyListeners();

    try {
      final TranslationResult translated = await _translator.translate(
        TranslationRequest(
          sourceText: trimmed,
          sourceLanguage: sourceLanguage.code,
          targetLanguage: targetLanguage.code,
        ),
      );
      result = translated;
      status = TranslateStatus.success;
    } on TextTranslationFailure catch (failure) {
      errorMessage = failure.message;
      status = TranslateStatus.error;
    } on Object {
      errorMessage =
          'The translation could not be completed right now. Please try again.';
      status = TranslateStatus.error;
    }
    notifyListeners();
  }

  /// Opens the microphone for [sourceLanguage], hands the transcript to
  /// [onTranscribed] (the screen fills the input and can translate), or reports
  /// honestly why nothing can be recognised.
  Future<void> startListening({
    void Function(String text)? onTranscribed,
  }) async {
    final SpeechRecognitionService? recogniser = speech;
    if (recogniser == null) {
      availabilityNote = 'Speech recognition is not available on this device.';
      notifyListeners();
      return;
    }

    isListening = true;
    availabilityNote = null;
    notifyListeners();

    try {
      final MicrophonePermission permission = await recogniser
          .requestPermission();
      if (permission != MicrophonePermission.granted) {
        availabilityNote = 'Microphone permission is needed to dictate.';
      } else {
        final SpeechRecognitionResult recognised = await recogniser
            .startListening(localeId: sourceLanguage.code);
        isListening = false;
        notifyListeners();
        onTranscribed?.call(recognised.text);
      }
    } on SpeechRecognitionFailure catch (failure) {
      availabilityNote = failure.message;
    } on Object {
      availabilityNote = "The microphone couldn't be started. Try again.";
    }
    isListening = false;
    notifyListeners();
  }

  /// Whether the voice (speech-to-speech) path is wired in this build.
  ///
  /// When true the microphone button records Hindi, uploads it, and the
  /// translated text with its spoken WAV come back from Adi Vaani — the screen
  /// never opens an on-device recogniser and never invents a Santali voice.
  bool get hasVoiceTranslation =>
      _voice != null && _recorder != null && hasPlayer;

  /// Whether translated audio can be replayed (needs the local player).
  bool get hasPlayer => _player != null;

  /// The recorded Urdu/Hindi clip path from the last voice translation, or
  /// null when the current result has no local audio to replay.
  String? get voiceClipPath => _voiceClipPath;

  /// Opens the microphone for the speech-to-speech path: records [sourceLanguage]
  /// (Hindi) into a temp file and sets [isRecording]. The caller's second tap
  /// calls [stopVoiceTranslation], which uploads and then completes the turn.
  Future<void> startVoiceTranslation() async {
    final AudioRecorder? recorder = _recorder;
    final VoiceTranslationService? voice = _voice;
    if (recorder == null || voice == null) {
      availabilityNote = 'Speech translation is not available on this device.';
      notifyListeners();
      return;
    }

    final bool permitted = await recorder.hasPermission();
    if (!permitted) {
      availabilityNote = 'Microphone permission is needed to record.';
      notifyListeners();
      return;
    }

    isRecording = true;
    errorMessage = null;
    availabilityNote = null;
    notifyListeners();

    try {
      final String path = await _recordingPath();
      AppLogger.debug('voice: recording started -> $path');
      await recorder.startRecording(targetPath: path);
    } on AudioRecorderException catch (failure) {
      isRecording = false;
      availabilityNote = failure.message;
      notifyListeners();
    } on Object {
      isRecording = false;
      availabilityNote = "The microphone couldn't be started. Try again.";
      notifyListeners();
    }
  }

  /// Stops the microphone and runs the recorded clip through the voice
  /// translation pipeline. On success the result holds the honest Adi Vaani
  /// transcript, the translated text, and a locally replayed clip; on failure
  /// the exact reason without ever inventing an answer.
  Future<void> stopVoiceTranslation() async {
    final VoiceTranslationService? voice = _voice;
    final AudioRecorder? recorder = _recorder;
    if (voice == null || recorder == null || !isRecording) return;

    isRecording = false;
    status = TranslateStatus.loading;
    result = null;
    errorMessage = null;
    availabilityNote = null;
    _voiceClipPath = null;
    notifyListeners();

    final String? clipPath = await recorder.stopRecording();
    AppLogger.debug('voice: recording stopped -> $clipPath');
    if (clipPath == null || clipPath.isEmpty) {
      status = TranslateStatus.error;
      errorMessage = "Couldn't hear the speech. Please try again.";
      notifyListeners();
      return;
    }

    try {
      final VoiceTranslationResult translated = await voice.translateVoice(
        audioPath: clipPath,
      );
      _voiceClipPath = translated.audioPath;
      result = TranslationResult(
        translatedText: translated.translatedText,
        originalText: translated.transcript,
        sourceLanguage: sourceLanguage.code,
        targetLanguage: targetLanguage.code,
        modelVersion: 'adivaani-ists-v1',
        source: TranslationSource.onlineBackend,
        engineName: 'adivaani',
        engineIsRealModel: true,
        provider: translated.provider,
      );
      status = TranslateStatus.success;
    } on VoiceTranslationFailure catch (failure) {
      errorMessage = failure.message;
      status = TranslateStatus.error;
    } on Object {
      errorMessage =
          'The speech translation could not be completed right now. '
          'Please try again.';
      status = TranslateStatus.error;
    }
    notifyListeners();
  }

  /// Reads the translated sentence aloud.
  ///
  /// When the current result came from a voice translation, this replays the
  /// returned WAV through the local player instead of the text-to-speech
  /// engine — the exact recorded answer, never a synthetic re-read.
  /// Otherwise the displayed text is handed straight to [TextToSpeechService.speak]
  /// with the target language's locale; no Santali-specific availability gate
  /// blocks the attempt — whatever engine the device has speaks whatever it can.
  Future<void> speakTranslation() async {
    final String? clipPath = _voiceClipPath;
    if (clipPath != null && _player != null) {
      AppLogger.debug('voice: replaying cached Adi Vaani clip instead of TTS');
      await _replayClip(clipPath);
      return;
    }

    final TextToSpeechService? engine = tts;
    final TranslationResult? translated = result;
    if (engine == null) {
      availabilityNote = 'Speech is not available on this device.';
      notifyListeners();
      return;
    }
    if (translated == null) return;

    final String localeId = targetLanguage.code;
    isSpeaking = true;
    notifyListeners();
    final outcome = await engine.speak(
      translated.translatedText,
      localeId: localeId,
    );
    isSpeaking = false;
    notifyListeners();
    if (outcome.isOk) return;
    availabilityNote = 'The text could not be read aloud right now.';
    notifyListeners();
  }

  Future<void> _replayClip(String clipPath) async {
    isSpeaking = true;
    notifyListeners();
    _clipCompleteSubscription?.cancel();
    _clipCompleteSubscription = _player?.onComplete.listen((_) {
      isSpeaking = false;
      notifyListeners();
    });
    try {
      await _player?.playFile(clipPath);
    } on Object {
      isSpeaking = false;
      notifyListeners();
      availabilityNote = 'The text could not be read aloud right now.';
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _ttsSubscription?.cancel();
    _clipCompleteSubscription?.cancel();
    super.dispose();
  }
}
