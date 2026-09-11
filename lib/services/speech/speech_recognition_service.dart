import 'dart:async';

import 'package:speech_to_text/speech_to_text.dart' as stt;

import '../../core/utils/app_logger.dart';
import '../../core/models/app_language.dart';

/// Whether the app may open the microphone.
enum MicrophonePermission {
  /// Never asked.
  notRequested,

  granted,

  /// Refused this time; asking again is allowed.
  denied,

  /// Refused for good. Only the system settings can undo it.
  permanentlyDenied,
}

/// What came back from listening.
class SpeechRecognitionResult {
  const SpeechRecognitionResult({
    required this.text,
    required this.localeId,
    required this.isFinal,
    this.confidence,
  });

  final String text;
  final String localeId;

  /// False for a partial transcript arriving mid-sentence.
  final bool isFinal;

  /// 0..1 where the recogniser reports one. Null means it did not say.
  final double? confidence;

  bool get isEmpty => text.trim().isEmpty;
}

/// Why listening could not start or finish.
enum SpeechFailureReason {
  /// The microphone was refused.
  permission,

  /// No recogniser exists for this language on this device.
  languageUnsupported,

  /// The recogniser is not available at all.
  unavailable,

  /// Nothing intelligible was heard.
  noSpeech,

  /// The attempt failed.
  failed,
}

class SpeechRecognitionFailure implements Exception {
  const SpeechRecognitionFailure(this.reason, this.message);

  final SpeechFailureReason reason;

  /// Plain language for the teacher.
  final String message;

  @override
  String toString() => 'SpeechRecognitionFailure($reason)';
}

/// Lifecycle of a listening attempt, for the UI.
enum SpeechRecognitionState {
  /// The recogniser exists but is not doing anything.
  idle,

  /// The microphone is open and audio is being captured.
  listening,

  /// Audio was captured and is being turned into text.
  processing,

  /// A final transcript was produced.
  completed,

  /// The attempt failed.
  failed,

  /// No recogniser exists on this device at all.
  unavailable,
}

/// Turns speech into text.
///
/// The screen and the orchestrator talk to this and never to a recogniser SDK,
/// so the device recogniser, a server endpoint and an on-device model are all
/// interchangeable.
abstract interface class SpeechRecognitionService {
  /// Whether anything can recognise [localeId] on this device.
  ///
  /// Load-bearing rather than informational: Santali, Mundari and Ho have no
  /// recogniser anywhere, and the session says so instead of opening a
  /// microphone that can only produce nonsense.
  Future<bool> isAvailable(String localeId);

  /// The canonical [AppLanguage] codes a real recogniser could actually
  /// transcribe on this device, plus the locale ids of any development
  /// adapter. Load-bearing for language selection, not decoration.
  Future<List<String>> supportedLanguages();

  /// The recogniser's lifecycle, for the listening-state UI. Broadcast from the
  /// moment listening starts until [SpeechRecognitionState.idle].
  Stream<SpeechRecognitionState> get stateChanges;

  MicrophonePermission get permission;

  Future<MicrophonePermission> requestPermission();

  /// The locale currently being listened for, or null when idle.
  String? getCurrentLanguage();

  /// Partial transcripts as they arrive.
  Stream<SpeechRecognitionResult> get partialResults;

  /// Microphone level, 0..1, for the waveform. Empty on platforms that do not
  /// report it — the waveform then falls back to a state-driven shape rather
  /// than inventing amplitudes.
  Stream<double> get amplitude;

  /// Opens the microphone and completes with the final transcript.
  ///
  /// Throws [SpeechRecognitionFailure]; callers turn that into a stage failure.
  Future<SpeechRecognitionResult> startListening({
    required String localeId,
    Duration? maxDuration,
  });

  /// Stops early and keeps whatever was heard.
  Future<void> stopListening();

  /// Stops and discards.
  Future<void> cancelListening();

  Future<void> dispose();
}

/// The device's own recogniser, through `speech_to_text`.
///
/// REAL IMPLEMENTATION. It genuinely opens the microphone and genuinely
/// transcribes — for the languages the device has a recogniser for, which in
/// practice means Hindi and English on an Android phone with Google's app
/// installed. It reports every other language as unavailable.
class PlatformSpeechRecognitionService implements SpeechRecognitionService {
  PlatformSpeechRecognitionService([stt.SpeechToText? speech])
      : _speech = speech ?? stt.SpeechToText();

