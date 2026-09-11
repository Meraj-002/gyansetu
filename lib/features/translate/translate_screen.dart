import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';
import '../../core/models/app_language.dart';
import '../../services/audio/audio_recorder.dart';
import '../../services/audio/clip_player.dart';
import '../../services/audio/text_to_speech_service.dart';
import '../../services/service_registry.dart';
import '../../services/speech/speech_recognition_service.dart';
import '../../services/translation/text_translation_service.dart';
import '../../services/translation/voice_translation_service.dart';
import 'services/translate_controller.dart';

/// Translate screen.
///
/// Real offline-first translation, not a placeholder. The sentence a teacher
/// types goes to the on-device phrasebook first, then an installed offline
/// model, and only reaches the network when the device is online and neither
/// can answer. Every outcome the teacher sees is labelled with what actually
/// happened — Phrasebook, Offline, Online, Cached — or with the honest reason
/// no answer exists. A result is never called "AI" unless a real model
/// produced it.
///
/// The microphone and the speaker connect the real speech pipeline without
/// faking a link: a language with no recogniser or no voice reports that
/// instead of pretending.
class TranslateScreen extends StatefulWidget {
  const TranslateScreen({
    super.key,
    this.controller,
    this.translator,
    this.speech,
    this.tts,
    this.voice,
    this.recorder,
    this.player,
  });

  /// Tests inject a controller to avoid touching the registry.
  final TranslateController? controller;

  /// Tests inject a translator instead of the registry's decision graph.
  final TextTranslationService? translator;

  /// Tests inject recogniser/speech doubles so the mic and speaker controls
  /// never touch a real engine.
  final SpeechRecognitionService? speech;
  final TextToSpeechService? tts;

  /// Tests inject the speech-to-speech path and the local player so the voice
  /// controls never touch the network or the device microphone.
  final VoiceTranslationService? voice;
  final AudioRecorder? recorder;
  final ClipPlayer? player;

  @override
  State<TranslateScreen> createState() => _TranslateScreenState();
}

class _TranslateScreenState extends State<TranslateScreen> {
  late final TranslateController _controller;
  final TextEditingController _input = TextEditingController();

  @override
  void initState() {
    super.initState();
    _controller = widget.controller ??
        TranslateController(
          translator: widget.translator ??
              ServiceRegistry.instance.translation,
          speech: widget.speech ?? ServiceRegistry.instance.speech,
          tts: widget.tts ?? ServiceRegistry.instance.tts,
          voice: widget.voice ?? ServiceRegistry.instance.voice,
          recorder: widget.recorder ?? ServiceRegistry.instance.recorder,
          player: widget.player ?? ServiceRegistry.instance.player,
        );
  }

