// ignore_for_file: prefer_initializing_formals
// Private fields cannot be initialising formals: a named parameter may not
// start with an underscore.
import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../core/utils/app_logger.dart';
import '../../../models/flashcard.dart';
import '../../../models/lesson.dart';
import '../../../models/progress_event.dart';
import '../../../services/audio/lesson_audio_service.dart';
import '../../../services/connectivity/connectivity_service.dart';
import '../../lessons/services/lesson_repository.dart';
import '../../progress/services/learning_progress_repository.dart';
import '../../setup/models/classroom_setup.dart';
import '../../setup/services/classroom_setup_repository.dart';
import 'flashcard_recommendation_service.dart';
import 'flashcard_repository.dart';

/// Where the screen is in its own lifecycle.
enum FlashcardsLoadState { loading, ready, error }

/// What the Listen button is doing.
enum SpeechState { idle, speaking }

/// Drives the flashcards screen.
///
/// Holds which category is showing, which card, whether it is flipped and what
/// the audio is doing. It knows nothing about where cards come from, how they
/// are stored, or how speech is produced.
class FlashcardsController extends ChangeNotifier {
  FlashcardsController({
    required FlashcardRepository flashcards,
    required ClassroomSetupRepository classrooms,
    required LessonAudioService audio,
    required ConnectivityService connectivity,
    required String teacherId,
    FlashcardRecommendationService? recommendations,
    LessonRepository? lessons,
    String? lessonId,
    FlashcardCategory? openOn,
    ProgressRecorder recorder = const ProgressRecorder.none(),
  })  : _flashcards = flashcards,
        _classrooms = classrooms,
        _audio = audio,
        _connectivity = connectivity,
        _teacherId = teacherId,
        _recommendations =
            recommendations ?? const LocalFlashcardRecommendationService(),
        _lessons = lessons,
        _lessonId = lessonId,
        _openOn = openOn,
        _recorder = recorder {
    _playbackSubscription = _audio.states.listen(_onPlayback);
    _connectionStatus = _connectivity.status;
    _connectivitySubscription =
        _connectivity.onStatusChanged.listen((ConnectionStatus status) {
      _connectionStatus = status;
      notifyListeners();
    });
    unawaited(load());
  }

  final FlashcardRepository _flashcards;
  final ClassroomSetupRepository _classrooms;
  final LessonAudioService _audio;
  final ConnectivityService _connectivity;
  final FlashcardRecommendationService _recommendations;
  final LessonRepository? _lessons;
  final String _teacherId;
  final String? _lessonId;

  /// The deck the caller asked to land on. Overrides the recommendation, which
  /// is what lets Learning Insights send a teacher straight to Numbers.
  final FlashcardCategory? _openOn;

  /// Writes flashcard use to the progress log, so Learning Insights can count
  /// a week in which the cards were used rather than only the lessons.
  final ProgressRecorder _recorder;

  /// Cards already recorded as seen this session, so paging back and forth
  /// does not log the same card ten times.
  final Set<String> _seen = <String>{};

  StreamSubscription<PlaybackState>? _playbackSubscription;
  StreamSubscription<ConnectionStatus>? _connectivitySubscription;

  // --- Loaded context ------------------------------------------------------

  FlashcardsLoadState _loadState = FlashcardsLoadState.loading;
  FlashcardsLoadState get loadState => _loadState;

  List<Flashcard> _catalogue = const <Flashcard>[];

  ClassroomSetup? _classroom;
  ClassroomSetup? get classroom => _classroom;

  Lesson? _lesson;

  /// The lesson the teacher came from, when they came from one.
  Lesson? get lesson => _lesson;

  Set<String> _bookmarks = <String>{};

  ConnectionStatus _connectionStatus = ConnectionStatus.unknown;

  /// The mother tongue this classroom teaches into. Every label naming a
  /// language reads this, never a constant.
  TargetLanguage get targetLanguage {
    // Python lesson uses English as its target language.
    if (_lesson?.id == 'python-intro') return TargetLanguage.english;
    return _classroom?.targetLanguage ?? TargetLanguage.santali;
  }

  TeachingMedium get teachingMedium =>
      _classroom?.teachingMedium ?? TeachingMedium.hindi;

  String get languagePair =>
      '${teachingMedium.label} + ${targetLanguage.label}';

  /// What the header pill may claim, from the device's real state.
  String get offlineStatusLabel => switch (_connectionStatus) {
        ConnectionStatus.offline => 'Offline Ready',
        ConnectionStatus.online => 'Online',
        ConnectionStatus.unknown => 'Checking…',
      };

  // --- What is showing -----------------------------------------------------

  FlashcardCategory _category = FlashcardCategory.numbers;
  FlashcardCategory get category => _category;

  /// True when the teacher is looking at their bookmarks rather than a
  /// category.
  bool _showingBookmarks = false;
  bool get showingBookmarks => _showingBookmarks;

  List<Flashcard> _cards = const <Flashcard>[];

  /// The cards currently being flipped through.
  List<Flashcard> get cards => _cards;

  int _index = 0;
  int get index => _index;

  bool _flipped = false;
  bool get flipped => _flipped;

