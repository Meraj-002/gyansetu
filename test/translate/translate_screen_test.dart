import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gyan_setu_ai/core/models/app_language.dart';
import 'package:gyan_setu_ai/features/translate/services/translate_controller.dart';
import 'package:gyan_setu_ai/features/translate/translate_screen.dart';
import 'package:gyan_setu_ai/services/speech/speech_recognition_service.dart';
import 'package:gyan_setu_ai/services/translation/text_translation_service.dart';

import '../classroom/live_classroom_doubles.dart'
    show FakeSpeechRecognitionService;
import '../lessons/lesson_detail_services_test.dart' show FakeTts;
import '../translation/translation_test_doubles.dart';

/// Succeeds on the second call so a Retry tap can be proven to re-run the
/// exact sentence with the controller's own input.
class _FlakyOnceTranslator implements TextTranslationService {
  int calls = 0;

  @override
  bool get requiresNetwork => false;
  @override
  bool get isRealModel => false;
  @override
  String get modelVersion => 'flaky-1';

  @override
  Future<bool> supportsPair(String source, String target) async => true;

  @override
  Future<TranslationResult> translate(TranslationRequest request) async {
    calls += 1;
    if (calls == 1) {
      throw const TextTranslationFailure(
        TranslationFailureReason.failed,
        'temporary failure',
      );
    }
    return offlineResult();
  }
}

