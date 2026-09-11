// ignore_for_file: prefer_initializing_formals
// Private fields cannot be initialising formals: a named parameter may not
// start with an underscore.
import '../audio/lesson_audio_service.dart';
import '../connectivity/connectivity_service.dart';
import '../speech/speech_recognition_service.dart';
import '../translation/text_translation_service.dart';

/// The three things a voice-to-voice turn needs.
enum AiComponent {
  speechRecognition(label: 'Speech recognition'),
  translation(label: 'Translation'),
  speechSynthesis(label: 'Audio');

  const AiComponent({required this.label});

  final String label;
}

/// Whether one component can serve this language pair, and what is serving it.
class AiComponentStatus {
  const AiComponentStatus({
    required this.component,
    required this.available,
    required this.runsOnDevice,
    required this.isRealModel,
    this.detail,
  });

  final AiComponent component;

  /// True only when this component can actually handle the requested language.
  final bool available;

  /// True when it needs no connection.
  final bool runsOnDevice;

  /// False for a development adapter. What separates a demo from a product.
  final bool isRealModel;

  /// Why it is unavailable, when it is.
  final String? detail;
}

/// What the header pill may claim.
enum AiRuntimeState {
  /// Connectivity has not been determined. The UI must not claim either.
  connecting,

  /// Everything needed is on the device, and there is no connection.
  offlineAiActive,

  /// Everything needed is available, and there is a connection.
  onlineAiActive,

  /// Some of the pipeline works and some does not.
  limited,

  /// Nothing can run.
  unavailable,
}

/// A snapshot of what the AI pipeline can actually do right now.
class AiRuntimeStatus {
  const AiRuntimeStatus({
    required this.state,
    required this.components,
    required this.label,
    this.usesDevelopmentAdapters = false,
  });

  const AiRuntimeStatus.connecting()
      : state = AiRuntimeState.connecting,
        components = const <AiComponentStatus>[],
        label = 'Connecting',
        usesDevelopmentAdapters = false;

  final AiRuntimeState state;
  final List<AiComponentStatus> components;

  /// Exactly what the pill says. Built from [components], never a constant.
  final String label;

  /// True when any component is served by a development adapter, so the UI can
  /// mark the session as a demo pipeline rather than a working model.
  final bool usesDevelopmentAdapters;

  Iterable<AiComponentStatus> get missing =>
      components.where((AiComponentStatus c) => !c.available);

  bool get canRunPipeline =>
      components.isNotEmpty &&
      components.every((AiComponentStatus c) => c.available);

  /// The component that blocks the pipeline, if one does.
  AiComponentStatus? get firstMissing =>
      missing.isEmpty ? null : missing.first;
}

/// Reports what the AI pipeline can do for a given language pair.
///
/// The header pill reads this rather than a constant, which is why it can say
/// "Offline AI Active" honestly: it is the answer the three services gave when
/// asked about these two languages, not a decoration.
abstract interface class AiRuntimeStatusService {
  Future<AiRuntimeStatus> check({
    required String sourceLocaleId,
    required String targetLocaleId,
    required String spokenScriptLocaleId,
  });
}

/// Asks the real services, then combines their answers with connectivity.
///
/// Nothing here loads a model. Checking whether a component can serve a
/// language is a capability query, not an initialisation, which is what lets
/// the screen show a truthful status without costing a low-end phone seconds of
/// loading it may never need.
class LocalAiRuntimeService implements AiRuntimeStatusService {
  LocalAiRuntimeService({
    required SpeechRecognitionService speech,
    required TextTranslationService translator,
    required LessonAudioService audio,
    required ConnectivityService connectivity,
  })  : _speech = speech,
        _translator = translator,
        _audio = audio,
        _connectivity = connectivity;

  final SpeechRecognitionService _speech;
  final TextTranslationService _translator;
  final LessonAudioService _audio;
  final ConnectivityService _connectivity;

  @override
  Future<AiRuntimeStatus> check({
    required String sourceLocaleId,
    required String targetLocaleId,
    required String spokenScriptLocaleId,
  }) async {
    final ConnectionStatus connection = _connectivity.status;
    if (connection == ConnectionStatus.unknown) {
      return const AiRuntimeStatus.connecting();
    }

    final bool asrOk = await _speech.isAvailable(sourceLocaleId);
    final bool translationOk =
        await _translator.supportsPair(sourceLocaleId, targetLocaleId);

    // The audio layer is asked about a passage in the target language, with the
    // Devanagari fallback declared, because that is exactly how it will be
    // asked during a real turn.
    final AudioAvailability audio = await _audio.availability(
      SpokenPassage(
        lessonId: 'runtime-probe',
        label: targetLocaleId,
        displayText: 'probe',
        localeId: targetLocaleId,
        spokenText: 'probe',
        spokenScriptLocaleId: spokenScriptLocaleId,
      ),
    );

    final List<AiComponentStatus> components = <AiComponentStatus>[
      AiComponentStatus(
        component: AiComponent.speechRecognition,
        available: asrOk,
        runsOnDevice: true,
        isRealModel: _speech is PlatformSpeechRecognitionService,
        detail: asrOk
            ? null
            : 'Offline speech recognition for this language is not available '
                'on this device.',
      ),
      AiComponentStatus(
        component: AiComponent.translation,
        available: translationOk,
        runsOnDevice: !_translator.isRealModel,
        isRealModel: _translator.isRealModel,
        detail: translationOk
            ? null
            : 'Translation between these languages is not available yet.',
      ),
      AiComponentStatus(
        component: AiComponent.speechSynthesis,
        available: audio.canPlay,
        runsOnDevice: true,
        isRealModel: audio.kind != AudioVoiceKind.none,
        detail: audio.canPlay ? null : audio.blockedReason,
      ),
    ];

    final bool usesMocks =
        components.any((AiComponentStatus c) => !c.isRealModel && c.available);

    final bool allAvailable =
        components.every((AiComponentStatus c) => c.available);
    final bool noneAvailable =
        components.every((AiComponentStatus c) => !c.available);

    final AiRuntimeState state;
    final String label;
    if (noneAvailable) {
      state = AiRuntimeState.unavailable;
      label = 'AI Unavailable';
    } else if (!allAvailable) {
      state = AiRuntimeState.limited;
      label = '${components.firstWhere(
        (AiComponentStatus c) => !c.available,
      ).component.label} unavailable';
    } else if (connection == ConnectionStatus.offline) {
      state = AiRuntimeState.offlineAiActive;
      label = 'Offline AI Active';
    } else {
      state = AiRuntimeState.onlineAiActive;
      label = 'Online AI Active';
    }

    return AiRuntimeStatus(
      state: state,
      components: components,
      label: label,
      usesDevelopmentAdapters: usesMocks,
    );
  }
}
