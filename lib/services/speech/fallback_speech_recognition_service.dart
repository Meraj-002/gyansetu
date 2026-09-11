import 'dart:async';

import '../../core/utils/app_logger.dart';
import 'development_speech_recognition_service.dart';
import 'speech_recognition_service.dart';

/// Uses the device's recogniser, and falls back only where it genuinely cannot
/// serve the language.
///
/// The choice is made on the first request, not when the screen opens. That
/// matters twice over: initialising a recogniser costs a low-end phone real
/// time for a session the teacher may never start, and it makes Android show
/// the microphone prompt before anyone has asked to speak.
class FallbackSpeechRecognitionService implements SpeechRecognitionService {
  FallbackSpeechRecognitionService({
    SpeechRecognitionService? platform,
    SpeechRecognitionService? fallback,
  })  : _platform = platform ?? PlatformSpeechRecognitionService(),
        _fallback = fallback ?? DevelopmentSpeechRecognitionService();

  final SpeechRecognitionService _platform;

  /// DEVELOPMENT MOCK. Only ever reached for a language the device cannot
  /// recognise, and everything it produces is marked as coming from a mock.
  final SpeechRecognitionService _fallback;

  final StreamController<SpeechRecognitionResult> _partials =
      StreamController<SpeechRecognitionResult>.broadcast();
  final StreamController<double> _amplitude =
      StreamController<double>.broadcast();
  final StreamController<SpeechRecognitionState> _states =
      StreamController<SpeechRecognitionState>.broadcast();

  late final StreamSubscription<SpeechRecognitionResult> _platformPartials =
      _platform.partialResults.listen(_partials.add);
  late final StreamSubscription<SpeechRecognitionResult> _fallbackPartials =
      _fallback.partialResults.listen(_partials.add);
  late final StreamSubscription<double> _platformAmplitude =
      _platform.amplitude.listen(_amplitude.add);
  late final StreamSubscription<double> _fallbackAmplitude =
      _fallback.amplitude.listen(_amplitude.add);
  late final StreamSubscription<SpeechRecognitionState> _platformStates =
      _platform.stateChanges.listen(_states.add);
  late final StreamSubscription<SpeechRecognitionState> _fallbackStates =
      _fallback.stateChanges.listen(_states.add);

  /// Which one answered last, so stop and cancel reach the right one.
  SpeechRecognitionService? _active;

  /// Per-locale answers, cached so the device is not asked on every turn.
  final Map<String, bool> _platformSupports = <String, bool>{};

  bool _wired = false;

  void _wire() {
    if (_wired) return;
    _wired = true;
    _platformPartials;
    _fallbackPartials;
    _platformAmplitude;
    _fallbackAmplitude;
  }

  /// True when the answer for this turn came from the development adapter, so
  /// the pipeline can stamp its measurements as a demo.
  bool get usingFallback => _active == _fallback;

  @override
  MicrophonePermission get permission =>
      (_active ?? _platform).permission;

  @override
  String? getCurrentLanguage() => _active?.getCurrentLanguage();

  @override
  Stream<SpeechRecognitionResult> get partialResults {
    _wire();
    return _partials.stream;
  }

  @override
  Stream<double> get amplitude {
    _wire();
    return _amplitude.stream;
  }

  @override
  Stream<SpeechRecognitionState> get stateChanges {
    _wire();
    return _states.stream;
  }

  @override
  Future<List<String>> supportedLanguages() async {
    _wire();
    final List<String> platform =
        await _platform.supportedLanguages();
    final List<String> fallback =
        await _fallback.supportedLanguages();
    return <String>{...platform, ...fallback}.toList()..sort();
  }

  Future<bool> _platformCan(String localeId) async {
    final bool? known = _platformSupports[localeId];
    if (known != null) return known;
    bool answer = false;
    try {
      answer = await _platform.isAvailable(localeId);
    } on Object catch (error) {
      AppLogger.error('recogniser availability check failed', error: error);
    }
    return _platformSupports[localeId] = answer;
  }

  @override
  Future<bool> isAvailable(String localeId) async =>
      await _platformCan(localeId) || await _fallback.isAvailable(localeId);

  @override
  Future<MicrophonePermission> requestPermission() async {
    // Asked of the device recogniser, because that is the one that needs the
    // microphone. The development adapter needs no permission at all.
    final MicrophonePermission granted = await _platform.requestPermission();
    if (granted == MicrophonePermission.granted) return granted;
    return _fallback.requestPermission();
  }

  @override
  Future<SpeechRecognitionResult> startListening({
    required String localeId,
    Duration? maxDuration,
  }) async {
    _wire();

    if (await _platformCan(localeId)) {
      _active = _platform;
      try {
        return await _platform.startListening(
          localeId: localeId,
          maxDuration: maxDuration,
        );
      } on SpeechRecognitionFailure catch (failure) {
        // A language the device turned out not to handle falls through; a
        // genuine listening failure does not, because retrying it with a mock
        // would hide a real problem behind fabricated words.
        if (failure.reason != SpeechFailureReason.languageUnsupported) rethrow;
        _platformSupports[localeId] = false;
      }
    }

    if (!await _fallback.isAvailable(localeId)) {
      _active = null;
      throw const SpeechRecognitionFailure(
        SpeechFailureReason.languageUnsupported,
        'Speech recognition for this language is not available on this device '
            'yet.',
      );
    }

    _active = _fallback;
    return _fallback.startListening(
      localeId: localeId,
      maxDuration: maxDuration,
    );
  }

  @override
  Future<void> stopListening() async => _active?.stopListening();

  @override
  Future<void> cancelListening() async {
    await _platform.cancelListening();
    await _fallback.cancelListening();
    _active = null;
  }

  @override
  Future<void> dispose() async {
    if (_wired) {
      await _platformPartials.cancel();
      await _fallbackPartials.cancel();
      await _platformAmplitude.cancel();
      await _fallbackAmplitude.cancel();
      await _platformStates.cancel();
      await _fallbackStates.cancel();
    }
    await _platform.dispose();
    await _fallback.dispose();
    await _partials.close();
    await _amplitude.close();
    await _states.close();
  }
}
