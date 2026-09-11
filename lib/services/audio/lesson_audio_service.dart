// ignore_for_file: prefer_initializing_formals
// Private fields cannot be initialising formals: a named parameter may not
// start with an underscore.
import 'dart:async';

import 'package:path/path.dart' as p;

import '../../core/utils/app_logger.dart';
import '../../core/utils/result.dart';
import '../connectivity/connectivity_service.dart';
import 'audio_directory.dart';
import 'audio_resource_store.dart';
import 'clip_player.dart';
import 'text_to_speech_service.dart';

/// What the player is doing right now.
enum PlaybackState { idle, loading, playing, paused, completed, error }

/// How a passage will actually be voiced.
///
/// This is not decoration. Santali, Mundari and Ho have no voice in any Android
/// speech engine, so the honest answer for those languages is either a saved
/// clip, a clearly-labelled approximation, or nothing at all — and the UI shows
/// which one it is.
enum AudioVoiceKind {
  /// A clip saved on this device. Needs no connection and no engine.
  savedClip,

  /// The engine has a voice for this exact language.
  nativeVoice,

  /// No voice exists for the language, but the words are also written in
  /// Devanagari, which an Indic voice can pronounce. Recognisable, not native.
  approximateVoice,

  /// Nothing can voice this passage.
  none,
}

/// Whether a passage can be spoken, and with what.
class AudioAvailability {
  const AudioAvailability({
    required this.kind,
    this.note,
    this.blockedReason,
    this.saved = false,
  });

  final AudioVoiceKind kind;

  /// Shown beside the player when the voice is not the real thing.
  final String? note;

  /// Why nothing can be played, when nothing can.
  final String? blockedReason;

  /// True when a clip for this passage is on the device.
  final bool saved;

  bool get canPlay => kind != AudioVoiceKind.none;
}

/// A passage of text the teacher can hear.
class SpokenPassage {
  const SpokenPassage({
    required this.lessonId,
    required this.label,
    required this.displayText,
    required this.localeId,
    this.spokenText,
    this.spokenScriptLocaleId,
    this.textHash = '',
  });

  final String lessonId;

  /// The language's name, for labels and for the reason a voice is missing.
  final String label;

  /// What is on screen.
  final String displayText;

  /// The language's own locale, used to look for a native voice and to key the
  /// saved clip.
  final String localeId;

  /// The same words in a script an existing voice can pronounce. Null when
  /// there is no such form — in which case nothing is spoken, because handing
  /// Latin-script Santali to a Hindi voice produces noise, not Santali.
  final String? spokenText;

  /// The locale of the voice that can read [spokenText], e.g. `hi-IN` for
  /// Devanagari.
  final String? spokenScriptLocaleId;

  /// Distinguishes one sentence from another within the same lesson and
  /// language. Empty for a whole-lesson passage, where the lesson and the
  /// language are enough.
  final String textHash;

  /// True when this passage is in a language the engine may know directly.
  bool get hasOwnScript => spokenText == null;
}

/// Outcome of asking for playback.
sealed class AudioRequestOutcome {
  const AudioRequestOutcome();
}

final class AudioStarted extends AudioRequestOutcome {
  const AudioStarted(this.kind);

  final AudioVoiceKind kind;
}

/// Playback did not start, and the message says why in plain words.
final class AudioBlocked extends AudioRequestOutcome {
  const AudioBlocked(this.message);

  final String message;
}

final class AudioFailed extends AudioRequestOutcome {
  const AudioFailed(this.message);

  final String message;
}

/// Outcome of saving audio for offline use.
sealed class SaveAudioOutcome {
  const SaveAudioOutcome();
}

final class AudioSaved extends SaveAudioOutcome {
  const AudioSaved(this.resource);

  final AudioResource resource;
}

final class AudioAlreadySaved extends SaveAudioOutcome {
  const AudioAlreadySaved(this.resource);

  final AudioResource resource;
}

final class SaveBlocked extends SaveAudioOutcome {
  const SaveBlocked(this.message);

  final String message;
}

final class SaveFailed extends SaveAudioOutcome {
  const SaveFailed(this.message);

  final String message;
}

/// Playback speeds the classroom needs. Slow is for pupils, not for effect.
enum AudioSpeed {
  normal(multiplier: 1.0, label: 'Normal'),
  slow(multiplier: 0.75, label: '0.75x');

  const AudioSpeed({required this.multiplier, required this.label});

  final double multiplier;
  final String label;
}

