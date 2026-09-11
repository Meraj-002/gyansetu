import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/routes.dart';
import '../../core/constants/app_assets.dart';
import '../../core/constants/app_colors.dart';
import '../../models/flashcard.dart';
import '../../services/audio/audio_resource_store.dart';
import '../../services/audio/lesson_audio_service.dart';
import '../../services/audio/text_to_speech_service.dart';
import '../../services/connectivity/connectivity_service.dart';
import '../../services/storage/secure_storage_service.dart';
import '../auth/services/auth_session_store.dart';
import '../lessons/services/lesson_repository.dart';
import '../progress/services/learning_progress_repository.dart';
import '../setup/data/classroom_setup_storage.dart';
import '../setup/services/classroom_setup_repository.dart';
import 'services/flashcard_recommendation_service.dart';
import 'services/flashcard_repository.dart';
import 'services/flashcards_controller.dart';
import 'widgets/flashcard_widgets.dart';

/// What the flashcards screen may be opened with.
///
/// A lesson is optional: the screen works on its own from Home, and simply
/// cannot add a card to a lesson when it does not have one.
class FlashcardsArgs {
  const FlashcardsArgs({this.lessonId, this.category});

  final String? lessonId;

  /// The deck to open on, when the caller knows which one it wants — Learning
  /// Insights pointing at Numbers for a counting weakness, say. Null lets the
  /// recommendation service choose from the lesson, as it always has.
  final FlashcardCategory? category;

  static String? lessonIdFrom(Object? arguments) => switch (arguments) {
        FlashcardsArgs(:final String? lessonId) => lessonId,
        final String id when id.isNotEmpty => id,
        _ => null,
      };

  static FlashcardCategory? categoryFrom(Object? arguments) =>
      switch (arguments) {
        FlashcardsArgs(:final FlashcardCategory? category) => category,
        _ => null,
      };
}

/// Picture cards for teaching a word in two languages.
///
/// The mother tongue comes from the saved classroom, the deck order comes from
/// the lesson the teacher arrived with, and every picture is bundled — so the
/// whole screen works with the radio off.
class FlashcardsScreen extends StatefulWidget {
  const FlashcardsScreen({
    this.lessonId,
    this.category,
    this.controller,
    this.flashcards,
    this.classrooms,
    this.audio,
    this.connectivity,
    this.lessons,
    this.recommendations,
    this.teacherId,
    super.key,
  });

  static const Key scrollKey = Key('flashcards-scroll');
  static const Key skeletonKey = Key('flashcards-skeleton');
  static const Key backKey = Key('flashcards-back');
  static const Key moreKey = Key('flashcards-more');
  static const Key statusKey = Key('flashcards-status');
  static const Key cardKey = Key('flashcards-card');
  static const Key deckKey = Key('flashcards-deck');
  static const Key bookmarkKey = Key('flashcards-bookmark');
  static const Key listenKey = Key('flashcards-listen');
  static const Key previousArrowKey = Key('flashcards-arrow-previous');
  static const Key nextArrowKey = Key('flashcards-arrow-next');
  static const Key previousKey = Key('flashcards-previous');
  static const Key flipKey = Key('flashcards-flip');
  static const Key nextKey = Key('flashcards-next');
  static const Key classroomKey = Key('flashcards-use-in-classroom');
  static const Key retryKey = Key('flashcards-retry');
  static const Key progressKey = Key('flashcards-progress');

  static Key categoryKey(FlashcardCategory value) =>
      Key('flashcards-category-${value.name}');

  final String? lessonId;

  /// The deck to open on, when the caller asked for one.
  final FlashcardCategory? category;

  /// Supplied whole by tests; built from the parts below otherwise.
  final FlashcardsController? controller;

  final FlashcardRepository? flashcards;
  final ClassroomSetupRepository? classrooms;
  final LessonAudioService? audio;
  final ConnectivityService? connectivity;
  final LessonRepository? lessons;
  final FlashcardRecommendationService? recommendations;
  final String? teacherId;