void main() {
  Widget harness(TranslateController controller) =>
      MaterialApp(home: TranslateScreen(controller: controller));

  testWidgets('labels a phrasebook answer with the honest source badge', (
    WidgetTester tester,
  ) async {
    final RecordingTranslator translator = RecordingTranslator(
      answer: offlineResult(),
      requiresNetwork: false,
    );
    final TranslateController controller = TranslateController(
      translator: translator,
    );

    await controller.translate('बच्चों, कितने आम हैं?');
    await tester.pumpWidget(harness(controller));
    await tester.pumpAndSettle();

    expect(find.text("Gidra'ko, kete ul menaka?"), findsOneWidget);
    expect(find.text('Phrasebook'), findsOneWidget);
    expect(find.text('Online'), findsNothing);
    expect(find.text('AI'), findsNothing);
  });

  testWidgets('labels an online answer with the honest source badge', (
    WidgetTester tester,
  ) async {
    final RecordingTranslator translator = RecordingTranslator(
      answer: onlineResult(),
      requiresNetwork: true,
    );
    final TranslateController controller = TranslateController(
      translator: translator,
    );

    await controller.translate('बच्चों, कितने आम हैं?');
    await tester.pumpWidget(harness(controller));
    await tester.pumpAndSettle();

    expect(find.text('Online translation'), findsOneWidget);
    expect(find.text('Phrasebook'), findsNothing);
    expect(find.text('AI'), findsNothing);
  });

  testWidgets(
    'badges "AI translation" ONLY when a real model produced the answer',
    (WidgetTester tester) async {
      final RecordingTranslator translator = RecordingTranslator(
        answer: TranslationResult(
          translatedText: 'translated',
          sourceLanguage: 'hi-IN',
          targetLanguage: 'sat',
          modelVersion: 'indictrans2-indic-indic-dist-320M',
          source: TranslationSource.onlineBackend,
          engineName: 'ai4bharat/indictrans2-indic-indic-dist-320M',
          engineIsRealModel: true,
        ),
        requiresNetwork: true,
      );
      final TranslateController controller = TranslateController(
        translator: translator,
      );

      await controller.translate('बच्चों, कितने आम हैं?');
      await tester.pumpWidget(harness(controller));
      await tester.pumpAndSettle();

      expect(
        find.text(
          'AI translation • ai4bharat/indictrans2-indic-indic-dist-320M',
        ),
        findsOneWidget,
      );
      expect(find.text('Online translation'), findsNothing);
    },
  );

  testWidgets('a verified phrasebook answer is labelled "Verified phrase"', (
    WidgetTester tester,
  ) async {
    final RecordingTranslator translator = RecordingTranslator(
      answer: TranslationResult(
        translatedText: "Gidra'ko, kete ul menaka?",
        sourceLanguage: 'hi-IN',
        targetLanguage: 'sat',
        modelVersion: 'offline-phrasebook-1',
        spokenText: 'गिड़ाको, केते उल् मेनाका?',
        reviewedBySpeaker: true,
        source: TranslationSource.phrasebook,
      ),
      requiresNetwork: false,
    );
    final TranslateController controller = TranslateController(
      translator: translator,
    );

    await controller.translate('बच्चों, कितने आम हैं?');
    await tester.pumpWidget(harness(controller));
    await tester.pumpAndSettle();

    expect(find.text('Verified phrase'), findsOneWidget);
    expect(find.text('Phrasebook'), findsNothing);
    // A verified record is not warned about.
    expect(find.textContaining('not yet verified by a speaker'), findsNothing);
  });

  testWidgets('an unverified phrasebook answer stays "Phrasebook" and warns '
      '(never claims verification)', (WidgetTester tester) async {
    final RecordingTranslator translator = RecordingTranslator(
      answer: offlineResult(),
      requiresNetwork: false,
    );
    final TranslateController controller = TranslateController(
      translator: translator,
    );

    await controller.translate('बच्चों, कितने आम हैं?');
    await tester.pumpWidget(harness(controller));
    await tester.pumpAndSettle();

    expect(find.text('Phrasebook'), findsOneWidget);
    expect(find.text('Verified phrase'), findsNothing);
    expect(
      find.textContaining('not yet verified by a speaker'),
      findsOneWidget,
    );
  });

  testWidgets('an offline model answer is labelled "Offline model"', (
    WidgetTester tester,
  ) async {
    final RecordingTranslator translator = RecordingTranslator(
      answer: offlineResult().copyWith(source: TranslationSource.offlineModel),
      requiresNetwork: false,
    );
    final TranslateController controller = TranslateController(
      translator: translator,
    );

    await controller.translate('बच्चों, कितने आम हैं?');
    await tester.pumpWidget(harness(controller));
    await tester.pumpAndSettle();

    expect(find.text('Offline model'), findsOneWidget);
  });

  testWidgets('labels a cached answer with the cached badge and the original '
      'text', (WidgetTester tester) async {
    final RecordingTranslator translator = RecordingTranslator(
      answer: offlineResult().copyWith(source: TranslationSource.cache),
      requiresNetwork: false,
    );
    final TranslateController controller = TranslateController(
      translator: translator,
    );

    await controller.translate('बच्चों, कितने आम हैं?');
    await tester.pumpWidget(harness(controller));
    await tester.pumpAndSettle();

    expect(find.text('Cached'), findsOneWidget);
  });

  testWidgets('a microphone control is honest when no recogniser exists', (
    WidgetTester tester,
  ) async {
    final RecordingTranslator translator = RecordingTranslator(
      answer: offlineResult(),
      requiresNetwork: false,
    );
    final TranslateController controller = TranslateController(
      translator: translator,
    );

    await controller.startListening();
    await tester.pumpWidget(harness(controller));

    expect(
      find.text('Speech recognition is not available on this device.'),
      findsOneWidget,
    );
  });

  testWidgets('shows the exact reason when no answer exists offline', (
    WidgetTester tester,
  ) async {
    final RecordingTranslator translator = RecordingTranslator(
      failure: const TextTranslationFailure(
        TranslationFailureReason.needsConnection,
        'Offline translation is unavailable for this language.',
      ),
      requiresNetwork: false,
    );
    final TranslateController controller = TranslateController(
      translator: translator,
    );

    await controller.translate('कल की छुट्टी के बारे में बात करें।');
    await tester.pumpWidget(harness(controller));
    await tester.pumpAndSettle();

    expect(
      find.text('Offline translation is unavailable for this language.'),
      findsOneWidget,
    );
    // No invented answer reaches the teacher.
    expect(find.text("Gidra'ko, kete ul menaka?"), findsNothing);
  });

  testWidgets('swapping the languages translates the other way', (
    WidgetTester tester,
  ) async {
    final RecordingTranslator translator = RecordingTranslator(
      answer: onlineResult(text: 'बच्चों, कितने आम हैं?'),
      requiresNetwork: true,
    );
    final TranslateController controller = TranslateController(
      translator: translator,
    );

    controller.swapLanguages();
    await tester.pumpWidget(harness(controller));
    await tester.pumpAndSettle();

    expect(controller.sourceLanguage, AppLanguage.santali);
    expect(controller.targetLanguage, AppLanguage.hindi);

    await controller.translate("Gidra'ko, kete ul menaka?");
    expect(translator.lastRequest!.sourceLanguage, 'sat');
    expect(translator.lastRequest!.targetLanguage, 'hi-IN');
  });

  testWidgets('an empty input is explained, never translated', (
    WidgetTester tester,
  ) async {
    final RecordingTranslator translator = RecordingTranslator(
      answer: offlineResult(),
      requiresNetwork: false,
    );
    final TranslateController controller = TranslateController(
      translator: translator,
    );

    await controller.translate('   ');
    await tester.pumpWidget(harness(controller));
    await tester.pumpAndSettle();

    expect(find.text('Type a sentence to translate first.'), findsOneWidget);
    expect(translator.calls, 0);
  });

  testWidgets('dictating opens the recogniser and fills the sentence, which '
      'then translates', (WidgetTester tester) async {
    final RecordingTranslator translator = RecordingTranslator(
      answer: onlineResult(),
      requiresNetwork: true,
    );
    final FakeSpeechRecognitionService speech = FakeSpeechRecognitionService(
      transcript: 'बच्चों, कितने आम हैं?',
    );
    final TranslateController controller = TranslateController(
      translator: translator,
      speech: speech,
    );

    await tester.pumpWidget(harness(controller));
    await tester.tap(find.byKey(const ValueKey<String>('mic')));
    await tester.pumpAndSettle();

    expect(speech.requestedLocales, <String>['hi-IN']);
    expect(
      find.text("Gidra'ko, kete ul menaka?"),
      findsOneWidget,
      reason: 'the dictated sentence is translated and shown.',
    );
  });

  testWidgets('a language with no recogniser reports it instead of listening', (
    WidgetTester tester,
  ) async {
    final TranslateController controller = TranslateController(
      translator: RecordingTranslator(answer: offlineResult()),
      speech: FakeSpeechRecognitionService(
        failure: const SpeechRecognitionFailure(
          SpeechFailureReason.languageUnsupported,
          'Speech recognition for this language is not available on this '
          'device yet.',
        ),
      ),
    );

    await tester.pumpWidget(harness(controller));
    await tester.tap(find.byKey(const ValueKey<String>('mic')));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('not available on this device yet'),
      findsOneWidget,
    );
  });

  testWidgets('read-aloud attempts the text even when the engine has no '
      'native voice', (WidgetTester tester) async {
    final RecordingTranslator translator = RecordingTranslator(
      answer: onlineResult(),
      requiresNetwork: true,
    );
    // A device with no native Santali voice: the text is still handed to the
    // engine as plain text, rather than being blocked by an availability gate.
    final FakeTts tts = FakeTts(languages: const <String>{});
    final TranslateController controller = TranslateController(
      translator: translator,
      tts: tts,
    );

    await controller.translate('बच्चों, कितने आम हैं?');
    await tester.pumpWidget(harness(controller));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey<String>('speaker')));
    await tester.pumpAndSettle();

    expect(tts.spoken.single, "Gidra'ko, kete ul menaka?");
    expect(find.textContaining('No Santali voice'), findsNothing);
  });

  testWidgets('read-aloud speaks with the target voice when one exists', (
    WidgetTester tester,
  ) async {
    final RecordingTranslator translator = RecordingTranslator(
      answer: offlineResult().copyWith(source: TranslationSource.onlineBackend),
      requiresNetwork: true,
    );
    final FakeTts tts = FakeTts(languages: const <String>{'sat'});
    final TranslateController controller = TranslateController(
      translator: translator,
      tts: tts,
    );

    await controller.translate('बच्चों, कितने आम हैं?');
    await tester.pumpWidget(harness(controller));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey<String>('speaker')));
    await tester.pumpAndSettle();

    expect(tts.spoken.single, "Gidra'ko, kete ul menaka?");
    expect(tts.locales.single, 'sat');
  });

  testWidgets('a failed translation can be retried from the Retry button', (
    WidgetTester tester,
  ) async {
    final _FlakyOnceTranslator translator = _FlakyOnceTranslator();
    final TranslateController controller = TranslateController(
      translator: translator,
    );

    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(harness(controller));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'बच्चों, कितने आम हैं?');
    await tester.tap(find.byKey(const ValueKey<String>('translate')));
    await tester.pumpAndSettle();

    expect(translator.calls, 1);
    expect(find.textContaining('temporary failure'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey<String>('retry')));
    await tester.pumpAndSettle();

    expect(translator.calls, 2);
    expect(find.textContaining('temporary failure'), findsNothing);
  });

  testWidgets('lays out at handset and tablet widths without overflow', (
    WidgetTester tester,
  ) async {
    final RecordingTranslator translator = RecordingTranslator(
      answer: offlineResult(),
      requiresNetwork: false,
    );
    final TranslateController controller = TranslateController(
      translator: translator,
    );

    for (final Size size in <Size>[
      const Size(360, 800),
      const Size(375, 812),
      const Size(390, 844),
      const Size(412, 915),
      const Size(600, 960),
      const Size(900, 1200),
    ]) {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await controller.translate('बच्चों, कितने आम हैं?');
      await tester.pumpWidget(harness(controller));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Phrasebook'), findsOneWidget);
    }
  });
}
