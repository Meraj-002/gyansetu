import 'dart:async';

import 'speech_recognition_service.dart';

/// DEVELOPMENT MOCK ONLY.
/// Replace with a real ASR implementation — either
/// [PlatformSpeechRecognitionService] where the device has a recogniser, or a
/// server- or model-backed one for the tribal languages, which no device
/// recogniser covers.
///
/// This class does NOT listen to a microphone. It returns a scripted sentence
/// so the rest of the pipeline — translation, synthesis, timeline, latency —
/// can be exercised end to end on a machine with no recogniser. Anything it
/// produces is marked as coming from a mock, all the way through to the latency
/// badge, so a demo can never be mistaken for a working recogniser.
///
/// It adds no artificial delay. The latency it contributes is the app's own
/// overhead and nothing else, because a padded number would be worse than
/// useless when the point of the measurement is to find real overhead.
class DevelopmentSpeechRecognitionService implements SpeechRecognitionService {
  DevelopmentSpeechRecognitionService({
    Map<String, List<String>>? script,
    this.listenWindow = const Duration(milliseconds: 900),
  }) : _script = script ?? _defaultScript;

  /// Scripted sentences per source locale, cycled through in order.
  final Map<String, List<String>> _script;

  /// How long the microphone appears open for, so the listening state is
  /// visible. This is stage-setting for a demo, not a measured stage: the
  /// pipeline stopwatch starts only when this window closes.
  final Duration listenWindow;

  static const Map<String, List<String>> _defaultScript =
      <String, List<String>>{
    'hi-IN': <String>[
      'बच्चों, कितने आम हैं?',
      'अब हम एक से दस तक गिनेंगे।',
      'सब बच्चे पाँच पत्थर उठाओ।',
    ],
    'sat': <String>["Horoko, kete aam achhe?", "Mit', bar, pe."],
    'unr': <String>['Honko, chikan menaia?'],
    'hoc': <String>['Honko, chikan menaia?'],
  };

  final StreamController<SpeechRecognitionResult> _partials =
      StreamController<SpeechRecognitionResult>.broadcast();
  final StreamController<double> _amplitude =
      StreamController<double>.broadcast();
  final StreamController<SpeechRecognitionState> _states =
      StreamController<SpeechRecognitionState>.broadcast();

  final Map<String, int> _cursor = <String, int>{};
  MicrophonePermission _permission = MicrophonePermission.notRequested;
  String? _currentLocale;
  Timer? _timer;
  Completer<SpeechRecognitionResult>? _pending;
  SpeechRecognitionState _state = SpeechRecognitionState.idle;

  /// Identifies this as a mock to anything that reports pipeline provenance.
  static const bool isMock = true;

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

  @override
  Future<bool> isAvailable(String localeId) async =>
      _script.containsKey(localeId);

  @override
  Future<List<String>> supportedLanguages() async =>
      _script.keys.toList()..sort();

  @override
  Future<MicrophonePermission> requestPermission() async =>
      _permission = MicrophonePermission.granted;

  @override
  Future<SpeechRecognitionResult> startListening({
    required String localeId,
    Duration? maxDuration,
  }) async {
    final List<String>? lines = _script[localeId];
    if (lines == null || lines.isEmpty) {
      throw SpeechRecognitionFailure(
        SpeechFailureReason.languageUnsupported,
        'Speech recognition for this language is not available on this '
            'device yet.',
      );
    }

    await cancelListening();
    _currentLocale = localeId;
    _permission = MicrophonePermission.granted;
    _setState(SpeechRecognitionState.listening);

    final int index = (_cursor[localeId] ?? 0) % lines.length;
    _cursor[localeId] = index + 1;
    final String text = lines[index];

    final Completer<SpeechRecognitionResult> pending =
        Completer<SpeechRecognitionResult>();
    _pending = pending;

    _timer = Timer(listenWindow, () => _finish(text, localeId));
    return pending.future;
  }

  void _finish(String text, String localeId) {
    final Completer<SpeechRecognitionResult>? pending = _pending;
    if (pending == null || pending.isCompleted) return;
    _pending = null;
    _timer = null;
    _currentLocale = null;

    _setState(SpeechRecognitionState.completed);

    if (!_partials.isClosed) {
      _partials.add(
        SpeechRecognitionResult(
          text: text,
          localeId: localeId,
          isFinal: true,
          // No confidence is reported, because a mock has none to report.
        ),
      );
    }
    pending.complete(
      SpeechRecognitionResult(text: text, localeId: localeId, isFinal: true),
    );
  }

  @override
  Future<void> stopListening() async {
    _timer?.cancel();
    final String? locale = _currentLocale;
    final List<String>? lines = locale == null ? null : _script[locale];
    if (lines != null && lines.isNotEmpty) {
      final int index = ((_cursor[locale] ?? 1) - 1) % lines.length;
      _finish(lines[index], locale!);
    }
  }

  @override
  Future<void> cancelListening() async {
    _timer?.cancel();
    _timer = null;
    final Completer<SpeechRecognitionResult>? pending = _pending;
    _pending = null;
    _currentLocale = null;
    _setState(SpeechRecognitionState.idle);
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
