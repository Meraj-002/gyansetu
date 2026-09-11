import 'package:flutter/services.dart' show rootBundle;

import '../../features/setup/models/classroom_setup.dart';

/// Why a phrase could not be played.
enum AudioUnavailableReason {
  /// No recording is bundled and no voice exists for the language.
  noVoice,

  /// A voice exists but the platform refused to play.
  playbackFailed,
}

/// Outcome of asking for a spoken sample.
sealed class AudioPlaybackResult {
  const AudioPlaybackResult();
}

final class AudioPlaying extends AudioPlaybackResult {
  const AudioPlaying();
}

final class AudioUnavailable extends AudioPlaybackResult {
  const AudioUnavailable(this.reason, this.message);

  final AudioUnavailableReason reason;

  /// Text the UI shows. Says plainly that the language has no voice yet rather
  /// than implying playback merely failed this once.
  final String message;
}

/// Plays a short sample phrase in a chosen language.
///
/// An interface because the source will change: bundled recordings first, then
/// platform TTS where a voice exists, then an on-device model, then
/// server-rendered audio. None of that reaches the screen.
abstract interface class LanguageAudioService {
  /// The sample phrase used for previews, in the given language.
  String samplePhrase({TargetLanguage? target, TeachingMedium? medium});

  /// Whether anything can actually be played for this language.
  Future<bool> canPlay({TargetLanguage? target, TeachingMedium? medium});

  Future<AudioPlaybackResult> play({
    TargetLanguage? target,
    TeachingMedium? medium,
  });

  Future<void> stop();
}

/// Plays bundled recordings, and reports the truth when there are none.
///
/// IMPORTANT: no Santali, Mundari or Ho recordings ship with this build, and
/// Android's text-to-speech engines do not carry voices for these languages
/// either. So this service reports them unavailable rather than substituting a
/// Hindi voice reading tribal text, which would be worse than silence in a
/// classroom.
class BundledLanguageAudioService implements LanguageAudioService {
  const BundledLanguageAudioService();

  static const Map<String, String> _samplesByLocale = <String, String>{
    'sat': 'ᱡᱚᱦᱟᱨ! ᱟᱞᱮ ᱠᱚᱣᱟᱜ ᱠᱞᱟᱥ ᱨᱮ ᱥᱟᱹᱜᱩᱱ ᱫᱟᱨᱟᱢ',
    'unr': 'Johar! Ale kowa class re sagun daram',
    'hoc': 'Johar! Ale kowa class re sagun daram',
    'hi-IN': 'नमस्ते! आज हम पक्षियों के बारे में सीखेंगे।',
    'en-IN': 'Hello! Today we will learn about birds.',
    'bn-IN': 'নমস্কার! আজ আমরা পাখিদের সম্পর্কে শিখব।',
    'or-IN': 'ନମସ୍କାର! ଆଜି ଆମେ ପକ୍ଷୀ ବିଷୟରେ ଶିଖିବା।',
  };

  static String _localeOf({TargetLanguage? target, TeachingMedium? medium}) =>
      target?.localeId ?? medium?.localeId ?? 'hi-IN';

  static String _labelOf({TargetLanguage? target, TeachingMedium? medium}) =>
      target?.label ?? medium?.label ?? 'this language';

  /// Where a recording would live once one is produced.
  static String clipPath(String localeId) => 'assets/audio/sample_$localeId.mp3';

  @override
  String samplePhrase({TargetLanguage? target, TeachingMedium? medium}) =>
      _samplesByLocale[_localeOf(target: target, medium: medium)] ?? '';

  @override
  Future<bool> canPlay({TargetLanguage? target, TeachingMedium? medium}) async {
    try {
      await rootBundle.load(
        clipPath(_localeOf(target: target, medium: medium)),
      );
      return true;
    } on Object {
      return false;
    }
  }

  @override
  Future<AudioPlaybackResult> play({
    TargetLanguage? target,
    TeachingMedium? medium,
  }) async {
    if (!await canPlay(target: target, medium: medium)) {
      return AudioUnavailable(
        AudioUnavailableReason.noVoice,
        'Audio for ${_labelOf(target: target, medium: medium)} is not on this '
            'device yet. It will arrive with the offline language pack.',
      );
    }
    // Reached only once a clip is bundled; playback lands here with the audio
    // plugin at that point.
    return const AudioPlaying();
  }

  @override
  Future<void> stop() async {}
}
