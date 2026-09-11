import 'dart:async';

import 'package:audioplayers/audioplayers.dart';

import '../../core/utils/app_logger.dart';

/// Plays an audio file that is already on the device.
///
/// A narrow interface over the audio plugin. It exists so the lesson audio
/// service can be built without a platform channel — a test that constructs a
/// real player has to wait for method calls that will never be answered — and
/// so the plugin can be swapped without touching anything above it.
abstract interface class ClipPlayer {
  /// Fires when the clip reaches its end.
  Stream<void> get onComplete;

  Stream<Duration> get onPosition;

  Stream<Duration> get onDuration;

  Future<void> playFile(String path);

  Future<void> pause();

  Future<void> stop();

  Future<void> setRate(double rate);

  Future<void> dispose();
}

/// The real player, backed by `audioplayers`.
class AudioPlayersClipPlayer implements ClipPlayer {
  AudioPlayersClipPlayer([AudioPlayer? player])
      : _player = player ?? AudioPlayer();

  final AudioPlayer _player;

  @override
  Stream<void> get onComplete => _player.onPlayerComplete;

  @override
  Stream<Duration> get onPosition => _player.onPositionChanged;

  @override
  Stream<Duration> get onDuration => _player.onDurationChanged;

  @override
  Future<void> playFile(String path) async {
    AppLogger.debug('voice: AudioPlayer.play() started -> $path');
    try {
      await _player.play(DeviceFileSource(path));
      AppLogger.debug('voice: AudioPlayer.play() success');
    } on Object catch (error) {
      AppLogger.error('voice: AudioPlayer.play() failure', error: error);
      rethrow;
    }
  }

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> stop() => _player.stop();

  @override
  Future<void> setRate(double rate) => _player.setPlaybackRate(rate);

  @override
  Future<void> dispose() async {
    try {
      await _player.dispose();
    } on Object catch (error) {
      AppLogger.error('audio player could not be released', error: error);
    }
  }
}
