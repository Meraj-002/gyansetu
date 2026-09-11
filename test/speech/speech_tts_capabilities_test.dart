import 'package:flutter_test/flutter_test.dart';
import 'package:gyan_setu_ai/services/audio/text_to_speech_service.dart';
import 'package:gyan_setu_ai/services/speech/development_speech_recognition_service.dart';
import 'package:gyan_setu_ai/services/speech/fallback_speech_recognition_service.dart';
import 'package:gyan_setu_ai/services/speech/speech_recognition_service.dart';

void main() {
  group('speech capability reporting', () {
    test('dev adapter lists exactly the languages it can fake-transcribe', () async {
      final DevelopmentSpeechRecognitionService service =
          DevelopmentSpeechRecognitionService();

      final List<String> languages = await service.supportedLanguages();

      expect(languages, containsAll(<String>['hi-IN', 'sat']));
      expect(languages, equals(languages.toList()..sort()));
    });

    test('dev adapter is a mock and honesty-labelled as one', () async {
      final DevelopmentSpeechRecognitionService service =
          DevelopmentSpeechRecognitionService();
      expect(DevelopmentSpeechRecognitionService.isMock, isTrue);
      expect(await service.isAvailable('hi-IN'), isTrue);
      expect(await service.isAvailable('sat'), isTrue);
      expect(await service.isAvailable('de-DE'), isFalse);
    });

    test('the listening lifecycle is streamed to the UI', () async {
      final DevelopmentSpeechRecognitionService service =
          DevelopmentSpeechRecognitionService(
        listenWindow: const Duration(milliseconds: 1),
      );
      final List<SpeechRecognitionState> seen = <SpeechRecognitionState>[];
      final Future<void> done = service.startListening(localeId: 'hi-IN').then(
        (_) {},
        onError: (_) {},
      );

      final subscription = service.stateChanges.listen(seen.add);
      await done;
      await subscription.cancel();
      await service.dispose();

      expect(seen, contains(SpeechRecognitionState.listening));
      expect(seen, contains(SpeechRecognitionState.completed));
    });

    test('the fallback unions the device and dev languages', () async {
      final FallbackSpeechRecognitionService service =
          FallbackSpeechRecognitionService(
        platform: DevelopmentSpeechRecognitionService(
          script: const <String, List<String>>{},
        ),
        fallback: DevelopmentSpeechRecognitionService(),
      );

      final List<String> languages = await service.supportedLanguages();

      expect(languages, contains('hi-IN'));
      expect(languages, contains('sat'));
      await service.dispose();
    });
  });

  group('TTS honest capability', () {
    setUpAll(() => TestWidgetsFlutterBinding.ensureInitialized());

    test('pause is offered and resume is honestly refused', () async {
      final PlatformTextToSpeechService service = PlatformTextToSpeechService();

      expect(service.canPause, isTrue);
      expect(service.canResume, isFalse);

      final result = await service.resume();
      expect(result.isOk, isFalse,
          reason: 'a dead resume control must never be shown');
      await service.dispose();
    });

    test('tribal languages have no voice anywhere and admit it', () async {
      final PlatformTextToSpeechService service = PlatformTextToSpeechService();

      expect(await service.isLanguageAvailable('sat'), isFalse);
      await service.dispose();
    });
  });
}