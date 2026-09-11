import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

import '../../core/errors/app_exception.dart';
import '../../core/models/app_language.dart';
import '../../core/utils/app_logger.dart';
import '../../core/utils/result.dart';

/// What the speech engine reported while speaking.
enum SpeechEvent { started, completed, paused, continued, cancelled, failed }

/// Contract for reading text aloud.
///
/// NOTE: Android's bundled TTS engines cover Hindi but carry no Santali,
/// Mundari or Ho voice. [isLanguageAvailable] is therefore load-bearing rather
/// than informational: the audio layer asks it before offering to speak, and
/// says the language has no voice when it does not, instead of reading tribal
/// text with a Hindi voice and calling it Santali.
abstract interface class TextToSpeechService {
  /// Locale ids the engine can speak, e.g. `hi-IN`.
  Future<Result<List<String>>> availableLanguages();

  /// Whether this exact locale can be spoken on this device.
  Future<bool> isLanguageAvailable(String localeId);

  /// Emits as the engine starts, finishes, is paused or fails.
  Stream<SpeechEvent> get events;

  /// How far through the utterance the engine is, 0..1.
  ///
  /// Real position reported by the engine, not a timer: an engine that does not
  /// report progress simply never emits, and the UI shows no position rather
  /// than a made-up one.
  Stream<double> get progress;

  Future<Result<void>> speak(String text, {required String localeId});

  /// Whether a currently-paused utterance can actually be resumed on this
  /// engine. Honest capability, checked before the UI shows a resume control:
  /// flutter_tts on Android exposes pause but no working resume, and claiming
  /// one would leave a dead button and a teacher's live class stuck mid-word.
  bool get canPause;

  /// Whether a paused utterance can actually be resumed on this engine. See
  /// [canPause].
  bool get canResume;

  Future<Result<void>> pause();

  /// Resumes a paused utterance, or returns an error on engines where
  /// resuming is not possible ([canResume] is false).
  Future<Result<void>> resume();

  Future<Result<void>> stop();

  /// A multiplier on the engine's normal rate: 1.0 is normal, 0.75 is slow.
  /// The platform's own scale is not exposed, because it differs per platform.
  Future<Result<void>> setSpeedMultiplier(double multiplier);

  /// Renders [text] to a file at [filePath]. Returns the path on success.
  ///
  /// Not every platform can do this; [canSynthesiseToFile] says so up front so
  /// the UI never offers a save it cannot perform.
  bool get canSynthesiseToFile;

  Future<Result<String>> synthesiseToFile(
    String text, {
    required String localeId,
    required String filePath,
  });

  Future<void> dispose();
}

/// Speech through the platform's own engine, via `flutter_tts`.
///
/// Everything here is a real call into a real engine: [speak] produces sound,
/// [pause] and [stop] act on it, the speed multiplier changes the delivered
/// rate, and completion arrives from the engine's own callback rather than a
/// timer guessing when the audio ended.
class PlatformTextToSpeechService implements TextToSpeechService {
  PlatformTextToSpeechService([FlutterTts? tts]) : _tts = tts ?? FlutterTts() {
    _attachHandlers();
  }

  /// The platform's own value for "normal speed".
  ///
  /// Android and iOS take 0.0–1.0 with 0.5 as normal; the web speech API takes
  /// a rate around 1.0. The multiplier the app talks in is scaled onto whichever
  /// applies, so "Slow" means the same thing everywhere.
  static double get normalRate {
    if (kIsWeb) return 1.0;
    return switch (defaultTargetPlatform) {
      TargetPlatform.android || TargetPlatform.iOS => 0.5,
      _ => 1.0,
    };
  }