  static const Duration _defaultListenFor = Duration(seconds: 20);
  static const Duration _pauseFor = Duration(seconds: 3);

  final stt.SpeechToText _speech;

  final StreamController<SpeechRecognitionResult> _partials =
      StreamController<SpeechRecognitionResult>.broadcast();
  final StreamController<double> _amplitude =
      StreamController<double>.broadcast();
  final StreamController<SpeechRecognitionState> _states =
      StreamController<SpeechRecognitionState>.broadcast();

  MicrophonePermission _permission = MicrophonePermission.notRequested;
  bool _initialised = false;
  String? _currentLocale;
  Completer<SpeechRecognitionResult>? _pending;
  String _lastTranscript = '';
  double? _lastConfidence;
  SpeechRecognitionState _state = SpeechRecognitionState.idle;

  @override
  MicrophonePermission get permission => _permission;

  @override
  Stream<SpeechRecognitionState> get stateChanges {
    if (!_states.isClosed) _states.add(_state);
    return _states.stream;
  }

  void _setState(SpeechRecognitionState state) {
    _state = state;
    if (!_states.isClosed) _states.add(state);
  }

  @override
  String? getCurrentLanguage() => _currentLocale;

  @override
  Stream<SpeechRecognitionResult> get partialResults => _partials.stream;

  @override
  Stream<double> get amplitude => _amplitude.stream;

  /// Initialises once. The recogniser is not touched before this, so nothing
  /// heavy loads merely because the screen opened.
  Future<bool> _ensureInitialised() async {
    if (_initialised) return true;
    try {
      _initialised = await _speech.initialize(
        onError: (dynamic error) {
          AppLogger.error('speech recogniser error', error: error);
          _setState(SpeechRecognitionState.failed);
          _failPending(
            const SpeechRecognitionFailure(
              SpeechFailureReason.failed,
              "Couldn't understand the speech. Please try again.",
            ),
          );
        },
        onStatus: (String status) {
          if (status == 'notListening' || status == 'done') _settlePending();
        },
      );
      _permission = _initialised
          ? MicrophonePermission.granted
          : MicrophonePermission.denied;
      if (!_initialised) _setState(SpeechRecognitionState.unavailable);
      return _initialised;
    } on Object catch (error) {
      // No platform channel, or no recogniser installed. Neither is a crash.
      AppLogger.error('speech recogniser unavailable', error: error);
      _initialised = false;
      _setState(SpeechRecognitionState.unavailable);
      return false;
    }
  }

  @override
  Future<MicrophonePermission> requestPermission() async {
    final bool ready = await _ensureInitialised();
    if (ready) return _permission = MicrophonePermission.granted;

    // `speech_to_text` does not distinguish a refusal from a missing
    // recogniser, so this stays at denied rather than claiming the stronger
    // permanentlyDenied, which would send the teacher to settings for nothing.
    return _permission = MicrophonePermission.denied;
  }

  @override
  Future<bool> isAvailable(String localeId) async {
    if (!await _ensureInitialised()) return false;
    try {
      final List<stt.LocaleName> locales = await _speech.locales();
      final String wanted = localeId.toLowerCase();
      final String language = wanted.split(RegExp('[-_]')).first;
      return locales.any((stt.LocaleName l) {
        final String id = l.localeId.toLowerCase().replaceAll('_', '-');
        return id == wanted || id.split('-').first == language;
      });
    } on Object catch (error) {
      AppLogger.error('speech locales could not be read', error: error);
      return false;
    }
  }

  @override
  Future<List<String>> supportedLanguages() async {
    if (!await _ensureInitialised()) return <String>[];
    try {
      final List<stt.LocaleName> locales = await _speech.locales();
      final Set<String> supported = <String>{};
      for (final stt.LocaleName locale in locales) {
        final String code = locale.localeId.toLowerCase().replaceAll('_', '-');
        final AppLanguage? canonical = AppLanguage.byCodeStatic(code);
        supported.add(canonical?.code ?? code);
      }
      return supported.toList()..sort();
    } on Object catch (error) {
      AppLogger.error('speech locales could not be read', error: error);
      return <String>[];
    }
  }