/// Plays a lesson passage aloud.
///
/// One interface over two very different sources — a saved file and the
/// device's speech engine — so the screen has a single play button and no idea
/// which one answered.
abstract interface class LessonAudioService {
  PlaybackState get state;

  AudioSpeed get speed;

  /// Emits on every state change, so the UI never polls.
  Stream<PlaybackState> get states;

  /// How far through the current passage playback is, 0..1.
  ///
  /// Only ever a position the engine or the player actually reported. When
  /// neither reports one it stays at zero, and the waveform shows activity
  /// rather than inventing a position.
  Stream<double> get progress;

  double get progressValue;

  /// What could voice this passage, and whether a clip is already saved.
  Future<AudioAvailability> availability(SpokenPassage passage);

  Future<AudioRequestOutcome> play(SpokenPassage passage);

  /// Restarts from the beginning, whether it is playing, paused or finished.
  Future<AudioRequestOutcome> repeat(SpokenPassage passage);

  Future<void> pause();

  Future<void> stop();

  /// Applies immediately if something is playing, by restarting it: a speech
  /// engine cannot change rate mid-utterance.
  Future<void> setSpeed(AudioSpeed speed, {SpokenPassage? current});

  /// Writes the clip to the device so it plays with no connection.
  Future<SaveAudioOutcome> save(SpokenPassage passage);

  Future<void> dispose();
}

/// The real player: a saved clip if there is one, the speech engine otherwise.
///
/// Resolution order, and the reason for it:
///
///   saved clip      -> a fixed recording beats a re-synthesis, and needs
///                      neither engine nor connection
///   native voice    -> the engine can speak this language properly
///   Devanagari form -> no native voice, but the words are also written in a
///                      script an Indic voice can read; labelled as approximate
///   nothing         -> say so
class TtsLessonAudioService implements LessonAudioService {
  TtsLessonAudioService({
    required TextToSpeechService tts,
    required AudioResourceStore store,
    required ConnectivityService connectivity,
    ClipPlayer? player,
  })  : _tts = tts,
        _store = store,
        _connectivity = connectivity,
        _player = player ?? AudioPlayersClipPlayer() {
    _speechSubscription = _tts.events.listen(_onSpeechEvent);
    _speechProgressSubscription = _tts.progress.listen((double value) {
      if (_activeKind != AudioVoiceKind.savedClip) _setProgress(value);
    });
    try {
      _playerSubscription = _player.onComplete.listen((void _) {
        _setProgress(1);
        _set(PlaybackState.completed);
      });
      _playerPositionSubscription =
          _player.onPosition.listen((Duration position) {
        final Duration? total = _clipDuration;
        if (total == null || total.inMilliseconds <= 0) return;
        _setProgress(position.inMilliseconds / total.inMilliseconds);
      });
      _playerDurationSubscription = _player.onDuration.listen(
        (Duration total) => _clipDuration = total,
      );
    } on Object catch (error) {
      AppLogger.error('audio player events unavailable', error: error);
    }
  }

  final TextToSpeechService _tts;
  final AudioResourceStore _store;
  final ConnectivityService _connectivity;
  final ClipPlayer _player;

  StreamSubscription<SpeechEvent>? _speechSubscription;
  StreamSubscription<double>? _speechProgressSubscription;
  StreamSubscription<void>? _playerSubscription;
  StreamSubscription<Duration>? _playerPositionSubscription;
  StreamSubscription<Duration>? _playerDurationSubscription;

  final StreamController<PlaybackState> _states =
      StreamController<PlaybackState>.broadcast();
  final StreamController<double> _progress =
      StreamController<double>.broadcast();

  /// Length of the saved clip currently loaded, so a position can be turned
  /// into a fraction. Null until the player reports one.
  Duration? _clipDuration;

  double _progressValue = 0;

  PlaybackState _state = PlaybackState.idle;
  AudioSpeed _speed = AudioSpeed.normal;

  /// Which backend is currently sounding, so pause and stop go to the right
  /// one.
  AudioVoiceKind? _activeKind;

  @override
  PlaybackState get state => _state;

  @override
  AudioSpeed get speed => _speed;

  @override
  Stream<PlaybackState> get states => _states.stream;

  @override
  Stream<double> get progress => _progress.stream;

  @override
  double get progressValue => _progressValue;

  void _set(PlaybackState next) {
    if (_state == next) return;
    _state = next;
    if (next == PlaybackState.idle || next == PlaybackState.loading) {
      _setProgress(0);
    }
    if (!_states.isClosed) _states.add(next);
  }

