/// How long each stage of one voice-to-voice turn actually took.
///
/// Every field here is measured with a stopwatch around a real await. Nothing
/// in this class is estimated, and nothing is filled in with a plausible-looking
/// number: a stage that did not run reports [Duration.zero] and a turn that has
/// not finished has no metrics at all.
///
/// The product target is a total under three seconds. That target is checked
/// against [totalDuration] on a real device with real services; it is not
/// claimed anywhere in the UI on the strength of a development adapter.
class VoicePipelineMetrics {
  const VoicePipelineMetrics({
    required this.asrDuration,
    required this.translationDuration,
    required this.ttsDuration,
    required this.totalDuration,
    required this.timestamp,
    this.measuredWithMocks = false,
  });

  factory VoicePipelineMetrics.fromJson(Map<String, dynamic> json) =>
      VoicePipelineMetrics(
        asrDuration: Duration(milliseconds: json['asrMs'] as int),
        translationDuration: Duration(milliseconds: json['translationMs'] as int),
        ttsDuration: Duration(milliseconds: json['ttsMs'] as int),
        totalDuration: Duration(milliseconds: json['totalMs'] as int),
        timestamp: DateTime.parse(json['timestamp'] as String),
        measuredWithMocks: json['measuredWithMocks'] as bool? ?? false,
      );

  /// Speech capture end to recognised text.
  final Duration asrDuration;

  /// Recognised text to translated text.
  final Duration translationDuration;

  /// Translated text to audio ready to play.
  final Duration ttsDuration;

  /// Capture end to audio ready. This is the number the three-second target
  /// applies to.
  final Duration totalDuration;

  final DateTime timestamp;

  /// True when at least one stage was served by a development adapter, so the
  /// figure describes the app's own overhead rather than a real model.
  final bool measuredWithMocks;

  /// The product target for voice-to-voice latency.
  static const Duration target = Duration(seconds: 3);

  bool get withinTarget => totalDuration <= target;

  /// One decimal place, which is as precise as the number is meaningful.
  String get totalLabel =>
      '${(totalDuration.inMilliseconds / 1000).toStringAsFixed(1)} sec';

  Map<String, dynamic> toJson() => <String, dynamic>{
        'asrMs': asrDuration.inMilliseconds,
        'translationMs': translationDuration.inMilliseconds,
        'ttsMs': ttsDuration.inMilliseconds,
        'totalMs': totalDuration.inMilliseconds,
        'timestamp': timestamp.toIso8601String(),
        'measuredWithMocks': measuredWithMocks,
      };

  @override
  String toString() => 'VoicePipelineMetrics(total: $totalLabel, '
      'asr: ${asrDuration.inMilliseconds}ms, '
      'translation: ${translationDuration.inMilliseconds}ms, '
      'tts: ${ttsDuration.inMilliseconds}ms)';
}

/// Times one turn, stage by stage.
///
/// Deliberately dumb: it records the wall clock at each boundary and subtracts.
/// Timing that lives with the orchestrator rather than inside each service is
/// the only way the total can include the app's own overhead, which is exactly
/// the part this project can optimise.
class PipelineStopwatch {
  PipelineStopwatch({DateTime Function()? now})
      : _now = now ?? DateTime.now,
        _startedAt = (now ?? DateTime.now)();

  final DateTime Function() _now;
  final DateTime _startedAt;

  DateTime? _captureEnd;
  DateTime? _asrEnd;
  DateTime? _translationEnd;
  DateTime? _audioReady;

  /// The microphone closed; the measured window starts here.
  void speechCaptured() => _captureEnd = _now();

  void recognitionDone() => _asrEnd = _now();

  void translationDone() => _translationEnd = _now();

  void audioReadyNow() => _audioReady = _now();

  /// Null until the turn reaches audio-ready, because a partial turn has no
  /// total to report.
  VoicePipelineMetrics? build({bool measuredWithMocks = false}) {
    final DateTime? captureEnd = _captureEnd;
    final DateTime? audioReady = _audioReady;
    if (captureEnd == null || audioReady == null) return null;

    final DateTime asrEnd = _asrEnd ?? captureEnd;
    final DateTime translationEnd = _translationEnd ?? asrEnd;

    return VoicePipelineMetrics(
      asrDuration: asrEnd.difference(captureEnd),
      translationDuration: translationEnd.difference(asrEnd),
      ttsDuration: audioReady.difference(translationEnd),
      totalDuration: audioReady.difference(captureEnd),
      timestamp: _startedAt,
      measuredWithMocks: measuredWithMocks,
    );
  }
}