  SpeechState _speech = SpeechState.idle;
  SpeechState get speech => _speech;

  String? _message;

  /// A note for the teacher — a confirmation, or a reason something cannot be
  /// done. Never an exception.
  String? get message => _message;

  void dismissMessage() {
    if (_message == null) return;
    _message = null;
    notifyListeners();
  }

  bool get isEmpty => _cards.isEmpty;

  Flashcard? get current =>
      _cards.isEmpty ? null : _cards[_index.clamp(0, _cards.length - 1)];

  bool get hasNext => _index < _cards.length - 1;

  bool get hasPrevious => _index > 0;

  /// True on the last card, which is where the deck reports itself finished
  /// rather than looping quietly back to the start.
  bool get isComplete => _cards.isNotEmpty && _index == _cards.length - 1;

  /// 0..1, for the bar under the card.
  double get progress =>
      _cards.isEmpty ? 0 : (_index + 1) / _cards.length;

  bool get isBookmarked {
    final Flashcard? card = current;
    return card != null && _bookmarks.contains(card.id);
  }

  /// The mother-tongue word for the card on screen, or null when nobody has
  /// written one. Null is shown as "translation unavailable", never guessed.
  FlashcardTranslation? get currentTranslation =>
      current?.translationFor(targetLanguage);

  bool get hasTranslation => currentTranslation != null;

  /// Which categories actually hold cards, so an empty one is not offered as
  /// though it did.
  Set<FlashcardCategory> get populatedCategories => <FlashcardCategory>{
        for (final Flashcard c in _catalogue) c.category,
      };

  // --- Loading -------------------------------------------------------------

  Future<void> load() async {
    _loadState = FlashcardsLoadState.loading;
    notifyListeners();

    try {
      _catalogue = await _flashcards.all();
      _classroom = await _classrooms.load(_teacherId);
      _bookmarks = await _flashcards.bookmarkedIds();

      final String? lessonId = _lessonId;
      if (lessonId != null && _lessons != null) {
        _lesson = await _lessons.lessonById(lessonId);
      }

      _category = _openOn ??
          _recommendations.openingCategory(
            lesson: _lesson,
            classroom: _classroom,
            available: _catalogue,
          );
      await _applyCategory(restoreIndex: true);

      _loadState = FlashcardsLoadState.ready;
      _noteViewed();
    } on Object catch (error) {
      AppLogger.error('flashcards could not be loaded', error: error);
      _loadState = FlashcardsLoadState.error;
    }
    notifyListeners();
  }

  Future<void> _applyCategory({bool restoreIndex = false}) async {
    _cards = _recommendations.order(
      _catalogue.where((Flashcard c) => c.category == _category).toList(),
      lesson: _lesson,
      classroom: _classroom,
    );
    _flipped = false;

    if (restoreIndex && _cards.isNotEmpty) {
      final int saved = await _flashcards.lastIndexFor(_category);
      // A remembered position from a longer deck must not survive into a
      // shorter one.
      _index = saved.clamp(0, _cards.length - 1);
    } else {
      _index = 0;
    }
  }

  // --- Categories ----------------------------------------------------------

  Future<void> selectCategory(FlashcardCategory category) async {
    if (_category == category && !_showingBookmarks) return;

    await _stopSpeech();
    _category = category;
    _showingBookmarks = false;
    _message = null;
    // Switching category starts at the first card, as the teacher expects.
    await _applyCategory();
    notifyListeners();
    unawaited(_flashcards.setLastIndex(_category, _index));
  }

  /// Shows only the cards the teacher bookmarked.
  Future<void> showBookmarks() async {
    await _stopSpeech();
    final List<Flashcard> saved = await _flashcards.bookmarked();
    _showingBookmarks = true;
    _cards = _recommendations.order(
      saved,
      lesson: _lesson,
      classroom: _classroom,
    );
    _index = 0;
    _flipped = false;
    _message = saved.isEmpty ? 'No cards are bookmarked yet.' : null;
    notifyListeners();
  }

  Future<void> showCategories() => selectCategory(_category);

  // --- Moving through the deck ---------------------------------------------

  Future<void> next() async {
    if (!hasNext) return;
    await _moveTo(_index + 1);
  }

  Future<void> previous() async {
    if (!hasPrevious) return;
    await _moveTo(_index - 1);
  }

  /// Used by the swipe, which reports the page it landed on.
  Future<void> goTo(int index) async {
    if (index < 0 || index >= _cards.length || index == _index) return;
    await _moveTo(index);
  }

  Future<void> _moveTo(int index) async {
    await _stopSpeech();
    _index = index;
    _flipped = false;
    _message = null;
    notifyListeners();
    if (!_showingBookmarks) {
      unawaited(_flashcards.setLastIndex(_category, _index));
    }
    _noteViewed();
    // Reaching the last card is the only thing this feature has that means
    // "finished"; there is nothing else to call completion.
    if (isComplete) {
      unawaited(
        _recorder.record(
          ProgressEventType.flashcardCompleted,
          lessonId: _lessonId,
          metadata: <String, String>{
            'category': _category.name,
            'cards': '${_cards.length}',
          },
        ),
      );
    }
  }