  @override
  State<FlashcardsScreen> createState() => _FlashcardsScreenState();
}

class _FlashcardsScreenState extends State<FlashcardsScreen> {
  FlashcardsController? _controller;
  ConnectivityService? _ownedConnectivity;
  LessonAudioService? _ownedAudio;

  PageController? _pages;

  /// The deck the pager was built for.
  String? _deckId;

  bool _built = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_built) return;
    _built = true;

    final FlashcardsController? given = widget.controller;
    if (given != null) {
      _controller = given;
      given.addListener(_syncPager);
      return;
    }

    final Object? routeArgs = ModalRoute.of(context)?.settings.arguments;
    final String? lessonId =
        widget.lessonId ?? FlashcardsArgs.lessonIdFrom(routeArgs);
    final FlashcardCategory? category =
        widget.category ?? FlashcardsArgs.categoryFrom(routeArgs);
    unawaited(_build(lessonId, category));
  }

  Future<void> _build(String? lessonId, FlashcardCategory? category) async {
    final SecureStorageService storage = PlatformSecureStorageService();
    final String teacherId = widget.teacherId ??
        (await AuthSessionStore(storage).account())?.id ??
        'local-teacher';
    if (!mounted) return;

    final ConnectivityService connectivity = widget.connectivity ??
        (_ownedConnectivity = PlatformConnectivityService());

    // The same audio layer the lesson and the classroom use, so a language
    // with no voice is reported the same way everywhere.
    final LessonAudioService audio = widget.audio ??
        (_ownedAudio = TtsLessonAudioService(
          tts: PlatformTextToSpeechService(),
          store: LocalAudioResourceStore(storage),
          connectivity: connectivity,
        ));

    final FlashcardsController controller = FlashcardsController(
      flashcards: widget.flashcards ??
          LocalFlashcardRepository(storage: storage),
      classrooms: widget.classrooms ??
          LocalClassroomSetupRepository(defaultClassroomSetupStorage()),
      audio: audio,
      connectivity: connectivity,
      teacherId: teacherId,
      recommendations: widget.recommendations,
      lessons: widget.lessons ??
          defaultLessonRepository(
            storage: storage,
            downloads: LocalLessonDownloadRepository(storage),
          ),
      lessonId: lessonId,
      openOn: category,
      recorder: ProgressRecorder(LocalLearningProgressRepository(storage)),
    )..addListener(_syncPager);

    setState(() => _controller = controller);
  }

  /// Keeps the swipeable deck and the controller's index in step when the
  /// index was changed by a button rather than a swipe.
  void _syncPager() {
    final FlashcardsController? c = _controller;
    final PageController? pages = _pages;
    if (c == null || pages == null || !pages.hasClients) return;

    final int shown = pages.page?.round() ?? pages.initialPage;
    if (shown == c.index) return;
    pages.animateToPage(
      c.index,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  void dispose() {
    _controller?.removeListener(_syncPager);
    if (widget.controller == null) _controller?.dispose();
    _pages?.dispose();
    unawaited(_ownedAudio?.dispose());
    unawaited(_ownedConnectivity?.dispose());
    super.dispose();
  }

  // --- Actions -------------------------------------------------------------

  Future<void> _openMenu(FlashcardsController c) async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (BuildContext sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const SizedBox(height: 10),
            Container(
              width: 42,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.outline,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(height: 8),
            ListTile(
              leading: Icon(
                c.showingBookmarks
                    ? Icons.grid_view_outlined
                    : Icons.bookmark_outline,
              ),
              title: Text(
                c.showingBookmarks ? 'Back to categories' : 'Bookmarked cards',
              ),
              onTap: () {
                Navigator.of(sheetContext).pop();
                if (c.showingBookmarks) {
                  c.showCategories();
                } else {
                  c.showBookmarks();
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.restart_alt),
              title: const Text('Reset flashcard progress'),
              subtitle: const Text('Clears bookmarks and saved positions'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                _confirmReset(c);
              },
            ),
            ListTile(
              leading: const Icon(Icons.info_outline),
              title: const Text('Offline information'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                _showOfflineInfo(c);
              },
            ),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmReset(FlashcardsController c) async {
    final bool? go = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('Reset flashcard progress?'),
        content: const Text(
          'This clears your bookmarks and where you had got to in each '
          'category. Cards you added to a lesson are kept.',
          style: TextStyle(height: 1.45),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.authNavy),
            child: const Text('Reset'),
          ),
        ],
      ),
    );
    if (go == true) await c.resetProgress();
  }

  void _showOfflineInfo(FlashcardsController c) {
    showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('Offline information'),
        content: Text(
          'Every picture and word on these cards is stored on this phone. '
          'Nothing is fetched while you teach, so the flashcards work with no '
          'connection.\n\n'
          'Reading a card aloud uses the phone’s own speech engine. Where it '
          'has no voice for ${c.targetLanguage.label}, the card says so rather '
          'than staying silent.',
          style: const TextStyle(fontSize: 14, height: 1.45),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  // --- Build ---------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final FlashcardsController? c = _controller;

    if (c == null) {
      return const _Shell(child: _Skeleton());
    }

    return AnimatedBuilder(
      animation: c,
      builder: (BuildContext context, _) {
        switch (c.loadState) {
          case FlashcardsLoadState.loading:
            return const _Shell(child: _Skeleton());
          case FlashcardsLoadState.error:
            return _Shell(
              child: _Message(
                icon: Icons.error_outline,
                title: "Couldn't load flashcards.",
                body: 'The cards are stored on this phone, so this is usually '
                    'worth another try.',
                actionLabel: 'Retry',
                onAction: c.load,
                secondaryLabel: 'Back',
                onSecondary: () => Navigator.of(context).maybePop(),
              ),
            );
          case FlashcardsLoadState.ready:
            return _ready(context, c);
        }
      },
    );
  }

  Widget _ready(BuildContext context, FlashcardsController c) {
    return Scaffold(
      backgroundColor: AppColors.homePage,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: <Widget>[
            _Header(
              status: c.offlineStatusLabel,
              onBack: () {
                final NavigatorState navigator = Navigator.of(context);
                if (navigator.canPop()) {
                  navigator.maybePop();
                } else {
                  AppRouter.replaceWithFade(context, AppRoutes.home);
                }
              },
              onMore: () => _openMenu(c),
            ),
            Expanded(
              child: LayoutBuilder(
                builder: (BuildContext context, BoxConstraints constraints) {
                  final double width = constraints.maxWidth;
                  final double contentWidth = width.clamp(0.0, 720.0);
                  final double side = ((width - contentWidth) / 2) + 16;

                  return ListView(
                    key: FlashcardsScreen.scrollKey,
                    padding: EdgeInsets.fromLTRB(side, 2, side, 22),
                    children: <Widget>[
                      _title(c),
                      const SizedBox(height: 14),
                      _categories(c),
                      const SizedBox(height: 16),
                      if (c.isEmpty)
                        _empty(c)
                      else ...<Widget>[
                        _deck(c, width),
                        const SizedBox(height: 14),
                        _controls(c),
                        const SizedBox(height: 14),
                        _progress(c),
                      ],
                      if (c.message != null) ...<Widget>[
                        const SizedBox(height: 14),
                        _Notice(
                          message: c.message!,
                          onDismiss: c.dismissMessage,
                        ),
                      ],
                      const SizedBox(height: 16),
                      _classroomCta(c),
                      const SizedBox(height: 14),
                      FeatureRow(
                        languagePair: c.languagePair,
                        bilingual: c.hasTranslation,
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _title(FlashcardsController c) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            'Visual Flashcards',
            maxLines: 1,
            style: TextStyle(
              fontSize: 30,
              height: 1.1,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.8,
              color: AppColors.brandNavy,
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          c.showingBookmarks
              ? 'Bookmarked cards'
              : 'Learn  •  Listen  •  Teach  •  Reinforce',
          style: TextStyle(
            fontSize: 14.5,
            color: AppColors.brandNavy.withValues(alpha: 0.68),
          ),
        ),
      ],
    );
  }

  Widget _categories(FlashcardsController c) {
    final Set<FlashcardCategory> populated = c.populatedCategories;

    return SizedBox(
      height: 54,
      // Scrolls, but builds every chip: a lazily built row would leave the
      // last categories unreachable on a narrow phone.
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: <Widget>[
            for (final FlashcardCategory category in FlashcardCategory.values)
              Padding(
                padding: const EdgeInsets.only(right: 10),
                child: CategoryChip(
                  key: FlashcardsScreen.categoryKey(category),
                  category: category,
                  selected: !c.showingBookmarks && c.category == category,
                  enabled: populated.contains(category),
                  onTap: () => c.selectCategory(category),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Identifies the deck on screen. Changing it rebuilds the pager, which is
  /// what stops a page from the previous deck being reported as the current
  /// card after a category change.
  String _deckIdentity(FlashcardsController c) =>
      '${c.showingBookmarks ? 'bookmarks' : c.category.name}'
      '#${c.cards.length}';

  /// The swipeable deck, flanked by the two arrows.
  Widget _deck(FlashcardsController c, double width) {
    final String identity = _deckIdentity(c);
    if (_deckId != identity) {
      _deckId = identity;
      _pages?.dispose();
      _pages = PageController(initialPage: c.index);
    }

    // Sized from the available width rather than a fixed height, so the card
    // stays readable from a 320dp phone to a tablet.
    final double cardWidth = (width - 32).clamp(0.0, 520.0);
    final double cardHeight = (cardWidth * 1.42).clamp(360.0, 620.0);

    return SizedBox(
      height: cardHeight,
      child: Stack(
        alignment: Alignment.center,
        children: <Widget>[
          PageView.builder(
            key: FlashcardsScreen.deckKey,
            controller: _pages,
            itemCount: c.cards.length,
            onPageChanged: c.goTo,
            itemBuilder: (BuildContext context, int index) {
              final Flashcard card = c.cards[index];
              final bool isCurrent = index == c.index;

              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: FlipCard(
                  flipped: isCurrent && c.flipped,
                  onTap: isCurrent ? c.flip : null,
                  front: _CardFace(
                    key: isCurrent ? FlashcardsScreen.cardKey : null,
                    controller: c,
                    card: card,
                    showBookmark: isCurrent,
                    onBookmark: isCurrent ? c.toggleBookmark : null,
                  ),
                  back: _CardBack(controller: c, card: card),
                ),
              );
            },
          ),
          Positioned(
            left: 0,
            child: DeckArrow(
              key: FlashcardsScreen.previousArrowKey,
              icon: Icons.arrow_back,
              label: 'Previous card',
              onPressed: c.hasPrevious ? c.previous : null,
            ),
          ),
          Positioned(
            right: 0,
            child: DeckArrow(
              key: FlashcardsScreen.nextArrowKey,
              icon: Icons.arrow_forward,
              label: 'Next card',
              onPressed: c.hasNext ? c.next : null,
            ),
          ),
        ],
      ),
    );
  }

  Widget _controls(FlashcardsController c) {
    return Row(
      children: <Widget>[
        Expanded(
          child: DeckControl(
            key: FlashcardsScreen.previousKey,
            icon: Icons.arrow_back,
            label: 'Previous',
            // The same action the left arrow performs.
            onPressed: c.hasPrevious ? c.previous : null,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: DeckControl(
            key: FlashcardsScreen.flipKey,
            icon: Icons.autorenew,
            label: 'Flip Card',
            onPressed: c.flip,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: DeckControl(
            key: FlashcardsScreen.nextKey,
            icon: Icons.arrow_forward,
            label: 'Next',
            iconOnRight: true,
            onPressed: c.hasNext ? c.next : null,
          ),
        ),
      ],
    );
  }

  Widget _progress(FlashcardsController c) {
    return Column(
      key: FlashcardsScreen.progressKey,
      children: <Widget>[
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: TweenAnimationBuilder<double>(
            tween: Tween<double>(begin: 0, end: c.progress),
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeOut,
            builder: (BuildContext context, double value, _) =>
                LinearProgressIndicator(
              value: value,
              minHeight: 6,
              backgroundColor: AppColors.outlineVariant,
              valueColor: const AlwaysStoppedAnimation<Color>(
                AppColors.authNavy,
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          // Counted from the deck on screen, never a fixed pair of numbers.
          'Card ${c.index + 1} of ${c.cards.length}',
          style: TextStyle(
            fontSize: 13.5,
            fontWeight: FontWeight.w600,
            color: AppColors.brandNavy.withValues(alpha: 0.72),
          ),
        ),
        if (c.isComplete && c.cards.length > 1) ...<Widget>[
          const SizedBox(height: 4),
          Text(
            'That is the last card in this set.',
            style: TextStyle(
              fontSize: 12.5,
              color: AppColors.setupLiteracy.withValues(alpha: 0.95),
            ),
          ),
        ],
      ],
    );
  }

  Widget _empty(FlashcardsController c) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.authFieldBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Icon(
            Icons.style_outlined,
            size: 34,
            color: AppColors.brandMuted,
          ),
          const SizedBox(height: 12),
          Text(
            c.showingBookmarks
                ? 'No bookmarked cards yet'
                : 'No flashcards available',
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: AppColors.brandNavy,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            c.showingBookmarks
                ? 'Tap the bookmark on a card to keep it here.'
                : 'More learning cards will be available soon.',
            style: TextStyle(
              fontSize: 13.5,
              height: 1.4,
              color: AppColors.brandNavy.withValues(alpha: 0.7),
            ),
          ),
          const SizedBox(height: 16),
          OutlinedButton(
            onPressed: () => c.selectCategory(
              c.populatedCategories.isEmpty
                  ? FlashcardCategory.numbers
                  : c.populatedCategories.first,
            ),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.brandNavy,
              minimumSize: const Size(0, 48),
              side: const BorderSide(color: AppColors.authFieldBorder),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text(
              'Choose another category',
              style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }

  Widget _classroomCta(FlashcardsController c) {
    final bool enabled = !c.isEmpty;

    return Semantics(
      button: true,
      enabled: enabled,
      label: 'Use this flashcard in the classroom',
      child: ExcludeSemantics(
        child: Material(
          color: enabled
              ? AppColors.setupLiteracy
              : AppColors.setupLiteracy.withValues(alpha: 0.45),
          borderRadius: BorderRadius.circular(15),
          child: InkWell(
            key: FlashcardsScreen.classroomKey,
            onTap: enabled ? c.useInClassroom : null,
            borderRadius: BorderRadius.circular(15),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 12, 16),
              child: Row(
                children: <Widget>[
                  Icon(
                    c.currentInClassroom
                        ? Icons.check_circle_outline
                        : Icons.co_present_outlined,
                    size: 28,
                    color: Colors.white,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          c.currentInClassroom
                              ? 'In your lesson'
                              : 'Use in Classroom',
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          c.canAddToClassroom
                              ? 'Add this flashcard to your lesson'
                              : 'Open flashcards from a lesson to add cards',
                          style: TextStyle(
                            fontSize: 13,
                            height: 1.3,
                            color: Colors.white.withValues(alpha: 0.9),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(
                    Icons.chevron_right,
                    size: 26,
                    color: Colors.white,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The front of a card: picture, both words, and Listen.
class _CardFace extends StatelessWidget {
  const _CardFace({
    required this.controller,
    required this.card,
    required this.showBookmark,
    this.onBookmark,
    super.key,
  });

  final FlashcardsController controller;
  final Flashcard card;
  final bool showBookmark;
  final VoidCallback? onBookmark;

  @override
  Widget build(BuildContext context) {
    final FlashcardTranslation? translation =
        card.translationFor(controller.targetLanguage);
    final bool speaking = controller.speech == SpeechState.speaking;

    return _Paper(
      child: Column(
        children: <Widget>[
          Expanded(
            child: Stack(
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 18, 18, 6),
                  child: FlashcardVisual(card: card),
                ),
                if (showBookmark)
                  Positioned(
                    top: 0,
                    right: 0,
                    child: Semantics(
                      button: true,
                      selected: controller.isBookmarked,
                      label: controller.isBookmarked
                          ? 'Remove bookmark'
                          : 'Bookmark this card',
                      child: ExcludeSemantics(
                        child: Material(
                          color: Colors.white,
                          shape: const CircleBorder(
                            side: BorderSide(color: AppColors.authFieldBorder),
                          ),
                          child: InkWell(
                            key: FlashcardsScreen.bookmarkKey,
                            onTap: onBookmark,
                            customBorder: const CircleBorder(),
                            child: SizedBox(
                              width: 46,
                              height: 46,
                              child: Icon(
                                controller.isBookmarked
                                    ? Icons.bookmark
                                    : Icons.bookmark_outline,
                                size: 22,
                                color: controller.isBookmarked
                                    ? AppColors.brandGold
                                    : AppColors.brandNavy,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Align(
                  alignment: Alignment.centerLeft,
                  child: LanguageTag(
                    label: controller.teachingMedium.label,
                    tint: AppColors.brandGold,
                  ),
                ),
                const SizedBox(height: 6),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    card.hindiWord,
                    maxLines: 1,
                    style: const TextStyle(
                      fontSize: 34,
                      height: 1.15,
                      fontWeight: FontWeight.w800,
                      color: AppColors.authNavy,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                const Divider(height: 1, color: AppColors.outlineVariant),
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerLeft,
                  child: LanguageTag(
                    // From the saved classroom, never a constant.
                    label: controller.targetLanguage.label,
                    tint: AppColors.setupLiteracy,
                  ),
                ),
                const SizedBox(height: 6),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    // Nothing is guessed: a card with no word for this
                    // language says so.
                    translation?.word ?? 'Translation unavailable offline',
                    maxLines: 1,
                    style: TextStyle(
                      fontSize: translation == null ? 17 : 32,
                      height: 1.15,
                      fontWeight: FontWeight.w700,
                      color: translation == null
                          ? AppColors.brandNavy.withValues(alpha: 0.55)
                          : AppColors.setupLiteracy,
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Semantics(
                  button: true,
                  enabled: translation != null,
                  label: speaking
                      ? 'Stop the audio'
                      : 'Listen to the '
                          '${controller.targetLanguage.label} word',
                  child: ExcludeSemantics(
                    child: FilledButton(
                      key: FlashcardsScreen.listenKey,
                      onPressed: translation == null
                          ? null
                          : controller.listen,
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.authNavy,
                        foregroundColor: Colors.white,
                        disabledBackgroundColor:
                            AppColors.brandMuted.withValues(alpha: 0.3),
                        minimumSize: const Size(0, 54),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(27),
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: <Widget>[
                          Icon(
                            speaking ? Icons.stop : Icons.play_arrow,
                            size: 22,
                          ),
                          const SizedBox(width: 10),
                          Flexible(
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                speaking ? 'Speaking…' : 'Listen',
                                maxLines: 1,
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          const Icon(Icons.volume_up, size: 20),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The back of a card: the mother-tongue word, how to say it, and the lesson
/// it belongs with.
class _CardBack extends StatelessWidget {
  const _CardBack({required this.controller, required this.card});

  final FlashcardsController controller;
  final Flashcard card;

  @override
  Widget build(BuildContext context) {
    final FlashcardTranslation? translation =
        card.translationFor(controller.targetLanguage);

    return _Paper(
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            LanguageTag(
              label: controller.targetLanguage.label,
              tint: AppColors.setupLiteracy,
            ),
            const SizedBox(height: 10),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                translation?.word ?? 'Translation unavailable offline',
                maxLines: 1,
                style: TextStyle(
                  fontSize: translation == null ? 20 : 38,
                  height: 1.1,
                  fontWeight: FontWeight.w800,
                  color: translation == null
                      ? AppColors.brandNavy.withValues(alpha: 0.55)
                      : AppColors.setupLiteracy,
                ),
              ),
            ),
            if (translation?.pronunciation != null) ...<Widget>[
              const SizedBox(height: 12),
              Text(
                'Pronunciation',
                style: TextStyle(
                  fontSize: 12.5,
                  color: AppColors.brandNavy.withValues(alpha: 0.6),
                ),
              ),
              Text(
                translation!.pronunciation!,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  color: AppColors.brandNavy,
                ),
              ),
            ],
            if (translation != null && !translation.reviewedBySpeaker) ...<Widget>[
              const SizedBox(height: 12),
              Text(
                // Said plainly: this word has not been checked by a speaker.
                'Not yet checked by a '
                '${controller.targetLanguage.label} speaker.',
                style: TextStyle(
                  fontSize: 12,
                  height: 1.35,
                  color: AppColors.brandNavy.withValues(alpha: 0.55),
                ),
              ),
            ],
            const SizedBox(height: 18),
            const Divider(height: 1, color: AppColors.outlineVariant),
            const SizedBox(height: 14),
            Text(
              '${controller.teachingMedium.label}: ${card.hindiWord}',
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: AppColors.authNavy,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              card.category.label,
              style: TextStyle(
                fontSize: 13,
                color: AppColors.brandNavy.withValues(alpha: 0.6),
              ),
            ),
            const Spacer(),
            Row(
              children: <Widget>[
                Icon(
                  Icons.touch_app_outlined,
                  size: 16,
                  color: AppColors.brandNavy.withValues(alpha: 0.5),
                ),
                const SizedBox(width: 7),
                Text(
                  'Tap to turn back',
                  style: TextStyle(
                    fontSize: 12.5,
                    color: AppColors.brandNavy.withValues(alpha: 0.55),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Paper extends StatelessWidget {
  const _Paper({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          color: AppColors.brandCreamWarm.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: AppColors.outlineVariant),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: AppColors.brandNavy.withValues(alpha: 0.08),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: ColoredBox(color: Colors.white.withValues(alpha: 0.55), child: child),
      );
}

/// Back, branding, offline status, options.
class _Header extends StatelessWidget {
  const _Header({
    required this.status,
    required this.onBack,
    required this.onMore,
  });

  final String status;
  final VoidCallback onBack;
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final bool showWordmark = constraints.maxWidth >= 380;

        return Padding(
          padding: const EdgeInsets.fromLTRB(2, 4, 6, 4),
          child: Row(
            children: <Widget>[
              IconButton(
                key: FlashcardsScreen.backKey,
                onPressed: onBack,
                tooltip: 'Back',
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.arrow_back, size: 23),
                color: AppColors.brandNavy,
              ),
              Image.asset(
                AppAssets.loginBrandMark,
                height: 30,
                filterQuality: FilterQuality.medium,
                excludeFromSemantics: true,
              ),
              if (showWordmark) ...<Widget>[
                const SizedBox(width: 8),
                Flexible(
                  child: Semantics(
                    label: 'GyanSetu AI',
                    child: ExcludeSemantics(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text.rich(
                          TextSpan(
                            children: const <InlineSpan>[
                              TextSpan(
                                text: 'GyanSetu',
                                style: TextStyle(color: AppColors.brandNavy),
                              ),
                              TextSpan(text: ' '),
                              TextSpan(
                                text: 'AI',
                                style: TextStyle(color: AppColors.brandOrange),
                              ),
                            ],
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.3,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ] else
                Semantics(
                  label: 'GyanSetu AI',
                  child: const SizedBox.shrink(),
                ),
              const Spacer(),
              Semantics(
                key: FlashcardsScreen.statusKey,
                liveRegion: true,
                label: status,
                child: ExcludeSemantics(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 11,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: AppColors.authFieldBorder),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Container(
                          width: 9,
                          height: 9,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: AppColors.setupLiteracy,
                          ),
                        ),
                        const SizedBox(width: 8),
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 120),
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              status,
                              maxLines: 1,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: AppColors.setupLiteracy,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              IconButton(
                key: FlashcardsScreen.moreKey,
                onPressed: onMore,
                tooltip: 'Flashcard options',
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.more_vert, size: 21),
                color: AppColors.brandNavy,
              ),
            ],
          ),
        );
      },
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.message, required this.onDismiss});

  final String message;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 4, 10),
      decoration: BoxDecoration(
        color: AppColors.homeBannerTint,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.brandGold.withValues(alpha: 0.42)),
      ),
      child: Row(
        children: <Widget>[
          const Icon(
            Icons.info_outline,
            size: 18,
            color: AppColors.secondaryDark,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                fontSize: 13.5,
                height: 1.4,
                color: AppColors.brandNavy.withValues(alpha: 0.88),
              ),
            ),
          ),
          IconButton(
            onPressed: onDismiss,
            tooltip: 'Dismiss',
            icon: const Icon(Icons.close, size: 17),
            color: AppColors.brandNavy.withValues(alpha: 0.6),
          ),
        ],
      ),
    );
  }
}

class _Shell extends StatelessWidget {
  const _Shell({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: AppColors.homePage,
        appBar: AppBar(
          backgroundColor: AppColors.homePage,
          foregroundColor: AppColors.brandNavy,
          elevation: 0,
          title: const Text('Visual Flashcards'),
        ),
        body: SafeArea(child: child),
      );
}

class _Skeleton extends StatelessWidget {
  const _Skeleton();

  @override
  Widget build(BuildContext context) {
    Widget bar(double width, double height) => Container(
          width: width,
          height: height,
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: AppColors.surfaceVariant,
            borderRadius: BorderRadius.circular(10),
          ),
        );

    return ListView(
      key: FlashcardsScreen.skeletonKey,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: <Widget>[
        bar(200, 30),
        bar(double.infinity, 52),
        const SizedBox(height: 8),
        bar(double.infinity, 380),
        bar(double.infinity, 52),
      ],
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({
    required this.icon,
    required this.title,
    required this.body,
    this.actionLabel,
    this.onAction,
    this.secondaryLabel,
    this.onSecondary,
  });

  final IconData icon;
  final String title;
  final String body;
  final String? actionLabel;
  final VoidCallback? onAction;
  final String? secondaryLabel;
  final VoidCallback? onSecondary;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, size: 38, color: AppColors.brandMuted),
            const SizedBox(height: 14),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppColors.brandNavy,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              body,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13.5,
                height: 1.4,
                color: AppColors.brandNavy.withValues(alpha: 0.7),
              ),
            ),
            if (actionLabel != null && onAction != null) ...<Widget>[
              const SizedBox(height: 18),
              FilledButton(
                key: FlashcardsScreen.retryKey,
                onPressed: onAction,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.authNavy,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(0, 48),
                ),
                child: Text(actionLabel!),
              ),
            ],
            if (secondaryLabel != null && onSecondary != null) ...<Widget>[
              const SizedBox(height: 10),
              TextButton(
                onPressed: onSecondary,
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.brandNavy,
                  minimumSize: const Size(48, 44),
                ),
                child: Text(secondaryLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