  void _setProgress(double value) {
    final double clamped = value.clamp(0.0, 1.0);
    if ((clamped - _progressValue).abs() < 0.005 && clamped != 0) return;
    _progressValue = clamped;
    if (!_progress.isClosed) _progress.add(clamped);
  }

  void _onSpeechEvent(SpeechEvent event) {
    if (_activeKind == AudioVoiceKind.savedClip) return;
    switch (event) {
      case SpeechEvent.started || SpeechEvent.continued:
        _set(PlaybackState.playing);
      case SpeechEvent.completed:
        _set(PlaybackState.completed);
      case SpeechEvent.paused:
        _set(PlaybackState.paused);
      case SpeechEvent.cancelled:
        _set(PlaybackState.idle);
      case SpeechEvent.failed:
        _set(PlaybackState.error);
    }
  }

  @override
  Future<AudioAvailability> availability(SpokenPassage passage) async {
    final AudioResource? saved = await _store.find(
      passage.lessonId,
      passage.localeId,
      passage.textHash,
    );
    if (saved != null) {
      return const AudioAvailability(
        kind: AudioVoiceKind.savedClip,
        saved: true,
        note: 'Saved on this device',
      );
    }

    if (await _tts.isLanguageAvailable(passage.localeId)) {
      return const AudioAvailability(kind: AudioVoiceKind.nativeVoice);
    }

    final String? spoken = passage.spokenText;
    final String? scriptLocale = passage.spokenScriptLocaleId;
    if (spoken != null &&
        spoken.trim().isNotEmpty &&
        scriptLocale != null &&
        await _tts.isLanguageAvailable(scriptLocale)) {
      return AudioAvailability(
        kind: AudioVoiceKind.approximateVoice,
        note: 'Approximate voice — no ${passage.label} voice on this device '
            'yet, so an Indic voice reads the Devanagari spelling.',
      );
    }

    return AudioAvailability(
      kind: AudioVoiceKind.none,
      blockedReason:
          'Audio in ${passage.label} is not available on this device yet.',
    );
  }

  @override
  Future<AudioRequestOutcome> play(SpokenPassage passage) async {
    // Only stop something that is actually sounding. Calling stop immediately
    // before speak makes some engines cancel the utterance that follows it.
    if (_state == PlaybackState.playing ||
        _state == PlaybackState.paused) {
      await stop();
    }
    _set(PlaybackState.loading);

    final AudioAvailability availability = await this.availability(passage);

    switch (availability.kind) {
      case AudioVoiceKind.savedClip:
        return _playSavedClip(passage);
      case AudioVoiceKind.nativeVoice:
        return _speak(
          passage.displayText,
          localeId: passage.localeId,
          kind: AudioVoiceKind.nativeVoice,
        );
      case AudioVoiceKind.approximateVoice:
        return _speak(
          passage.spokenText!,
          localeId: passage.spokenScriptLocaleId!,
          kind: AudioVoiceKind.approximateVoice,
        );
      case AudioVoiceKind.none:
        _set(PlaybackState.idle);
        return AudioBlocked(
          availability.blockedReason ??
              'Audio in ${passage.label} is not available on this device yet.',
        );
    }
  }

  Future<AudioRequestOutcome> _playSavedClip(SpokenPassage passage) async {
    final AudioResource? saved = await _store.find(
      passage.lessonId,
      passage.localeId,
      passage.textHash,
    );
    if (saved == null) {
      _set(PlaybackState.idle);
      return const AudioBlocked('The saved audio could not be found.');
    }
    try {
      _activeKind = AudioVoiceKind.savedClip;
      await _player.setRate(_speed.multiplier);
      await _player.playFile(saved.filePath);
      _set(PlaybackState.playing);
      return const AudioStarted(AudioVoiceKind.savedClip);
    } on Object catch (error) {
      // The record outlived its file. Drop the record so the next attempt
      // falls through to the engine instead of failing the same way forever.
      AppLogger.error('saved clip could not be played', error: error);
      await _store.remove(
        passage.lessonId,
        passage.localeId,
        passage.textHash,
      );
      _activeKind = null;
      _set(PlaybackState.error);
      return const AudioFailed("Couldn't play the audio.");
    }
  }

  Future<AudioRequestOutcome> _speak(
    String text, {
    required String localeId,
    required AudioVoiceKind kind,
  }) async {
    _activeKind = kind;
    await _tts.setSpeedMultiplier(_speed.multiplier);
    final Result<void> result = await _tts.speak(text, localeId: localeId);

    if (result is Err<void>) {
      _activeKind = null;
      _set(PlaybackState.error);
      return const AudioFailed("Couldn't play the audio.");
    }

    // The engine's own start callback will confirm this; setting it here keeps
    // the button responsive on engines that report late.
    _set(PlaybackState.playing);
    return AudioStarted(kind);
  }

