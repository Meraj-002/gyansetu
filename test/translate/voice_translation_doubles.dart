import 'dart:async';

import 'package:gyan_setu_ai/services/audio/audio_recorder.dart';
import 'package:gyan_setu_ai/services/audio/clip_player.dart';
import 'package:gyan_setu_ai/services/translation/voice_translation_service.dart';

/// A scripted [AudioRecorder]: permission can be granted or refused, and the
/// clip is "recorded" to a canned path.
class FakeAudioRecorder implements AudioRecorder {
  FakeAudioRecorder({
    required this.permitted,
    this.outputPath,
  });

  final bool permitted;
  final String? outputPath;

  bool started = false;
  bool stopped = false;
  String? startedPath;

  @override
  Future<bool> hasPermission() async => permitted;

  @override
  Future<void> startRecording({required String targetPath}) async {
    started = true;
    startedPath = targetPath;
  }

  @override
  Future<String?> stopRecording() async {
    stopped = true;
    return outputPath;
  }

  @override
  Future<void> dispose() async {}
}

/// A scripted [VoiceTranslationService] whose answer (or error) the test
/// chooses.
class FakeVoiceTranslationService implements VoiceTranslationService {
  FakeVoiceTranslationService({required this.direction});

  /// Receives the uploaded audio path, returns the result or throws.
  final VoiceTranslationResult Function(String audioPath) direction;

  final List<String> uploaded = <String>[];

  @override
  Future<VoiceTranslationResult> translateVoice({
    required String audioPath,
  }) async {
    uploaded.add(audioPath);
    return direction(audioPath);
  }
}

/// A scripted [ClipPlayer] recording what was asked to play.
class FakeClipPlayer implements ClipPlayer {
  final StreamController<void> _complete = StreamController<void>.broadcast();

  final List<String> played = <String>[];

  @override
  Stream<void> get onComplete => _complete.stream;

  @override
  Stream<Duration> get onPosition => const Stream<Duration>.empty();

  @override
  Stream<Duration> get onDuration => const Stream<Duration>.empty();

  @override
  Future<void> playFile(String path) async => played.add(path);

  @override
  Future<void> pause() async {}

  @override
  Future<void> stop() async {}

  @override
  Future<void> setRate(double rate) async {}

  @override
  Future<void> dispose() async => _complete.close();
}