  @override
  Future<bool> isLanguageAvailable(String localeId) async {
    // Santali, Mundari and Ho have no voice in any engine. That is a known
    // fact about the world, owned by the canonical language model rather than a
    // second hard-coded list here, and it holds whatever the engine reports.
    final AppLanguage? language = AppLanguage.byCodeStatic(localeId);
    if (language != null && !language.capabilities.hasKnownTtsVoice) {
      return false;
    }

    final List<String> languages = await _resolveLanguages();
    if (languages.isNotEmpty) return _matches(languages, localeId);

    // The engine could not list anything. Absence of a list is not evidence of
    // absence of a voice, so the attempt is allowed and a real failure is
    // reported by the engine's own error handler rather than guessed at here.
    try {
      final dynamic available = await _tts.isLanguageAvailable(localeId);
      if (available == true) return true;
    } on Object {
      // Falls through to the optimistic answer below.
    }
    AppLogger.error(
      'speech engine listed no languages; attempting $localeId anyway',
    );
    return true;
  }

  final FlutterTts _tts;
  List<String>? _languages;

  final StreamController<SpeechEvent> _events =
      StreamController<SpeechEvent>.broadcast();
  final StreamController<double> _progress =
      StreamController<double>.broadcast();

  bool _handlersAttached = false;

  @override
  Stream<SpeechEvent> get events => _events.stream;

  @override
  Stream<double> get progress => _progress.stream;

  @override
  bool get canSynthesiseToFile => !kIsWeb;

  // flutter_tts exposes pause, but resume is only reachable through `speak()`
  // again on some platforms and pulls the state out from under the UI. The
  // control that would call it is not shown: honest capability over a broken
  // one.
  @override
  bool get canPause => true;

  @override
  bool get canResume =>
      // The Dart API has no resume method (flutter_tts 4.2.5), so resuming is
      // genuinely not possible from this adapter.
      false;

  void _attachHandlers() {
    if (_handlersAttached) return;
    _handlersAttached = true;
    try {
      _tts
        ..setStartHandler(() => _emit(SpeechEvent.started))
        ..setCompletionHandler(() => _emit(SpeechEvent.completed))
        ..setCancelHandler(() => _emit(SpeechEvent.cancelled))
        ..setPauseHandler(() => _emit(SpeechEvent.paused))
        ..setContinueHandler(() => _emit(SpeechEvent.continued))
        ..setErrorHandler((dynamic message) {
          AppLogger.error('speech engine error', error: message);
          _emit(SpeechEvent.failed);
        })
        ..setProgressHandler((String text, int start, int end, String word) {
          if (text.isEmpty || _progress.isClosed) return;
          _progress.add((end / text.length).clamp(0.0, 1.0));
        });
    } on Object catch (error) {
      // No platform channel — a widget test, or a host with no engine. The
      // service stays usable and simply reports failures.
      AppLogger.error('speech handlers could not be attached', error: error);
    }
  }

  void _emit(SpeechEvent event) {
    if (!_events.isClosed) _events.add(event);
    if (event == SpeechEvent.started && !_progress.isClosed) {
      _progress.add(0);
    }
  }

  @override
  Future<Result<List<String>>> availableLanguages() async =>
      Ok<List<String>>(await _resolveLanguages());

  /// The engine's own language list, read once and kept.
  ///
  /// Retried because of the browser: `speechSynthesis.getVoices()` populates
  /// asynchronously and the first call after a page load returns an empty list.
  /// Treating that first empty answer as "no voices" is what silently stopped
  /// every play button from doing anything on the web.
  Future<List<String>> _resolveLanguages() async {
    final List<String>? held = _languages;
    if (held != null && held.isNotEmpty) return held;

    for (int attempt = 0; attempt < 3; attempt++) {
      try {
        final dynamic languages = await _tts.getLanguages;
        final List<String> found = <String>[
          for (final dynamic l
              in languages as List<dynamic>? ?? const <dynamic>[])
            '$l',
        ];
        if (found.isNotEmpty) return _languages = found;
      } on Object catch (error) {
        AppLogger.error('speech languages could not be read', error: error);
      }
      if (attempt < 2) {
        await Future<void>.delayed(const Duration(milliseconds: 250));
      }
    }
    return _languages = const <String>[];
  }

