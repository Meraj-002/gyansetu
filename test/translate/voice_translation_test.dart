import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:gyan_setu_ai/core/errors/app_exception.dart';
import 'package:gyan_setu_ai/core/utils/result.dart';
import 'package:gyan_setu_ai/features/translate/services/translate_controller.dart';
import 'package:gyan_setu_ai/services/api/api_client.dart';
import 'package:gyan_setu_ai/services/translation/fastapi_voice_translation_service.dart';
import 'package:gyan_setu_ai/services/translation/voice_translation_service.dart';

import '../lessons/lesson_detail_services_test.dart' show FakeTts;
import '../translation/translation_test_doubles.dart' show RecordingTranslator;
import 'voice_translation_doubles.dart';

void main() {
  group('FastApiVoiceTranslationService', () {
    test('uploads the file and decodes the WAV payload to a local clip',
        () async {
      final Directory dir = await Directory.systemTemp.createTemp('voice-test');
      final String clipPath = '${dir.path}/voice_out_test.wav';
      final FakeApiClient api = FakeApiClient(
        response: Ok<Map<String, dynamic>>(<String, dynamic>{
          'transcript': 'मेरा नाम अनिता है',
          'translatedText': 'Āmić’ nám Anita aka',
          'audio': base64.encode(<int>[0x52, 0x49, 0x46, 0x46, 0, 1, 2, 3, 4]),
          'contentType': 'audio/wav',
          'provider': 'adivaani',
        }),
      );
      final FastApiVoiceTranslationService service =
          FastApiVoiceTranslationService(
            api: api,
            translatedClipPath: () async => clipPath,
          );

      final VoiceTranslationResult result = await service.translateVoice(
        audioPath: '${dir.path}/recording.wav',
      );

      expect(api.lastPath, '/api/v1/translation/speech');
      expect(api.lastFileName, 'speech.wav');
      expect(result.transcript, 'मेरा नाम अनिता है');
      expect(result.translatedText, 'Āmić’ nám Anita aka');
      expect(result.provider, 'adivaani');
      expect(result.audioPath, clipPath);
      expect(
        await File(clipPath).readAsBytes(),
        <int>[0x52, 0x49, 0x46, 0x46, 0, 1, 2, 3, 4],
      );
      await dir.delete(recursive: true);
    });

    test('accepts a data-URL wrapped audio payload', () async {
      final Directory dir = await Directory.systemTemp.createTemp('voice-test');
      final String clipPath = '${dir.path}/voice_out_test.wav';
      final FakeApiClient api = FakeApiClient(
        response: Ok<Map<String, dynamic>>(<String, dynamic>{
          'transcript': 'hi',
          'translatedText': 'sat',
          'audio': 'data:audio/wav;base64,${base64.encode(<int>[9, 8])}',
        }),
      );
      final FastApiVoiceTranslationService service =
          FastApiVoiceTranslationService(
            api: api,
            translatedClipPath: () async => clipPath,
          );

      await service.translateVoice(
        audioPath: '${dir.path}/recording.wav',
      );

      final List<int> wav = await File(clipPath).readAsBytes();
      expect(wav.length, 44 + 2);
      expect(wav.sublist(44), <int>[9, 8]);
      await dir.delete(recursive: true);
    });

    test('wraps bare PCM frames in a playable WAV header', () async {
      final Directory dir = await Directory.systemTemp.createTemp('voice-test');
      final String clipPath = '${dir.path}/voice_out_test.wav';
      final List<int> pcm = <int>[0x24, 0x01, 0x25, 0x01, 0x00, 0x00];
      final FakeApiClient api = FakeApiClient(
        response: Ok<Map<String, dynamic>>(<String, dynamic>{
          'transcript': 'hi',
          'translatedText': 'sat',
          'audio': base64.encode(pcm),
        }),
      );
      final FastApiVoiceTranslationService service =
          FastApiVoiceTranslationService(
            api: api,
            translatedClipPath: () async => clipPath,
          );

      await service.translateVoice(audioPath: '${dir.path}/recording.wav');

      final List<int> wav = await File(clipPath).readAsBytes();
      expect(ascii.decode(wav.sublist(0, 4)), 'RIFF');
      expect(ascii.decode(wav.sublist(8, 12)), 'WAVE');
      expect(ascii.decode(wav.sublist(36, 40)), 'data');
      expect(wav.length, 44 + pcm.length);
      // 22050 Hz mono 16-bit PCM header (default when the payload lacks RIFF).
      expect(ByteData.sublistView(Uint8List.fromList(wav)).getUint16(22, Endian.little), 1);
      expect(ByteData.sublistView(Uint8List.fromList(wav)).getUint32(24, Endian.little), 22050);
      expect(ByteData.sublistView(Uint8List.fromList(wav)).getUint16(34, Endian.little), 16);
      expect(wav.sublist(44), pcm);
      await dir.delete(recursive: true);
    });

    test('throws an honest failure when the answer has no audio', () async {
      final FakeApiClient api = FakeApiClient(
        response: Ok<Map<String, dynamic>>(<String, dynamic>{
          'transcript': 'hi',
          'translatedText': 'sat',
        }),
      );
      final FastApiVoiceTranslationService service =
          FastApiVoiceTranslationService(api: api);

      expect(
        () => service.translateVoice(audioPath: '/tmp/recording.wav'),
        throwsA(
          isA<VoiceTranslationFailure>().having(
            (f) => f.reason,
            'reason',
            VoiceTranslationFailureReason.failed,
          ),
        ),
      );
    });

    test('throws needsConnection on a network failure', () async {
      final FakeApiClient api = FakeApiClient(
        response: Err<Map<String, dynamic>>(
          NetworkException('no network'),
        ),
      );
      final FastApiVoiceTranslationService service =
          FastApiVoiceTranslationService(api: api);

      expect(
        () => service.translateVoice(audioPath: '/tmp/recording.wav'),
        throwsA(
          isA<VoiceTranslationFailure>().having(
            (f) => f.reason,
            'reason',
            VoiceTranslationFailureReason.needsConnection,
          ),
        ),
      );
    });
  });

  group('TranslateController voice flow', () {
    test(
      'recording requires the microphone permission and translates the '
      'returned clip end to end',
      () async {
        final Directory dir =
            await Directory.systemTemp.createTemp('voice-ctrl-test');
        final String recorded = '${dir.path}/recording.wav';
        final String returned = '${dir.path}/returned.wav';
        await File(returned).writeAsBytes(<int>[7, 7, 7]);

        final FakeAudioRecorder recorder = FakeAudioRecorder(
          permitted: true,
          outputPath: recorded,
        );
        final FakeVoiceTranslationService voice =
            FakeVoiceTranslationService(
              direction: (String path) => VoiceTranslationResult(
                transcript: 'heard',
                translatedText: 'translated',
                audioPath: returned,
                provider: 'adivaani',
              ),
            );
        final FakeClipPlayer player = FakeClipPlayer();
        final RecordingTranslator translator = RecordingTranslator(
          requiresNetwork: false,
        );
        final TranslateController controller = TranslateController(
          translator: translator,
          voice: voice,
          recorder: recorder,
          player: player,
          recordingPath: () async => recorded,
        );

        await controller.startVoiceTranslation();
        expect(controller.isRecording, isTrue);
        expect(recorder.startedPath, recorded);

        await controller.stopVoiceTranslation();
        expect(recorder.stopped, isTrue);
        expect(controller.status, TranslateStatus.success);
        expect(controller.result!.translatedText, 'translated');
        expect(controller.result!.originalText, 'heard');
        expect(controller.result!.provider, 'adivaani');
        expect(controller.voiceClipPath, returned);

        await controller.speakTranslation();
        expect(player.played, <String>[returned]);

        controller.dispose();
        await dir.delete(recursive: true);
      },
    );

    test('a denied microphone reports honestly and records nothing', () async {
      final FakeAudioRecorder recorder = FakeAudioRecorder(permitted: false);
      final TranslateController controller = TranslateController(
        translator: RecordingTranslator(requiresNetwork: false),
        voice: FakeVoiceTranslationService(direction: (String _) =>
            VoiceTranslationResult(
              transcript: 'x',
              translatedText: 'y',
              audioPath: '',
            )),
        recorder: recorder,
      );

      await controller.startVoiceTranslation();

      expect(controller.isRecording, isFalse);
      expect(
        controller.availabilityNote,
        'Microphone permission is needed to record.',
      );
      expect(recorder.startedPath, isNull);
    });

    test('a failed upload surfaces the exact reason, not fabricated audio',
        () async {
      final Directory dir =
          await Directory.systemTemp.createTemp('voice-ctrl-fail');
      final FakeAudioRecorder recorder = FakeAudioRecorder(
        permitted: true,
        outputPath: '${dir.path}/recording.wav',
      );
      final FakeVoiceTranslationService voice = FakeVoiceTranslationService(
        direction: (_) =>
            throw const VoiceTranslationFailure(
              VoiceTranslationFailureReason.needsConnection,
              'No internet connection.',
            ),
      );
      final TranslateController controller = TranslateController(
        translator: RecordingTranslator(requiresNetwork: false),
        voice: voice,
        recorder: recorder,
        recordingPath: () async => '${dir.path}/recording.wav',
      );

      await controller.startVoiceTranslation();
      await controller.stopVoiceTranslation();

      expect(controller.status, TranslateStatus.error);
      expect(controller.errorMessage, 'No internet connection.');
      expect(controller.voiceClipPath, isNull);
      expect(controller.isSpeaking, isFalse);
      await dir.delete(recursive: true);
    });

    test('the speaker replays the cached clip instead of the TTS engine',
        () async {
      final Directory dir =
          await Directory.systemTemp.createTemp('voice-ctrl-speaker');
      final String returned = '${dir.path}/returned.wav';
      final FakeClipPlayer player = FakeClipPlayer();
      final FakeTts tts = FakeTts();
      final TranslateController controller = TranslateController(
        translator: RecordingTranslator(requiresNetwork: false),
        tts: tts,
        voice: FakeVoiceTranslationService(direction: (_) =>
            VoiceTranslationResult(
              transcript: 't',
              translatedText: 'tt',
              audioPath: returned,
            )),
        recorder: FakeAudioRecorder(
          permitted: true,
          outputPath: '${dir.path}/rec.wav',
        ),
        player: player,
        recordingPath: () async => '${dir.path}/rec.wav',
      );

      await controller.startVoiceTranslation();
      await controller.stopVoiceTranslation();
      await controller.speakTranslation();

      expect(player.played, <String>[returned]);
      expect(tts.spoken, isEmpty);
      controller.dispose();
      await dir.delete(recursive: true);
    });
  });
}