  @override
  Future<AudioRequestOutcome> repeat(SpokenPassage passage) async {
    // Replaying is starting again from zero, whatever the current state is.
    await stop();
    return play(passage);
  }

  @override
  Future<void> pause() async {
    if (_state != PlaybackState.playing) return;
    if (_activeKind == AudioVoiceKind.savedClip) {
      try {
        await _player.pause();
      } on Object catch (error) {
        AppLogger.error('audio could not be paused', error: error);
      }
    } else {
      await _tts.pause();
    }
    _set(PlaybackState.paused);
  }

  @override
  Future<void> stop() async {
    try {
      await _player.stop();
    } on Object {
      // Stopping a player that never started is not an error.
    }
    await _tts.stop();
    _activeKind = null;
    _set(PlaybackState.idle);
  }

  @override
  Future<void> setSpeed(AudioSpeed speed, {SpokenPassage? current}) async {
    _speed = speed;
    await _tts.setSpeedMultiplier(speed.multiplier);
    try {
      await _player.setRate(speed.multiplier);
    } on Object {
      // Rate is applied again at play time, so a refusal here is not fatal.
    }

    // A speech engine cannot change rate part-way through an utterance, so the
    // only honest way to apply a new speed to sound already playing is to start
    // it again at the new rate.
    if (current != null && _state == PlaybackState.playing) {
      await play(current);
    }
  }

  @override
  Future<SaveAudioOutcome> save(SpokenPassage passage) async {
    final AudioResource? existing = await _store.find(
      passage.lessonId,
      passage.localeId,
      passage.textHash,
    );
    if (existing != null) return AudioAlreadySaved(existing);

    if (!_tts.canSynthesiseToFile) {
      return const SaveBlocked(
        'Saving audio needs the phone app. The browser cannot write the clip '
        'to the device.',
      );
    }

    final String text = passage.spokenText ?? passage.displayText;
    if (text.trim().isEmpty) {
      return const SaveBlocked('There is nothing to save for this lesson yet.');
    }

    final AudioAvailability availability = await this.availability(passage);
    if (!availability.canPlay) {
      return SaveBlocked(
        availability.blockedReason ??
            'Audio in ${passage.label} is not available on this device yet.',
      );
    }

    final String localeId = availability.kind == AudioVoiceKind.approximateVoice
        ? passage.spokenScriptLocaleId!
        : passage.localeId;

    try {
      final String? directory = await resolveAudioDirectory();
      if (directory == null) {
        return const SaveBlocked(
          'This device has nowhere to keep the audio file.',
        );
      }
      final String suffix =
          passage.textHash.isEmpty ? '' : '_${passage.textHash}';
      final String filePath = p.join(
        directory,
        'lesson_${passage.lessonId}_${passage.localeId}$suffix.wav',
      );

      final Result<String> written = await _tts.synthesiseToFile(
        text,
        localeId: localeId,
        filePath: filePath,
      );

      return switch (written) {
        Ok<String>(:final String value) => AudioSaved(
            await _record(passage, value),
          ),
        Err<String>() => const SaveFailed(
            "Couldn't save audio for offline use.",
          ),
      };
    } on Object catch (error) {
      AppLogger.error('audio save failed', error: error);
      return const SaveFailed("Couldn't save audio for offline use.");
    }
  }

  Future<AudioResource> _record(SpokenPassage passage, String path) async {
    final AudioResource resource = AudioResource(
      audioResourceId:
          'audio-${passage.lessonId}-${passage.localeId}-${passage.textHash}',
      lessonId: passage.lessonId,
      localeId: passage.localeId,
      textHash: passage.textHash,
      filePath: path,
      createdAt: DateTime.now(),
    );
    await _store.save(resource);
    return resource;
  }

  /// Exposed so the screen can explain why a first synthesis may need a
  /// connection on engines whose voices are not installed offline.
  ConnectionStatus get connection => _connectivity.status;

  @override
  Future<void> dispose() async {
    await _speechSubscription?.cancel();
    await _speechProgressSubscription?.cancel();
    await _playerSubscription?.cancel();
    await _playerPositionSubscription?.cancel();
    await _playerDurationSubscription?.cancel();
    try {
      await _player.dispose();
    } on Object {
      // Nothing to release if the player never initialised.
    }
    await _tts.dispose();
    await _states.close();
    await _progress.close();
  }
}