  /// Records the card on screen as seen, once per card per session.
  void _noteViewed() {
    final Flashcard? card = current;
    if (card == null || !_seen.add(card.id)) return;
    unawaited(
      _recorder.record(
        ProgressEventType.flashcardViewed,
        lessonId: _lessonId,
        metadata: <String, String>{
          'flashcardId': card.id,
          'category': card.category.name,
        },
      ),
    );
  }

  void flip() {
    if (current == null) return;
    _flipped = !_flipped;
    notifyListeners();
  }

  // --- Bookmark ------------------------------------------------------------

  Future<void> toggleBookmark() async {
    final Flashcard? card = current;
    if (card == null) return;

    final bool nowBookmarked = await _flashcards.toggleBookmark(card.id);
    _bookmarks = await _flashcards.bookmarkedIds();
    _message = nowBookmarked ? 'Bookmarked.' : 'Bookmark removed.';

    // Removing the last bookmark while looking at bookmarks would otherwise
    // leave a card on screen that is no longer in the list.
    if (_showingBookmarks && !nowBookmarked) {
      await showBookmarks();
      return;
    }
    notifyListeners();
  }

  // --- Audio ---------------------------------------------------------------

  /// Reads the mother-tongue word aloud.
  ///
  /// Goes through the same audio layer the rest of the app uses, so a language
  /// with no voice is reported honestly rather than silently doing nothing.
  Future<void> listen() async {
    final Flashcard? card = current;
    final FlashcardTranslation? translation = currentTranslation;
    if (card == null) return;

    if (_speech == SpeechState.speaking) {
      await _stopSpeech();
      return;
    }
    if (translation == null) {
      _message = 'There is no ${targetLanguage.label} word for this card yet.';
      notifyListeners();
      return;
    }

    _message = null;
    final AudioRequestOutcome outcome = await _audio.play(
      SpokenPassage(
        lessonId: 'flashcard-${card.id}',
        label: targetLanguage.label,
        displayText: translation.word,
        localeId: targetLanguage.localeId,
        spokenText: translation.spokenText,
        // Devanagari is the script the spoken form is written in, so an Indic
        // voice is the one that can pronounce it.
        spokenScriptLocaleId: translation.spokenText == null
            ? null
            : teachingMedium.localeId,
        textHash: card.id,
      ),
    );

    switch (outcome) {
      case AudioStarted():
        _speech = SpeechState.speaking;
      case AudioBlocked(:final String message):
        _speech = SpeechState.idle;
        _message = message;
      case AudioFailed():
        _speech = SpeechState.idle;
        _message = 'Audio is unavailable on this device.';
    }
    notifyListeners();
  }

  Future<void> _stopSpeech() async {
    if (_speech == SpeechState.idle) return;
    await _audio.stop();
    _speech = SpeechState.idle;
  }

  void _onPlayback(PlaybackState state) {
    final SpeechState next = state == PlaybackState.playing
        ? SpeechState.speaking
        : SpeechState.idle;
    if (next == _speech) return;
    _speech = next;
    notifyListeners();
  }

  // --- Classroom -----------------------------------------------------------

  /// True when there is a lesson to add a card to.
  bool get canAddToClassroom => _lesson != null || _lessonId != null;

  bool _inClassroom = false;

  /// True when the card on screen is already in the lesson.
  bool get currentInClassroom => _inClassroom;

  /// Adds the card on screen to the lesson the teacher came from.
  Future<void> useInClassroom() async {
    final Flashcard? card = current;
    final String? lessonId = _lesson?.id ?? _lessonId;
    if (card == null) return;

    if (lessonId == null) {
      _message = 'Open flashcards from a lesson to add cards to it.';
      notifyListeners();
      return;
    }

    try {
      await _flashcards.addToClassroom(
        flashcardId: card.id,
        lessonId: lessonId,
        classNumber: _classroom?.classLevel ?? card.classNumber ?? 1,
      );
      _inClassroom = true;
      _message = 'Added to classroom.';
    } on Object catch (error) {
      AppLogger.error('flashcard could not be added', error: error);
      _message = "Couldn't add this card to the lesson.";
    }
    notifyListeners();
  }

  /// Re-reads whether the card on screen is already in the lesson.
  Future<void> refreshClassroomState() async {
    final Flashcard? card = current;
    final String? lessonId = _lesson?.id ?? _lessonId;
    if (card == null || lessonId == null) {
      _inClassroom = false;
      return;
    }
    _inClassroom = await _flashcards.isInClassroom(card.id, lessonId);
    notifyListeners();
  }

  // --- Progress ------------------------------------------------------------

  Future<void> resetProgress() async {
    await _flashcards.resetProgress();
    _bookmarks = <String>{};
    _showingBookmarks = false;
    await _applyCategory();
    _message = 'Flashcard progress reset.';
    notifyListeners();
  }

  @override
  void dispose() {
    unawaited(_playbackSubscription?.cancel());
    unawaited(_connectivitySubscription?.cancel());
    unawaited(_audio.stop());
    super.dispose();
  }
}