  @override
  Future<SpeechRecognitionResult> startListening({
    required String localeId,
    Duration? maxDuration,
  }) async {
    if (!await _ensureInitialised()) {
      throw const SpeechRecognitionFailure(
        SpeechFailureReason.permission,
        'Microphone permission is required for Live Classroom.',
      );
    }
    if (!await isAvailable(localeId)) {
      throw SpeechRecognitionFailure(
        SpeechFailureReason.languageUnsupported,
        'Speech recognition for this language is not available on this '
            'device yet.',
      );
    }

    await cancelListening();

    _currentLocale = localeId;
    _lastTranscript = '';
    _lastConfidence = null;
    _setState(SpeechRecognitionState.listening);
    final Completer<SpeechRecognitionResult> pending =
        Completer<SpeechRecognitionResult>();
    _pending = pending;

    try {
      await _speech.listen(
        listenOptions: stt.SpeechListenOptions(
          localeId: localeId,
          listenFor: maxDuration ?? _defaultListenFor,
          pauseFor: _pauseFor,
          // Partial results drive the live transcript; the final one settles
          // the turn.
          partialResults: true,
          cancelOnError: true,
        ),
        onResult: (dynamic result) {
          final String words = '${result.recognizedWords}';
          _lastTranscript = words;
          final dynamic confidence = result.confidence;
          _lastConfidence = confidence is num && confidence > 0
              ? confidence.toDouble()
              : null;
          if (!_partials.isClosed) {
            _partials.add(
              SpeechRecognitionResult(
                text: words,
                localeId: localeId,
                isFinal: result.finalResult == true,
                confidence: _lastConfidence,
              ),
            );
          }
          if (result.finalResult == true) {
            _setState(SpeechRecognitionState.processing);
            _settlePending();
          }
        },
        onSoundLevelChange: (double level) {
          if (_amplitude.isClosed) return;
          // The plugin reports a rough decibel figure; it is normalised here so
          // the waveform is fed 0..1 whatever the platform's scale.
          _amplitude.add((level.abs() / 40).clamp(0.0, 1.0));
        },
      );
    } on Object catch (error) {
      AppLogger.error('listening could not start', error: error);
      _pending = null;
      throw const SpeechRecognitionFailure(
        SpeechFailureReason.unavailable,
        "Microphone isn't available.",
      );
    }

    return pending.future;
  }

  void _settlePending() {
    final Completer<SpeechRecognitionResult>? pending = _pending;
    if (pending == null || pending.isCompleted) return;
    _pending = null;

    if (_lastTranscript.trim().isEmpty) {
      _setState(SpeechRecognitionState.failed);
      pending.completeError(
        const SpeechRecognitionFailure(
          SpeechFailureReason.noSpeech,
          "Couldn't understand the speech. Please try again.",
        ),
      );
      return;
    }
    _setState(SpeechRecognitionState.completed);
    pending.complete(
      SpeechRecognitionResult(
        text: _lastTranscript,
        localeId: _currentLocale ?? '',
        isFinal: true,
        confidence: _lastConfidence,
      ),
    );
  }

  void _failPending(SpeechRecognitionFailure failure) {
    final Completer<SpeechRecognitionResult>? pending = _pending;
    if (pending == null || pending.isCompleted) return;
    _pending = null;
    pending.completeError(failure);
  }

  @override
  Future<void> stopListening() async {
    try {
      await _speech.stop();
    } on Object {
      // Stopping something that never started is not an error.
    }
    _settlePending();
    _currentLocale = null;
  }

  @override
  Future<void> cancelListening() async {
    final Completer<SpeechRecognitionResult>? pending = _pending;
    _pending = null;
    try {
      await _speech.cancel();
    } on Object {
      // As above.
    }
    _currentLocale = null;
    if (pending != null && !pending.isCompleted) {
      pending.completeError(
        const SpeechRecognitionFailure(
          SpeechFailureReason.noSpeech,
          'Listening was cancelled.',
        ),
      );
    }
  }

  @override
  Future<void> dispose() async {
    await cancelListening();
    await _partials.close();
    await _amplitude.close();
    await _states.close();
  }
}