  /// Matches loosely: engines report `hi-IN`, `hi_IN` or plain `hi`, and an
  /// exact string comparison against one of those spellings answered "no" for
  /// a voice that was installed.
  static bool _matches(List<String> available, String localeId) {
    final String wanted = localeId.toLowerCase().replaceAll('_', '-');
    final String language = wanted.split('-').first;
    for (final String entry in available) {
      final String id = entry.toLowerCase().replaceAll('_', '-');
      if (id == wanted || id.split('-').first == language) return true;
    }
    return false;
  }

  @override
  Future<Result<void>> speak(String text, {required String localeId}) async {
    if (text.trim().isEmpty) {
      return Err<void>(const AudioException('There is nothing to read aloud'));
    }
    try {
      // The engine's own spelling of the locale where it has one, so
      // `setLanguage` is not handed a string it does not recognise.
      await _tts.setLanguage(await _engineLocaleFor(localeId));
      await _tts.speak(text);
      return const Ok<void>(null);
    } on Object catch (error) {
      AppLogger.error('speech failed', error: error);
      return Err<void>(
        AudioException('The audio could not be played', cause: error),
      );
    }
  }

  /// The engine's spelling of [localeId], or [localeId] unchanged when the
  /// engine has not told us what it calls it.
  Future<String> _engineLocaleFor(String localeId) async {
    final List<String> languages = await _resolveLanguages();
    final String wanted = localeId.toLowerCase().replaceAll('_', '-');
    final String language = wanted.split('-').first;

    for (final String entry in languages) {
      if (entry.toLowerCase().replaceAll('_', '-') == wanted) return entry;
    }
    for (final String entry in languages) {
      if (entry.toLowerCase().replaceAll('_', '-').split('-').first ==
          language) {
        return entry;
      }
    }
    return localeId;
  }

  @override
  Future<Result<void>> pause() async {
    try {
      await _tts.pause();
      return const Ok<void>(null);
    } on Object catch (error) {
      return Err<void>(
        AudioException('The audio could not be paused', cause: error),
      );
    }
  }

  @override
  Future<Result<void>> resume() async {
    // No API to call, and this is load-bearing: returning Ok here would let the
    // teacher's play control continue a paused Santali sentence with a fake.
    return const Err<void>(
      AudioException('Resuming audio is not possible with this engine'),
    );
  }

  @override
  Future<Result<void>> stop() async {
    try {
      await _tts.stop();
      return const Ok<void>(null);
    } on Object catch (error) {
      return Err<void>(
        AudioException('The audio could not be stopped', cause: error),
      );
    }
  }

  @override
  Future<Result<void>> setSpeedMultiplier(double multiplier) async {
    try {
      await _tts.setSpeechRate(normalRate * multiplier);
      return const Ok<void>(null);
    } on Object catch (error) {
      return Err<void>(
        AudioException('The playback speed could not be changed', cause: error),
      );
    }
  }

  @override
  Future<Result<String>> synthesiseToFile(
    String text, {
    required String localeId,
    required String filePath,
  }) async {
    if (!canSynthesiseToFile) {
      return Err<String>(
        const AudioException('This platform cannot write audio to a file'),
      );
    }
    try {
      await _tts.setLanguage(await _engineLocaleFor(localeId));
      await _tts.awaitSynthCompletion(true);
      await _tts.synthesizeToFile(text, filePath, true);
      return Ok<String>(filePath);
    } on Object catch (error) {
      AppLogger.error('audio could not be written to a file', error: error);
      return Err<String>(
        AudioException('The audio could not be saved', cause: error),
      );
    }
  }

  @override
  Future<void> dispose() async {
    try {
      await _tts.stop();
    } on Object {
      // Stopping a engine that never started is not an error worth reporting.
    }
    await _events.close();
    await _progress.close();
  }
}
