import 'dart:async';

import 'package:gyan_setu_ai/features/classroom/models/conversation_turn.dart';
import 'package:gyan_setu_ai/features/setup/models/classroom_setup.dart';
import 'package:gyan_setu_ai/services/ai/ai_runtime_status_service.dart';
import 'package:gyan_setu_ai/services/audio/audio_resource_store.dart';
import 'package:gyan_setu_ai/services/audio/clip_player.dart';
import 'package:gyan_setu_ai/services/speech/speech_recognition_service.dart';
import 'package:gyan_setu_ai/services/translation/text_translation_service.dart';

ConversationContext testContext({
  TargetLanguage target = TargetLanguage.santali,
  TeachingMedium medium = TeachingMedium.hindi,
  int classLevel = 1,
}) =>
    ConversationContext(
      lessonId: 'c1-num-counting-1-10',
      lessonTitle: 'Counting 1–10',
      learningOutcome: 'Count objects from 1 to 10.',
      classLevel: classLevel,
      subject: ClassroomSubject.numeracy,
      teachingMedium: medium,
      targetLanguage: target,
    );

/// A recogniser the test drives, with no microphone behind it.
class FakeSpeechRecognitionService implements SpeechRecognitionService {
  FakeSpeechRecognitionService({
    this.transcript = 'बच्चों, कितने आम हैं?',
    this.available = true,
    this.grant = MicrophonePermission.granted,
    this.failure,
    this.confidence,
  });

  String transcript;
  bool available;
  MicrophonePermission grant;

  /// Thrown instead of returning a transcript, when set.
  SpeechRecognitionFailure? failure;

  double? confidence;

  final StreamController<SpeechRecognitionResult> _partials =
      StreamController<SpeechRecognitionResult>.broadcast();
  final StreamController<double> _amplitude =
      StreamController<double>.broadcast();
  final StreamController<SpeechRecognitionState> _states =
      StreamController<SpeechRecognitionState>.broadcast();

  int listenCalls = 0;
  int cancelCalls = 0;
  int stopCalls = 0;
  final List<String> requestedLocales = <String>[];

  MicrophonePermission _permission = MicrophonePermission.notRequested;
  String? _current;

  @override
  MicrophonePermission get permission => _permission;

  @override
  String? getCurrentLanguage() => _current;

  @override
  Stream<SpeechRecognitionResult> get partialResults => _partials.stream;

  @override
  Stream<double> get amplitude => _amplitude.stream;

  @override
  Stream<SpeechRecognitionState> get stateChanges => _states.stream;

  @override
  Future<List<String>> supportedLanguages() async => available
      ? const <String>['hi-IN', 'sat']
      : const <String>[];

  void emitAmplitude(double value) => _amplitude.add(value);

  void emitPartial(String text) => _partials.add(
        SpeechRecognitionResult(
          text: text,
          localeId: _current ?? '',
          isFinal: false,
        ),
      );

  @override
  Future<bool> isAvailable(String localeId) async => available;

  @override
  Future<MicrophonePermission> requestPermission() async =>
      _permission = grant;

  @override
  Future<SpeechRecognitionResult> startListening({
    required String localeId,
    Duration? maxDuration,
  }) async {
    listenCalls++;
    requestedLocales.add(localeId);
    _current = localeId;

    final SpeechRecognitionFailure? thrown = failure;
    if (thrown != null) throw thrown;

    return SpeechRecognitionResult(
      text: transcript,
      localeId: localeId,
      isFinal: true,
      confidence: confidence,
    );
  }

  @override
  Future<void> stopListening() async {
    stopCalls++;
    _current = null;
  }

  @override
  Future<void> cancelListening() async {
    cancelCalls++;
    _current = null;
  }

  @override
  Future<void> dispose() async {
    await _partials.close();
    await _amplitude.close();
    await _states.close();
  }
}

/// A translator the test dictates.
class FakeTextTranslationService implements TextTranslationService {
  FakeTextTranslationService({
    this.translated = "Gidra'ko, kete ul menaka?",
    this.spoken = 'गिड़ाको, केते उल् मेनाका?',
    this.supported = true,
    this.failure,
    this.confidence = 0.6,
    this.realModel = false,
  });

  String translated;
  String? spoken;
  bool supported;
  TextTranslationFailure? failure;
  double? confidence;
  bool realModel;

  int calls = 0;
  TranslationRequest? lastRequest;

  @override
  String get modelVersion => 'fake-1';

  @override
  bool get isRealModel => realModel;

  @override
  bool get requiresNetwork => false;

  @override
  Future<bool> supportsPair(String source, String target) async => supported;

  @override
  Future<TranslationResult> translate(TranslationRequest request) async {
    calls++;
    lastRequest = request;
    final TextTranslationFailure? thrown = failure;
    if (thrown != null) throw thrown;

    return TranslationResult(
      translatedText: translated,
      sourceLanguage: request.sourceLanguage,
      targetLanguage: request.targetLanguage,
      modelVersion: modelVersion,
      confidence: confidence,
      spokenText: spoken,
    );
  }
}

/// Reports whatever status the test wants the header to show.
class FakeAiRuntimeStatusService implements AiRuntimeStatusService {
  FakeAiRuntimeStatusService([AiRuntimeStatus? status]) : _status = status;

  AiRuntimeStatus? _status;

  set status(AiRuntimeStatus value) => _status = value;

  @override
  Future<AiRuntimeStatus> check({
    required String sourceLocaleId,
    required String targetLocaleId,
    required String spokenScriptLocaleId,
  }) async =>
      _status ??
      const AiRuntimeStatus(
        state: AiRuntimeState.offlineAiActive,
        components: <AiComponentStatus>[],
        label: 'Offline AI Active',
      );
}

/// A clip player with no platform behind it.
class FakeClipPlayer implements ClipPlayer {
  final StreamController<void> _complete = StreamController<void>.broadcast();
  final StreamController<Duration> _position =
      StreamController<Duration>.broadcast();
  final StreamController<Duration> _duration =
      StreamController<Duration>.broadcast();

  final List<String> played = <String>[];
  int stopCalls = 0;

  @override
  Stream<void> get onComplete => _complete.stream;

  @override
  Stream<Duration> get onPosition => _position.stream;

  @override
  Stream<Duration> get onDuration => _duration.stream;

  @override
  Future<void> playFile(String path) async => played.add(path);

  @override
  Future<void> pause() async {}

  @override
  Future<void> stop() async => stopCalls++;

  @override
  Future<void> setRate(double rate) async {}

  @override
  Future<void> dispose() async {
    await _complete.close();
    await _position.close();
    await _duration.close();
  }
}

/// Builds a saved-clip record without touching the file system.
AudioResource testClip({
  String lessonId = 'c1-num-counting-1-10',
  String localeId = 'sat',
  String textHash = '',
}) =>
    AudioResource(
      audioResourceId: 'audio-$lessonId-$localeId',
      lessonId: lessonId,
      localeId: localeId,
      textHash: textHash,
      filePath: '/tmp/$lessonId-$localeId.wav',
      createdAt: DateTime(2026, 6, 1),
    );
