import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gyan_setu_ai/app/theme.dart';
import 'package:gyan_setu_ai/data/flashcard_data.dart';
import 'package:gyan_setu_ai/features/flashcards/flashcards_screen.dart';
import 'package:gyan_setu_ai/features/flashcards/services/flashcard_recommendation_service.dart';
import 'package:gyan_setu_ai/features/flashcards/services/flashcard_repository.dart';
import 'package:gyan_setu_ai/features/flashcards/services/flashcards_controller.dart';
import 'package:gyan_setu_ai/features/flashcards/widgets/flashcard_widgets.dart';
import 'package:gyan_setu_ai/features/setup/models/classroom_setup.dart';
import 'package:gyan_setu_ai/models/flashcard.dart';
import 'package:gyan_setu_ai/models/lesson.dart';
import 'package:gyan_setu_ai/services/audio/audio_resource_store.dart';
import 'package:gyan_setu_ai/services/audio/lesson_audio_service.dart';
import 'package:gyan_setu_ai/services/connectivity/connectivity_service.dart';
import 'package:gyan_setu_ai/services/storage/secure_storage_service.dart';

import '../classroom/live_classroom_doubles.dart' show FakeClipPlayer;
import '../lessons/lesson_detail_services_test.dart' show FakeTts;
import '../lessons/lesson_test_doubles.dart';
import '../setup/setup_test_doubles.dart' as setup_doubles;

/// Holds the load open so the skeleton is observable.
class SlowFlashcardDataSource implements FlashcardDataSource {
  const SlowFlashcardDataSource();

  @override
  Future<List<Flashcard>> load() async {
    await Future<void>.delayed(const Duration(milliseconds: 200));
    return FlashcardData.all();
  }
}

/// Brings a category chip into view before tapping it: the row scrolls
/// sideways, and a chip off the right edge cannot be hit.
Future<void> tapCategory(WidgetTester tester, FlashcardCategory category) async {
  final Finder chip = find.byKey(FlashcardsScreen.categoryKey(category));
  await tester.ensureVisible(chip);
  await tester.pumpAndSettle();
  await tester.tap(chip);
  await tester.pumpAndSettle();
}