class FakeApiClient implements ApiClient {
  FakeApiClient({required this.response});

  final Result<Map<String, dynamic>> response;
  String? lastPath;
  String? lastFileName;
  String? lastFilePath;

  @override
  Future<Result<Map<String, dynamic>>> postMultipart(
    String path, {
    required Map<String, String> fields,
    required String fileField,
    required String filePath,
    String? filename,
  }) async {
    lastPath = path;
    lastFileName = filename;
    lastFilePath = filePath;
    return response;
  }

  @override
  Future<Result<Map<String, dynamic>>> get(
    String path, {
    Map<String, String>? query,
  }) async => Err<Map<String, dynamic>>(ServerException('unused', statusCode: 500));

  @override
  Future<Result<Map<String, dynamic>>> post(String path, {Object? body}) async =>
      Err<Map<String, dynamic>>(ServerException('unused', statusCode: 500));

  @override
  Future<Result<Map<String, dynamic>>> put(String path, {Object? body}) async =>
      Err<Map<String, dynamic>>(ServerException('unused', statusCode: 500));

  @override
  Future<Result<Map<String, dynamic>>> patch(
    String path, {
    Object? body,
  }) async => Err<Map<String, dynamic>>(ServerException('unused', statusCode: 500));

  @override
  Future<Result<void>> delete(String path) async => const Ok<void>(null);
}