  @override
  void dispose() {
    _input.dispose();
    if (widget.controller == null && widget.translator == null) {
      _controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Translate')),
      body: ListenableBuilder(
        listenable: _controller,
        builder: (BuildContext context, Widget? _) {
          return SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  _languageRow(),
                  const SizedBox(height: 12),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Expanded(
                        child: TextField(
                          controller: _input,
                          maxLines: 3,
                          decoration: const InputDecoration(
                            border: OutlineInputBorder(),
                            hintText: 'Type a sentence…',
                            labelText: 'Sentence',
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      _micButton(),
                    ],
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    key: const ValueKey<String>('translate'),
                    onPressed: _controller.status == TranslateStatus.loading
                        ? null
                        : () => _controller.translate(_input.text),
                    icon: const Icon(Icons.translate),
                    label: Text(
                      _controller.status == TranslateStatus.loading
                          ? 'Translating…'
                          : 'Translate',
                    ),
                  ),
                  if (_controller.availabilityNote != null) ...<Widget>[
                    const SizedBox(height: 12),
                    _availabilityNote(_controller.availabilityNote!),
                  ],
                  const SizedBox(height: 16),
                  _outcome(),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _languageRow() {
    return Row(
      children: <Widget>[
        Expanded(child: _languageDropdown(which: 'source')),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 8),
          child: Icon(Icons.arrow_forward, color: AppColors.textSecondary),
        ),
        Expanded(child: _languageDropdown(which: 'target')),
        IconButton(
          onPressed: _controller.swapLanguages,
          icon: const Icon(Icons.swap_horiz),
          tooltip: 'Swap languages',
        ),
      ],
    );
  }

  Widget _languageDropdown({required String which}) {
    final bool isSource = which == 'source';
    final AppLanguage selected =
        isSource ? _controller.sourceLanguage : _controller.targetLanguage;
    return DropdownButtonFormField<AppLanguage>(
      key: ValueKey<String>(which),
      initialValue: selected,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: isSource ? 'From' : 'To',
        border: const OutlineInputBorder(),
      ),
      items: <DropdownMenuItem<AppLanguage>>[
        for (final AppLanguage language in _translatableLanguages())
          DropdownMenuItem<AppLanguage>(
            value: language,
            child: Text(language.label, overflow: TextOverflow.ellipsis),
          ),
      ],
      onChanged: (AppLanguage? language) {
        if (language == null) return;
        if (isSource) {
          _controller.setSourceLanguage(language);
        } else {
          _controller.setTargetLanguage(language);
        }
      },
    );
  }

  List<AppLanguage> _translatableLanguages() => const <AppLanguage>[
        AppLanguage.hindi,
        AppLanguage.santali,
      ];

  /// The microphone button.
  ///
  /// With the voice (speech-to-speech) path wired, one tap starts recording,
  /// the next stops and uploads — the translated text and its spoken clip come
  /// back from Adi Vaani. Without it, real on-device speech recognition when
  /// the language has a recogniser, and an honest unavailable note otherwise.
  Widget _micButton() {
    final bool busy = _controller.isListening;
    final bool recording = _controller.isRecording;
    if (_controller.hasVoiceTranslation) {
      final bool uploading = _controller.status == TranslateStatus.loading;
      return IconButton.filledTonal(
        key: const ValueKey<String>('mic'),
        onPressed: uploading
            ? null
            : recording
            ? _controller.stopVoiceTranslation
            : _controller.startVoiceTranslation,
        icon: recording
            ? const Icon(Icons.stop, color: AppColors.error)
            : const Icon(Icons.mic),
        tooltip: recording
            ? 'Stop and translate in ${_controller.targetLanguage.label}'
            : 'Record in ${_controller.sourceLanguage.label}',
      );
    }
    return IconButton.filledTonal(
      key: const ValueKey<String>('mic'),
      onPressed: busy
          ? null
          : () => _controller.startListening(
                onTranscribed: (String text) {
                  _input
                    ..text = text
                    ..selection = TextSelection.collapsed(
                        offset: text.length);
                  if (text.trim().isNotEmpty) _controller.translate(text);
                },
              ),
      icon: busy
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.mic),
      tooltip: 'Dictate in ${_controller.sourceLanguage.label}',
    );
  }

  /// The honest read-aloud of an unavailable capability (no recogniser, no
  /// voice), shown as its own note rather than as a translation error.
  Widget _availabilityNote(String note) {
    return Card(
      color: AppColors.textSecondary.withValues(alpha: 0.08),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: <Widget>[
            const Icon(Icons.info_outline, size: 18),
            const SizedBox(width: 8),
            Expanded(child: Text(note)),
          ],
        ),
      ),
    );
  }

  Widget _outcome() {
    switch (_controller.status) {
      case TranslateStatus.idle:
        return const SizedBox.shrink();
      case TranslateStatus.loading:
        return const Card(
          child: Padding(
            padding: EdgeInsets.all(16),
            child: Row(
              children: <Widget>[
                SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                SizedBox(width: 12),
                Text('Working…'),
              ],
            ),
          ),
        );
      case TranslateStatus.error:
        return Card(
          color: AppColors.error.withValues(alpha: 0.06),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Icon(Icons.info_outline, color: AppColors.error),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(_controller.errorMessage ?? 'Translation failed.'),
                ),
                const SizedBox(width: 4),
                TextButton.icon(
                  key: const ValueKey<String>('retry'),
                  onPressed: () => _controller.translate(_input.text),
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text('Retry'),
                ),
              ],
            ),
          ),
        );
      case TranslateStatus.success:
        final TranslationResult result = _controller.result!;
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Expanded(child: _sourceBadge(result)),
                    _speakerButton(result),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  result.translatedText,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                if (result.spokenText != null &&
                    result.spokenText!.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 8),
                  Text(
                    result.spokenText!,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 16,
                    ),
                  ),
                ],
                if (_isUnreviewedPhrasebook(result)) ...<Widget>[
                  const SizedBox(height: 8),
                  const Text(
                    'Development phrasebook entry — not yet verified by a '
                    'speaker.',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
    }
  }

  /// The read-aloud control. Hidden when no speech output is wired at all;
  /// with a voice-translation result it replays the recorded clip, otherwise
  /// the TTS engine reads the text (reporting honestly when a language has no
  /// voice).
  Widget _speakerButton(TranslationResult result) {
    if (_controller.tts == null && !_controller.hasPlayer) {
      return const SizedBox.shrink();
    }
    return IconButton(
      key: const ValueKey<String>('speaker'),
      onPressed: _controller.isSpeaking
          ? null
          : _controller.speakTranslation,
      icon: _controller.isSpeaking
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.volume_up),
      tooltip: 'Read aloud in ${_controller.targetLanguage.label}',
    );
  }

  bool _isUnreviewedPhrasebook(TranslationResult result) =>
      result.source == TranslationSource.phrasebook &&
      !result.reviewedBySpeaker;

  Widget _sourceBadge(TranslationResult result) {
    final TranslationSource? source = result.source;
    if (source == null) return const SizedBox.shrink();
    final Color color = switch (source) {
      TranslationSource.phrasebook => AppColors.primary,
      TranslationSource.offlineModel => AppColors.primary,
      TranslationSource.onlineBackend => AppColors.secondaryDark,
      TranslationSource.cache => AppColors.success,
    };
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          result.aiEngineLabel ??
              source.displayLabel(reviewedBySpeaker: result.reviewedBySpeaker),
          style: TextStyle(color: color, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}