void main() {
  late InMemorySecureStorageService storage;
  late LocalFlashcardRepository flashcards;
  late setup_doubles.TestRepository classrooms;
  late FakeLessonRepository lessons;
  late FakeTts tts;
  late TtsLessonAudioService audio;
  late StaticConnectivityService connectivity;

  Lesson countingLesson() => Lesson(
        id: 'c1-num-counting-1-10',
        title: 'Counting 1–10',
        description: 'Count everyday objects aloud.',
        subject: ClassroomSubject.numeracy,
        classNumber: 1,
        learningOutcome: 'Count objects from 1 to 10.',
        durationMinutes: 10,
        lessonOrder: 1,
        createdAt: DateTime(2026, 6, 1),
        updatedAt: DateTime(2026, 6, 1),
      );

  setUp(() {
    storage = InMemorySecureStorageService();
    flashcards = LocalFlashcardRepository(storage: storage);
    classrooms = setup_doubles.TestRepository(existing: testClassroom());
    lessons = FakeLessonRepository(catalogue: <Lesson>[countingLesson()]);
    // The engine knows Hindi and nothing else, which is the real situation on
    // an Android phone: no tribal language has a voice.
    tts = FakeTts(languages: <String>{'hi-IN'}, canSynthesiseToFile: false);
    connectivity = StaticConnectivityService(ConnectionStatus.offline);
    audio = TtsLessonAudioService(
      tts: tts,
      store: InMemoryAudioResourceStore(),
      player: FakeClipPlayer(),
      connectivity: connectivity,
    );
  });

  FlashcardsController buildController({
    String? lessonId,
    FlashcardRepository? repository,
    TargetLanguage target = TargetLanguage.santali,
  }) {
    if (target != TargetLanguage.santali) {
      classrooms = setup_doubles.TestRepository(
        existing: testClassroom(target: target),
      );
    }
    final FlashcardsController controller = FlashcardsController(
      flashcards: repository ?? flashcards,
      classrooms: classrooms,
      audio: audio,
      connectivity: connectivity,
      teacherId: kTeacherId,
      recommendations: const LocalFlashcardRecommendationService(),
      lessons: lessons,
      lessonId: lessonId,
    );
    addTearDown(controller.dispose);
    return controller;
  }

  Future<FlashcardsController> settle(FlashcardsController c) async {
    while (c.loadState == FlashcardsLoadState.loading) {
      await Future<void>.delayed(Duration.zero);
    }
    return c;
  }

  Future<FlashcardsController> pump(
    WidgetTester tester, {
    String? lessonId,
    FlashcardRepository? repository,
    Size size = const Size(430, 1600),
    FlashcardsController? controller,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final FlashcardsController c = controller ??
        buildController(lessonId: lessonId, repository: repository);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: FlashcardsScreen(controller: c),
      ),
    );
    await tester.pumpAndSettle();
    return c;
  }

  group('data', () {
    test('the bundled set has cards in the categories it claims', () async {
      final List<Flashcard> all = FlashcardData.all();

      expect(all, isNotEmpty);
      expect(
        all.where((Flashcard c) => c.category == FlashcardCategory.numbers),
        hasLength(10),
      );
      expect(
        all.where((Flashcard c) => c.category == FlashcardCategory.animals),
        hasLength(4),
      );
      expect(
        all.where((Flashcard c) => c.category == FlashcardCategory.nature),
        hasLength(4),
      );
      expect(
        all.where((Flashcard c) => c.category == FlashcardCategory.objects),
        hasLength(4),
      );
    });

    test('every picture is a bundled asset, never a URL', () {
      for (final Flashcard card in FlashcardData.all()) {
        final String? asset = card.imageAsset;
        if (asset == null) continue;
        expect(asset, startsWith('assets/'));
        expect(asset, isNot(contains('http')));
      }
    });

    test('a card with no picture draws its numeral instead', () {
      final Flashcard three = FlashcardData.all()
          .firstWhere((Flashcard c) => c.id == 'numbers-3');

      expect(three.hasImage, isFalse);
      expect(three.isDrawn, isTrue);
      expect(three.numeral, 3);
      expect(three.counters, 3);
    });

    test('survives a round trip through JSON', () {
      final Flashcard card = FlashcardData.all().first;
      final Flashcard decoded = Flashcard.fromJson(card.toJson());

      expect(decoded.id, card.id);
      expect(decoded.category, card.category);
      expect(decoded.hindiWord, card.hindiWord);
      expect(
        decoded.translationFor(TargetLanguage.santali)?.word,
        card.translationFor(TargetLanguage.santali)?.word,
      );
    });
  });

  group('repository', () {
    test('filters by category', () async {
      final List<Flashcard> animals =
          await flashcards.byCategory(FlashcardCategory.animals);

      expect(animals, isNotEmpty);
      for (final Flashcard card in animals) {
        expect(card.category, FlashcardCategory.animals);
      }
    });

    test('a category with no cards comes back empty, not missing', () async {
      expect(
        await flashcards.byCategory(FlashcardCategory.actions),
        isEmpty,
      );
    });

    test('finds a card by id', () async {
      expect((await flashcards.byId('objects-apple'))?.hindiWord, 'सेब');
      expect(await flashcards.byId('nothing'), isNull);
    });

    test('a bookmark survives a new repository over the same storage',
        () async {
      expect(await flashcards.toggleBookmark('objects-apple'), isTrue);

      final LocalFlashcardRepository reopened =
          LocalFlashcardRepository(storage: storage);
      expect(await reopened.bookmarkedIds(), contains('objects-apple'));
      expect((await reopened.bookmarked()).single.id, 'objects-apple');
    });

    test('toggling twice removes the bookmark', () async {
      await flashcards.toggleBookmark('objects-apple');
      expect(await flashcards.toggleBookmark('objects-apple'), isFalse);
      expect(await flashcards.bookmarkedIds(), isEmpty);
    });

    test('adding the same card to a lesson twice keeps one record', () async {
      await flashcards.addToClassroom(
        flashcardId: 'numbers-1',
        lessonId: 'c1-num-counting-1-10',
        classNumber: 1,
      );
      await flashcards.addToClassroom(
        flashcardId: 'numbers-1',
        lessonId: 'c1-num-counting-1-10',
        classNumber: 1,
      );

      expect(
        await flashcards.classroomCards(lessonId: 'c1-num-counting-1-10'),
        hasLength(1),
      );
      expect(
        await flashcards.isInClassroom('numbers-1', 'c1-num-counting-1-10'),
        isTrue,
      );
    });

    test('resetting progress keeps the lesson cards', () async {
      await flashcards.toggleBookmark('numbers-1');
      await flashcards.setLastIndex(FlashcardCategory.numbers, 3);
      await flashcards.addToClassroom(
        flashcardId: 'numbers-1',
        lessonId: 'c1-num-counting-1-10',
        classNumber: 1,
      );

      await flashcards.resetProgress();

      expect(await flashcards.bookmarkedIds(), isEmpty);
      expect(await flashcards.lastIndexFor(FlashcardCategory.numbers), 0);
      // The teacher's lesson plan is not progress and is left alone.
      expect(await flashcards.classroomCards(), hasLength(1));
    });
  });

  group('lesson context', () {
    test('a counting lesson opens on Numbers', () async {
      final FlashcardsController c =
          await settle(buildController(lessonId: 'c1-num-counting-1-10'));

      expect(c.category, FlashcardCategory.numbers);
      expect(c.lesson?.id, 'c1-num-counting-1-10');
    });

    test('cards belonging to that lesson come first', () async {
      final FlashcardsController c =
          await settle(buildController(lessonId: 'c1-num-counting-1-10'));

      expect(
        c.cards.first.lessonIds,
        contains('c1-num-counting-1-10'),
      );
    });

    test('with no lesson it still opens on a category that has cards',
        () async {
      final FlashcardsController c = await settle(buildController());

      expect(c.cards, isNotEmpty);
      expect(c.populatedCategories, contains(c.category));
    });
  });

  group('deck', () {
    testWidgets('shows the card count from the deck on screen', (
      WidgetTester tester,
    ) async {
      final FlashcardsController c = await pump(tester);

      expect(find.text('Card 1 of ${c.cards.length}'), findsOneWidget);
      expect(c.progress, closeTo(1 / c.cards.length, 0.001));
    });

    testWidgets('Next moves on and updates the count', (
      WidgetTester tester,
    ) async {
      final FlashcardsController c = await pump(tester);

      await tester.tap(find.byKey(FlashcardsScreen.nextKey));
      await tester.pumpAndSettle();

      expect(c.index, 1);
      expect(find.text('Card 2 of ${c.cards.length}'), findsOneWidget);
    });

    testWidgets('the right arrow does the same thing as Next', (
      WidgetTester tester,
    ) async {
      final FlashcardsController c = await pump(tester);

      await tester.tap(find.byKey(FlashcardsScreen.nextArrowKey));
      await tester.pumpAndSettle();

      expect(c.index, 1);
    });

    testWidgets('Previous is disabled on the first card', (
      WidgetTester tester,
    ) async {
      await pump(tester);

      expect(
        tester
            .widget<DeckControl>(find.byKey(FlashcardsScreen.previousKey))
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<DeckArrow>(find.byKey(FlashcardsScreen.previousArrowKey))
            .onPressed,
        isNull,
      );
    });

    testWidgets('Next is disabled on the last card, with a completion note', (
      WidgetTester tester,
    ) async {
      final FlashcardsController c = await pump(tester);
      for (int i = 0; i < c.cards.length - 1; i++) {
        await c.next();
      }
      await tester.pumpAndSettle();

      expect(c.isComplete, isTrue);
      expect(
        tester
            .widget<DeckControl>(find.byKey(FlashcardsScreen.nextKey))
            .onPressed,
        isNull,
      );
      expect(find.text('That is the last card in this set.'), findsOneWidget);
    });

    testWidgets('Previous goes back', (WidgetTester tester) async {
      final FlashcardsController c = await pump(tester);
      await c.next();
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(FlashcardsScreen.previousKey));
      await tester.pumpAndSettle();

      expect(c.index, 0);
    });

    testWidgets('swiping left moves to the next card', (
      WidgetTester tester,
    ) async {
      final FlashcardsController c = await pump(tester);

      await tester.fling(
        find.byKey(FlashcardsScreen.deckKey),
        const Offset(-320, 0),
        900,
      );
      await tester.pumpAndSettle();

      expect(c.index, 1);
    });

    testWidgets('swiping right goes back', (WidgetTester tester) async {
      final FlashcardsController c = await pump(tester);
      await c.next();
      await tester.pumpAndSettle();

      await tester.fling(
        find.byKey(FlashcardsScreen.deckKey),
        const Offset(320, 0),
        900,
      );
      await tester.pumpAndSettle();

      expect(c.index, 0);
    });

    testWidgets('moving on turns a flipped card back over', (
      WidgetTester tester,
    ) async {
      final FlashcardsController c = await pump(tester);

      c.flip();
      await tester.pumpAndSettle();
      expect(c.flipped, isTrue);

      await c.next();
      await tester.pumpAndSettle();
      expect(c.flipped, isFalse);
    });
  });

  group('flip', () {
    testWidgets('Flip Card turns the card over and back', (
      WidgetTester tester,
    ) async {
      final FlashcardsController c = await pump(tester);

      await tester.tap(find.byKey(FlashcardsScreen.flipKey));
      await tester.pumpAndSettle();
      expect(c.flipped, isTrue);

      await tester.tap(find.byKey(FlashcardsScreen.flipKey));
      await tester.pumpAndSettle();
      expect(c.flipped, isFalse);
    });

    testWidgets('the back shows the mother-tongue word', (
      WidgetTester tester,
    ) async {
      final FlashcardsController c =
          await pump(tester, lessonId: 'c1-num-counting-1-10');

      c.flip();
      await tester.pumpAndSettle();

      expect(find.text("mit'"), findsWidgets);
      expect(find.text('Tap to turn back'), findsOneWidget);
    });

    testWidgets('the back says a word has not been checked by a speaker', (
      WidgetTester tester,
    ) async {
      final FlashcardsController c =
          await pump(tester, lessonId: 'c1-num-counting-1-10');

      c.flip();
      await tester.pumpAndSettle();

      expect(
        find.textContaining('Not yet checked by a Santali speaker'),
        findsOneWidget,
      );
    });
  });

  group('categories', () {
    testWidgets('choosing a category shows only its cards', (
      WidgetTester tester,
    ) async {
      final FlashcardsController c = await pump(tester);

      await tapCategory(tester, FlashcardCategory.animals);

      expect(c.category, FlashcardCategory.animals);
      for (final Flashcard card in c.cards) {
        expect(card.category, FlashcardCategory.animals);
      }
      expect(find.text('गाय'), findsWidgets);
    });

    testWidgets('switching category starts again at the first card', (
      WidgetTester tester,
    ) async {
      final FlashcardsController c = await pump(tester);
      await c.next();
      await c.next();
      await tester.pumpAndSettle();
      expect(c.index, 2);

      await tapCategory(tester, FlashcardCategory.nature);

      expect(c.index, 0);
    });

    testWidgets('an empty category shows its empty state, not a broken card', (
      WidgetTester tester,
    ) async {
      final FlashcardsController c = await pump(tester);

      await tapCategory(tester, FlashcardCategory.actions);

      expect(c.isEmpty, isTrue);
      expect(find.text('No flashcards available'), findsOneWidget);
      expect(
        find.text('More learning cards will be available soon.'),
        findsOneWidget,
      );
      expect(find.text('Choose another category'), findsOneWidget);
    });

    testWidgets('every category is reachable', (WidgetTester tester) async {
      await pump(tester);

      for (final FlashcardCategory category in FlashcardCategory.values) {
        expect(
          find.byKey(FlashcardsScreen.categoryKey(category)),
          findsOneWidget,
        );
      }
    });
  });

  group('target language', () {
    testWidgets('reads the mother tongue from the classroom', (
      WidgetTester tester,
    ) async {
      final FlashcardsController c = await pump(tester);

      expect(c.targetLanguage, TargetLanguage.santali);
      expect(find.text('Santali'), findsWidgets);
    });

    testWidgets('a Mundari classroom shows Mundari', (
      WidgetTester tester,
    ) async {
      final FlashcardsController controller =
          buildController(target: TargetLanguage.mundari);
      await pump(tester, controller: controller);

      expect(controller.targetLanguage, TargetLanguage.mundari);
      expect(find.text('Mundari'), findsWidgets);
      expect(find.text('Santali'), findsNothing);
    });

    testWidgets('a Ho classroom shows Ho', (WidgetTester tester) async {
      final FlashcardsController controller =
          buildController(target: TargetLanguage.ho);
      await pump(tester, controller: controller);

      expect(controller.targetLanguage, TargetLanguage.ho);
      expect(find.text('Ho'), findsWidgets);
    });

    testWidgets('a card with no word for this language says so', (
      WidgetTester tester,
    ) async {
      final FlashcardsController controller =
          buildController(target: TargetLanguage.mundari, lessonId: null);
      await pump(tester, controller: controller);

      // Nothing is guessed for a language nobody has written words for.
      expect(controller.hasTranslation, isFalse);
      expect(find.text('Translation unavailable offline'), findsWidgets);
    });
  });

  group('bookmark', () {
    testWidgets('the bookmark button turns on and off, and persists', (
      WidgetTester tester,
    ) async {
      final FlashcardsController c = await pump(tester);
      final String id = c.current!.id;

      await tester.tap(find.byKey(FlashcardsScreen.bookmarkKey));
      await tester.pumpAndSettle();
      expect(c.isBookmarked, isTrue);
      expect(await flashcards.bookmarkedIds(), contains(id));

      await tester.tap(find.byKey(FlashcardsScreen.bookmarkKey));
      await tester.pumpAndSettle();
      expect(c.isBookmarked, isFalse);
    });

    testWidgets('bookmarked cards can be browsed on their own', (
      WidgetTester tester,
    ) async {
      final FlashcardsController c = await pump(tester);
      await c.toggleBookmark();
      await tester.pumpAndSettle();

      await c.showBookmarks();
      await tester.pumpAndSettle();

      expect(c.showingBookmarks, isTrue);
      expect(c.cards, hasLength(1));
      expect(find.text('Bookmarked cards'), findsOneWidget);
    });

    testWidgets('with nothing bookmarked it says so', (
      WidgetTester tester,
    ) async {
      final FlashcardsController c = await pump(tester);

      await c.showBookmarks();
      await tester.pumpAndSettle();

      expect(find.text('No bookmarked cards yet'), findsOneWidget);
    });
  });

  group('audio', () {
    testWidgets('Listen speaks the mother-tongue word', (
      WidgetTester tester,
    ) async {
      final FlashcardsController c =
          await pump(tester, lessonId: 'c1-num-counting-1-10');

      await tester.tap(find.byKey(FlashcardsScreen.listenKey));
      await tester.pumpAndSettle();

      // The Devanagari form is what the engine can pronounce; the Latin one
      // would be read as English.
      expect(tts.spoken.single, 'मित्');
      expect(c.speech, SpeechState.speaking);
      expect(find.text('Speaking…'), findsOneWidget);
    });

    testWidgets('a second tap stops rather than speaking twice', (
      WidgetTester tester,
    ) async {
      final FlashcardsController c =
          await pump(tester, lessonId: 'c1-num-counting-1-10');

      await tester.tap(find.byKey(FlashcardsScreen.listenKey));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(FlashcardsScreen.listenKey));
      await tester.pumpAndSettle();

      expect(tts.spoken, hasLength(1));
      expect(c.speech, SpeechState.idle);
    });

    testWidgets('a card with no word does not offer to read it', (
      WidgetTester tester,
    ) async {
      final FlashcardsController controller =
          buildController(target: TargetLanguage.ho);
      await pump(tester, controller: controller);

      expect(
        tester
            .widget<FilledButton>(find.byKey(FlashcardsScreen.listenKey))
            .onPressed,
        isNull,
      );
      expect(tts.spoken, isEmpty);
    });

    testWidgets('an engine failure is reported, not swallowed', (
      WidgetTester tester,
    ) async {
      tts.speakFails = true;
      final FlashcardsController c =
          await pump(tester, lessonId: 'c1-num-counting-1-10');

      await tester.tap(find.byKey(FlashcardsScreen.listenKey));
      await tester.pumpAndSettle();

      expect(c.speech, SpeechState.idle);
      expect(find.text('Audio is unavailable on this device.'), findsOneWidget);
    });
  });

  group('classroom', () {
    testWidgets('Use in Classroom adds the card to the lesson', (
      WidgetTester tester,
    ) async {
      final FlashcardsController c =
          await pump(tester, lessonId: 'c1-num-counting-1-10');
      final String id = c.current!.id;

      await tester.tap(find.byKey(FlashcardsScreen.classroomKey));
      await tester.pumpAndSettle();

      final List<ClassroomFlashcard> added =
          await flashcards.classroomCards(lessonId: 'c1-num-counting-1-10');
      expect(added, hasLength(1));
      expect(added.single.flashcardId, id);
      expect(added.single.classNumber, 1);
      expect(find.text('Added to classroom.'), findsOneWidget);
    });

    testWidgets('with no lesson it explains rather than failing quietly', (
      WidgetTester tester,
    ) async {
      final FlashcardsController c = await pump(tester);

      await tester.tap(find.byKey(FlashcardsScreen.classroomKey));
      await tester.pumpAndSettle();

      expect(c.canAddToClassroom, isFalse);
      expect(
        find.text('Open flashcards from a lesson to add cards to it.'),
        findsOneWidget,
      );
      expect(await flashcards.classroomCards(), isEmpty);
    });
  });

  group('progress', () {
    test('where the teacher had got to is remembered', () async {
      final FlashcardsController first =
          await settle(buildController(lessonId: 'c1-num-counting-1-10'));
      await first.next();
      await first.next();
      expect(first.index, 2);

      final FlashcardsController second =
          await settle(buildController(lessonId: 'c1-num-counting-1-10'));
      expect(second.index, 2);
    });

    test('a remembered position from a longer deck is not carried over',
        () async {
      await flashcards.setLastIndex(FlashcardCategory.animals, 90);
      final FlashcardsController c = await settle(buildController());
      await c.selectCategory(FlashcardCategory.animals);

      expect(c.index, 0);
      expect(c.index, lessThan(c.cards.length));
    });

    testWidgets('resetting clears bookmarks and positions', (
      WidgetTester tester,
    ) async {
      final FlashcardsController c = await pump(tester);
      await c.toggleBookmark();
      await c.next();
      await tester.pumpAndSettle();

      await c.resetProgress();
      await tester.pumpAndSettle();

      expect(await flashcards.bookmarkedIds(), isEmpty);
      expect(c.index, 0);
    });
  });

  group('states', () {
    testWidgets('a loading deck shows a skeleton, not a blank screen', (
      WidgetTester tester,
    ) async {
      final FlashcardsController c = buildController(
        repository: LocalFlashcardRepository(
          storage: storage,
          source: const SlowFlashcardDataSource(),
        ),
      );
      await tester.pumpWidget(
        MaterialApp(theme: AppTheme.light, home: FlashcardsScreen(controller: c)),
      );
      await tester.pump();

      expect(find.byKey(FlashcardsScreen.skeletonKey), findsOneWidget);

      await tester.pumpAndSettle(const Duration(milliseconds: 400));
      expect(find.byKey(FlashcardsScreen.skeletonKey), findsNothing);
    });

    testWidgets('a failure offers Retry and Back', (WidgetTester tester) async {
      final LocalFlashcardRepository failing = LocalFlashcardRepository(
        storage: storage,
        source: const FailingFlashcardDataSource(),
      );
      final FlashcardsController c = await pump(tester, repository: failing);

      expect(c.loadState, FlashcardsLoadState.error);
      expect(find.text("Couldn't load flashcards."), findsOneWidget);
      expect(find.byKey(FlashcardsScreen.retryKey), findsOneWidget);
      expect(find.text('Back'), findsOneWidget);
    });

    testWidgets('the header reports the real connectivity state', (
      WidgetTester tester,
    ) async {
      await pump(tester);
      // The header pill and the feature row both mention it, which is the
      // point; the pill is the one that tracks the device.
      expect(find.text('Offline Ready'), findsWidgets);

      connectivity.set(ConnectionStatus.online);
      await tester.pumpAndSettle();
      expect(find.text('Online'), findsOneWidget);
    });
  });

  group('chrome', () {
    testWidgets('carries GyanSetu AI branding and no other', (
      WidgetTester tester,
    ) async {
      await pump(tester);

      expect(
        find.textContaining('GyanSetu AI', findRichText: true),
        findsOneWidget,
      );
      expect(
        find.textContaining('BhashaSetu', findRichText: true),
        findsNothing,
      );
    });

    testWidgets('back returns to whatever pushed this screen', (
      WidgetTester tester,
    ) async {
      final FlashcardsController c = buildController();

      tester.view.physicalSize = const Size(430, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Builder(
            builder: (BuildContext context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => FlashcardsScreen(controller: c),
                    ),
                  ),
                  child: const Text('open flashcards'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open flashcards'));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(FlashcardsScreen.backKey));
      await tester.pumpAndSettle();

      expect(find.text('open flashcards'), findsOneWidget);
    });
  });

  group('layout', () {
    testWidgets('lays out on a small handset without overflow', (
      WidgetTester tester,
    ) async {
      await pump(tester, size: const Size(320, 1700));

      expect(tester.takeException(), isNull);
      expect(find.text('Visual Flashcards'), findsOneWidget);
    });

    testWidgets('lays out on a tablet-sized screen without overflow', (
      WidgetTester tester,
    ) async {
      await pump(tester, size: const Size(900, 1700));

      expect(tester.takeException(), isNull);
    });
  });
}
