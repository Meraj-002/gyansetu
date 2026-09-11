// ignore_for_file: prefer_initializing_formals
// Private fields cannot be initialising formals: a named parameter may not
// start with an underscore.
import 'package:record/record.dart' as record;

import '../../core/utils/app_logger.dart';
import 'audio_recorder.dart';

/// The device microphone recorder, backed by the `record` package.
///
/// Records to PCM WAV because that is the container the Adi Vaani provider
/// speaks back: one recording format in, the same format out. The encoder is
/// picked at construction so tests can substitute a decoder-free build and the
/// engine can be swapped behind the [AudioRecorder] interface.
class RecordAudioRecorder implements AudioRecorder {
  RecordAudioRecorder({int sampleRate = 16000})
      : _sampleRate = sampleRate,
        _recorder = record.AudioRecorder();

  final int _sampleRate;
  final record.AudioRecorder _recorder;

  static const record.AudioEncoder _encoder = record.AudioEncoder.wav;

  @override
  Future<bool> hasPermission() => _recorder.hasPermission();

  @override
  Future<void> startRecording({required String targetPath}) async {
    try {
      await _recorder.start(
        record.RecordConfig(
          encoder: _encoder,
          sampleRate: _sampleRate,
          numChannels: 1,
          bitRate: 32000,
        ),
        path: targetPath,
      );
    } on Object catch (error) {
      AppLogger.error('mic could not start recording', error: error);
      throw AudioRecorderException("The microphone couldn't be started.");
    }
  }

  @override
  Future<String?> stopRecording() async {
    try {
      return await _recorder.stop();
    } on Object catch (error) {
      AppLogger.error('mic could not stop recording', error: error);
      return null;
    }
  }

  @override
  Future<void> dispose() async {
    try {
      await _recorder.dispose();
    } on Object catch (error) {
      AppLogger.error('mic recorder could not be released', error: error);
    }
  }
}