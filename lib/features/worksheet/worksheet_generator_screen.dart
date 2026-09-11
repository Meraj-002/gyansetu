import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/routes.dart';
import '../../core/constants/app_assets.dart';
import '../../core/constants/app_colors.dart';
import '../../models/question.dart';
import '../../models/worksheet.dart';
import '../../services/connectivity/connectivity_service.dart';
import '../../services/service_registry.dart';
import '../../services/storage/secure_storage_service.dart';
import '../../services/translation/cached_text_translation_service.dart';
import '../../services/translation/development_text_translation_service.dart';
import '../auth/services/auth_session_store.dart';
import '../lessons/services/lesson_repository.dart';
import '../setup/data/classroom_setup_storage.dart';
import '../setup/services/classroom_setup_repository.dart';
import 'services/local_worksheet_generation_service.dart';
import 'services/worksheet_generation_service.dart';
import 'services/worksheet_generator_controller.dart';
import 'services/worksheet_repository.dart';
import 'widgets/worksheet_widgets.dart';
import 'worksheet_preview_screen.dart' show WorksheetPreviewArgs;

/// What the worksheet generator is opened with.
class WorksheetGeneratorArgs {
  const WorksheetGeneratorArgs(this.lessonId);

  final String lessonId;

  static String? lessonIdFrom(Object? arguments) => switch (arguments) {
        WorksheetGeneratorArgs(:final String lessonId) => lessonId,
        final String id when id.isNotEmpty => id,
        _ => null,
      };
}

/// Builds a printable worksheet for the lesson the teacher came from.
///
/// The lesson and the classroom decide everything the worksheet is aligned to:
/// the number range comes out of the lesson's own learning outcome, the class
/// and both languages come from the saved classroom, and the concepts come from
/// the lesson. Nothing on this screen is a constant standing in for one of
/// those.
class WorksheetGeneratorScreen extends StatefulWidget {
  const WorksheetGeneratorScreen({
    this.lessonId,
    this.controller,
    this.lessons,
    this.classrooms,
    this.generator,
    this.worksheets,
    this.connectivity,
    this.storage,
    this.teacherId,
    super.key,
  });

  static const Key scrollKey = Key('worksheet-scroll');
  static const Key backKey = Key('worksheet-back');
  static const Key moreKey = Key('worksheet-more');
  static const Key statusKey = Key('worksheet-status');
  static const Key generateKey = Key('worksheet-generate');
  static const Key culturalToggleKey = Key('worksheet-cultural-toggle');

  static Key difficultyKey(WorksheetDifficulty value) =>
      Key('worksheet-difficulty-${value.name}');

  static Key questionTypeKey(QuestionType value) =>
      Key('worksheet-type-${value.name}');

  static Key countKey(int value) => Key('worksheet-count-$value');

  static Key visualKey(VisualExample value) =>
      Key('worksheet-visual-${value.name}');

  final String? lessonId;

  /// Supplied whole by tests; built from the parts below otherwise.
  final WorksheetGeneratorController? controller;

  final LessonRepository? lessons;
  final ClassroomSetupRepository? classrooms;
  final WorksheetGenerationService? generator;
  final WorksheetRepository? worksheets;
  final ConnectivityService? connectivity;
  final SecureStorageService? storage;
  final String? teacherId;

  @override
  State<WorksheetGeneratorScreen> createState() =>
      _WorksheetGeneratorScreenState();
}

class _WorksheetGeneratorScreenState extends State<WorksheetGeneratorScreen> {
  WorksheetGeneratorController? _controller;
  ConnectivityService? _ownedConnectivity;
  bool _built = false;

  /// Set as soon as the route's argument is read, before the controller has
  /// been assembled. Without it the screen showed "no lesson was chosen" for
  /// the frames it takes to resolve the teacher, which is a different thing
  /// from having no lesson.
  String? _pendingLessonId;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_built) return;
    _built = true;

    final WorksheetGeneratorController? given = widget.controller;
    if (given != null) {
      _controller = given;
      return;
    }

    final Object? routeArgs = ModalRoute.of(context)?.settings.arguments;
    final String? lessonId =
        widget.lessonId ?? WorksheetGeneratorArgs.lessonIdFrom(routeArgs);
    _pendingLessonId = lessonId;
    if (lessonId != null) unawaited(_build(lessonId));
  }

  Future<void> _build(String lessonId) async {
    final SecureStorageService storage =
        widget.storage ?? PlatformSecureStorageService();
    final String teacherId = widget.teacherId ??
        (await AuthSessionStore(storage).account())?.id ??
        'local-teacher';
    if (!mounted) return;

    final ConnectivityService connectivity = widget.connectivity ??
        (_ownedConnectivity = PlatformConnectivityService());

    setState(() {
      _controller = WorksheetGeneratorController(
        lessonId: lessonId,
        lessons: widget.lessons ??
            defaultLessonRepository(
              storage: storage,
              downloads: LocalLessonDownloadRepository(storage),
            ),
        classrooms: widget.classrooms ??
            LocalClassroomSetupRepository(defaultClassroomSetupStorage()),
        // DEVELOPMENT OFFLINE FALLBACK. Swap for the FastAPI-backed generator
        // and nothing above this line changes.
        generator: widget.generator ??
            LocalWorksheetGenerationService(
              translator: CachedTextTranslationService(
                inner: const DevelopmentTextTranslationService(),
                store: ServiceRegistry.instance.translationCacheStore,
                connectivity: connectivity,
              ),
            ),
        worksheets: widget.worksheets ?? LocalWorksheetRepository(storage),
        connectivity: connectivity,
        storage: storage,
        teacherId: teacherId,
      );
    });
  }

  @override
  void dispose() {
    if (widget.controller == null) _controller?.dispose();
    unawaited(_ownedConnectivity?.dispose());
    super.dispose();
  }

  Future<void> _generate(WorksheetGeneratorController c) async {
    final Worksheet? worksheet = await c.generate();
    if (worksheet == null || !mounted) return;

    await Navigator.of(context).pushNamed(
      AppRoutes.worksheetPreview,
      arguments: WorksheetPreviewArgs(worksheet.id),
    );
  }

  Future<void> _openMenu(WorksheetGeneratorController c) async {
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
              leading: const Icon(Icons.folder_open_outlined),
              title: const Text('Saved worksheets'),
              subtitle: const Text('Opens the resources centre'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                Navigator.of(context).pushNamed(AppRoutes.resources);
              },
            ),
            ListTile(
              leading: const Icon(Icons.info_outline),
              title: const Text('How questions are made'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                _showGenerationInfo(c);
              },
            ),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }

  void _showGenerationInfo(WorksheetGeneratorController c) {
    showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('How questions are made'),
        content: Text(
          c.generationSource.isAi
              ? 'Questions are written by the model behind GyanSetu AI, using '
                  "this lesson's outcome and your classroom's languages."
              : 'Questions are built on this phone from the lesson’s own '
                  'learning outcome and number range. They are made by a '
                  'deterministic generator, not by a model, so the same '
                  'choices always produce the same worksheet.',
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
    final WorksheetGeneratorController? c = _controller;

    if (c == null) {
      if (_pendingLessonId != null) {
        return const _GeneratorShell(child: _Skeleton());
      }
      return const _GeneratorShell(
        child: _Message(
          icon: Icons.description_outlined,
          title: 'No lesson was chosen.',
          body: 'Open this from a lesson so the worksheet knows what to '
              'practise.',
        ),
      );
    }

    return AnimatedBuilder(
      animation: c,
      builder: (BuildContext context, _) {
        switch (c.loadState) {
          case GeneratorLoadState.loading:
            return const _GeneratorShell(child: _Skeleton());
          case GeneratorLoadState.error:
            return _GeneratorShell(
              child: _Message(
                icon: Icons.error_outline,
                title: "Couldn't load this lesson.",
                body: 'The worksheet needs the lesson it is being built for.',
                actionLabel: 'Try again',
                onAction: c.load,
              ),
            );
          case GeneratorLoadState.ready:
            return _ready(context, c);
        }
      },
    );
  }

  Widget _ready(BuildContext context, WorksheetGeneratorController c) {
    return Scaffold(
      backgroundColor: AppColors.homePage,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: <Widget>[
            _Header(
              status: c.offlineStatusLabel,
              ready: c.offlineCapable,
              onBack: () => Navigator.of(context).maybePop(),
              onMore: () => _openMenu(c),
            ),
            Expanded(
              child: LayoutBuilder(
                builder: (BuildContext context, BoxConstraints constraints) {
                  final double width = constraints.maxWidth;
                  final double contentWidth = width.clamp(0.0, 760.0);
                  final double side = ((width - contentWidth) / 2) + 16;

                  return ListView(
                    key: WorksheetGeneratorScreen.scrollKey,
                    padding: EdgeInsets.fromLTRB(side, 4, side, 24),
                    children: <Widget>[
                      _title(c),
                      const SizedBox(height: 16),
                      _context(c, width),
                      const SizedBox(height: 24),
                      _difficulty(c),
                      const SizedBox(height: 24),
                      _questionTypes(c, width),
                      const SizedBox(height: 24),
                      _language(c),
                      const SizedBox(height: 24),
                      _questionCount(c),
                      const SizedBox(height: 24),
                      _visualExamples(c, width),
                      const SizedBox(height: 14),
                      _culturalToggle(c),
                      const SizedBox(height: 16),
                      _generationInfo(c),
                      if (c.message != null) ...<Widget>[
                        const SizedBox(height: 14),
                        WorksheetNotice(
                          message: c.message!,
                          onDismiss: c.dismissMessage,
                          onRetry:
                              c.generationState == GenerationState.failed
                                  ? () => _retry(c)
                                  : null,
                        ),
                      ],
                      if (c.isGenerating) ...<Widget>[
                        const SizedBox(height: 14),
                        _progress(c),
                      ],
                      const SizedBox(height: 18),
                      _generateButton(c),
                      const SizedBox(height: 12),
                      _footer(c),
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

  Future<void> _retry(WorksheetGeneratorController c) async {
    final Worksheet? worksheet = await c.retry();
    if (worksheet == null || !mounted) return;
    await Navigator.of(context).pushNamed(
      AppRoutes.worksheetPreview,
      arguments: WorksheetPreviewArgs(worksheet.id),
    );
  }

  // --- Sections ------------------------------------------------------------

  Widget _title(WorksheetGeneratorController c) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: AppColors.authChip,
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(
                Icons.description_outlined,
                size: 26,
                color: AppColors.brandNavy,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Create Worksheet',
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
                    c.generationSource.isAi
                        ? 'AI-powered worksheet generator for your classroom'
                        : 'Worksheet generator for your classroom, built on '
                            'this phone',
                    style: TextStyle(
                      fontSize: 14.5,
                      height: 1.35,
                      color: AppColors.brandNavy.withValues(alpha: 0.72),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        // The AI half of the badge appears only when a model really wrote the
        // questions. A deterministic generator gets the honest half.
        CapabilityBadge(
          aiLabel: c.generationSource.isAi ? 'AI-generated' : null,
          curriculumAligned: true,
        ),
      ],
    );
  }

  Widget _context(WorksheetGeneratorController c, double width) {
    final Widget lesson = ContextCard(
      icon: Icons.menu_book_outlined,
      tint: AppColors.liveGlowViolet,
      label: 'Lesson',
      value: c.lesson!.title,
    );
    final Widget outcome = ContextCard(
      icon: Icons.track_changes,
      tint: AppColors.setupLiteracy,
      label: 'Learning Outcome',
      value: c.lesson!.learningOutcome,
    );

    // Side by side where there is room; stacked below, where two cards would
    // squeeze a whole outcome into a column two words wide.
    if (width < 420) {
      return Column(
        children: <Widget>[lesson, const SizedBox(height: 10), outcome],
      );
    }
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Expanded(child: lesson),
          const SizedBox(width: 10),
          Expanded(child: outcome),
        ],
      ),
    );
  }

  Widget _difficulty(WorksheetGeneratorController c) {
    ({IconData icon, Color tint}) style(WorksheetDifficulty value) =>
        switch (value) {
          WorksheetDifficulty.easy => (
              icon: Icons.sentiment_satisfied_alt,
              tint: AppColors.liveGlowViolet,
            ),
          WorksheetDifficulty.medium => (
              icon: Icons.sentiment_neutral,
              tint: AppColors.brandGold,
            ),
          WorksheetDifficulty.advanced => (
              icon: Icons.rocket_launch_outlined,
              tint: AppColors.error,
            ),
        };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const SectionHeading(number: 1, title: 'Difficulty Level'),
        LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            final List<Widget> cards = <Widget>[
              for (final WorksheetDifficulty value
                  in WorksheetDifficulty.values)
                ChoiceCard(
                  key: WorksheetGeneratorScreen.difficultyKey(value),
                  selected: c.difficulty == value,
                  onTap: () => c.setDifficulty(value),
                  semanticLabel: '${value.label}. ${value.subtitle}',
                  tint: style(value).tint,
                  child: Padding(
                    padding: const EdgeInsets.only(right: 26),
                    child: Row(
                      children: <Widget>[
                        Icon(
                          style(value).icon,
                          size: 24,
                          color: style(value).tint,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  value.label,
                                  maxLines: 1,
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.brandNavy,
                                  ),
                                ),
                              ),
                              Text(
                                value.subtitle,
                                style: TextStyle(
                                  fontSize: 12.5,
                                  height: 1.25,
                                  color: AppColors.brandNavy
                                      .withValues(alpha: 0.62),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ];

            if (constraints.maxWidth < 480) {
              return Column(
                children: <Widget>[
                  for (int i = 0; i < cards.length; i++)
                    Padding(
                      padding: EdgeInsets.only(
                        bottom: i == cards.length - 1 ? 0 : 10,
                      ),
                      child: cards[i],
                    ),
                ],
              );
            }
            return Row(
              children: <Widget>[
                for (int i = 0; i < cards.length; i++) ...<Widget>[
                  Expanded(child: cards[i]),
                  if (i < cards.length - 1) const SizedBox(width: 10),
                ],
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _questionTypes(WorksheetGeneratorController c, double width) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const SectionHeading(
          number: 2,
          title: 'Question Types',
          hint: 'Select all that apply',
        ),
        _grid(
          width: width,
          minTileWidth: 168,
          children: <Widget>[
            for (final QuestionType type in QuestionType.values)
              ChoiceCard(
                key: WorksheetGeneratorScreen.questionTypeKey(type),
                selected: c.questionTypes.contains(type),
                onTap: () => c.toggleQuestionType(type),
                semanticLabel: '${type.label}. ${type.description}',
                child: Padding(
                  padding: const EdgeInsets.only(top: 26),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      _typePreview(type),
                      const SizedBox(height: 10),
                      Text(
                        type.label,
                        style: const TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w700,
                          color: AppColors.brandNavy,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        type.description,
                        style: TextStyle(
                          fontSize: 12.5,
                          height: 1.3,
                          color: AppColors.brandNavy.withValues(alpha: 0.62),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }

  /// A small illustration of what the question type looks like.
  Widget _typePreview(QuestionType type) {
    const TextStyle numeral = TextStyle(
      fontSize: 17,
      fontWeight: FontWeight.w700,
      color: AppColors.brandNavy,
    );

    // A floor rather than a fixed height, so the four previews line up without
    // clipping the tallest of them.
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 46),
      child: switch (type) {
        QuestionType.countingObjects => const Text(
            '🍎 🍎 🍎',
            style: TextStyle(fontSize: 22),
          ),
        QuestionType.matchNumbers => Row(
            children: <Widget>[
              for (final String n in <String>['1', '2', '3'])
                Container(
                  margin: const EdgeInsets.only(right: 6),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(7),
                    border: Border.all(color: AppColors.outline),
                  ),
                  child: Text(n, style: numeral),
                ),
            ],
          ),
        QuestionType.fillInTheBlanks =>
          const Text('7, 8, __, 10', style: numeral),
        QuestionType.visualIdentification => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Text(
                '5',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: AppColors.brandNavy,
                ),
              ),
              Text(
                '○ 3   ○ 5   ○ 8',
                style: TextStyle(
                  fontSize: 12,
                  color: AppColors.brandNavy.withValues(alpha: 0.7),
                ),
              ),
            ],
          ),
      },
    );
  }

  Widget _language(WorksheetGeneratorController c) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const SectionHeading(number: 3, title: 'Language'),
        Semantics(
          label: 'Worksheet language: ${c.languagePair}. '
              'Set in classroom setup.',
          child: ExcludeSemantics(
            child: Container(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.authFieldBorder),
              ),
              child: Row(
                children: <Widget>[
                  const Icon(
                    Icons.language,
                    size: 24,
                    color: AppColors.liveGlowViolet,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(
                            // Straight from the saved classroom. A classroom
                            // set to Mundari reads Mundari here.
                            c.languagePair,
                            maxLines: 1,
                            style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                              color: AppColors.brandNavy,
                            ),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Questions in both languages, from classroom setup',
                          style: TextStyle(
                            fontSize: 13,
                            color:
                                AppColors.brandNavy.withValues(alpha: 0.62),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _questionCount(WorksheetGeneratorController c) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const SectionHeading(number: 4, title: 'Number of Questions'),
        Row(
          children: <Widget>[
            for (int i = 0;
                i < WorksheetGeneratorController.questionCountOptions.length;
                i++) ...<Widget>[
              Expanded(
                child: Builder(
                  builder: (BuildContext context) {
                    final int value = WorksheetGeneratorController
                        .questionCountOptions[i];
                    return ChoiceCard(
                      key: WorksheetGeneratorScreen.countKey(value),
                      selected: c.numberOfQuestions == value,
                      onTap: () => c.setQuestionCount(value),
                      semanticLabel: '$value questions',
                      indicator: ChoiceIndicator.radio,
                      child: Padding(
                        padding: const EdgeInsets.only(right: 22),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            Text(
                              '$value',
                              style: const TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w800,
                                color: AppColors.brandNavy,
                              ),
                            ),
                            Text(
                              'Questions',
                              style: TextStyle(
                                fontSize: 12.5,
                                color: AppColors.brandNavy
                                    .withValues(alpha: 0.62),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
              if (i <
                  WorksheetGeneratorController.questionCountOptions.length - 1)
                const SizedBox(width: 10),
            ],
          ],
        ),
      ],
    );
  }

  Widget _visualExamples(WorksheetGeneratorController c, double width) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const SectionHeading(
          number: 5,
          title: 'Visual Examples',
          hint: 'Will be used in worksheet',
        ),
        _grid(
          width: width,
          minTileWidth: 150,
          children: <Widget>[
            for (final VisualExample example in VisualExample.values)
              ChoiceCard(
                key: WorksheetGeneratorScreen.visualKey(example),
                selected: c.visualExamples.contains(example),
                onTap: () => c.toggleVisualExample(example),
                semanticLabel: example.label,
                child: Padding(
                  padding: const EdgeInsets.only(top: 24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text(
                        // Two of the object, so the card shows what it draws.
                        '${example.glyph}${example.glyph}',
                        style: const TextStyle(fontSize: 30),
                      ),
                      const SizedBox(height: 8),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          example.label,
                          maxLines: 1,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: AppColors.brandNavy,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _culturalToggle(WorksheetGeneratorController c) {
    return Semantics(
      toggled: c.culturallyFamiliar,
      label: 'Use culturally familiar examples',
      child: ExcludeSemantics(
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.authFieldBorder),
          ),
          child: Row(
            children: <Widget>[
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: AppColors.setupLiteracy.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.groups_outlined,
                  size: 20,
                  color: AppColors.setupLiteracy,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    const Text(
                      'Use culturally familiar examples',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: AppColors.brandNavy,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Prefer everyday objects the classroom already has',
                      style: TextStyle(
                        fontSize: 12.5,
                        height: 1.3,
                        color: AppColors.brandNavy.withValues(alpha: 0.62),
                      ),
                    ),
                  ],
                ),
              ),
              Switch(
                key: WorksheetGeneratorScreen.culturalToggleKey,
                value: c.culturallyFamiliar,
                onChanged: c.setCulturallyFamiliar,
                activeThumbColor: Colors.white,
                activeTrackColor: AppColors.setupLiteracy,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _generationInfo(WorksheetGeneratorController c) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      decoration: BoxDecoration(
        color: AppColors.homeBannerTint,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.brandGold.withValues(alpha: 0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Icon(
            Icons.auto_awesome,
            size: 22,
            color: AppColors.brandGold,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  c.generationSource.isAi
                      ? 'AI will generate'
                      : 'This phone will generate',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: AppColors.brandNavy,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'A printable worksheet with questions, an answer key and '
                  'teacher notes, aligned to this lesson’s learning outcome.',
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.4,
                    color: AppColors.brandNavy.withValues(alpha: 0.78),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// The stages this app is working through, each set when it actually starts.
  Widget _progress(WorksheetGeneratorController c) {
    final GenerationStage? current = c.stage;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.authFieldBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          for (final GenerationStage stage in GenerationStage.values)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: <Widget>[
                  Icon(
                    current == null || stage.index < current.index
                        ? Icons.check_circle
                        : (stage == current
                            ? Icons.radio_button_checked
                            : Icons.radio_button_unchecked),
                    size: 17,
                    color: current != null && stage.index <= current.index
                        ? AppColors.setupLiteracy
                        : AppColors.outline,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      stage.label,
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: stage == current
                            ? FontWeight.w700
                            : FontWeight.w500,
                        color: AppColors.brandNavy.withValues(
                          alpha: current != null && stage.index <= current.index
                              ? 0.9
                              : 0.5,
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

  Widget _generateButton(WorksheetGeneratorController c) {
    final bool enabled = c.canGenerate;

    return Semantics(
      button: true,
      enabled: enabled,
      label: c.isGenerating
          ? 'Generating worksheet'
          : 'Generate worksheet',
      child: ExcludeSemantics(
        child: FilledButton(
          key: WorksheetGeneratorScreen.generateKey,
          // Disabled while one is running, so a second tap cannot start a
          // second worksheet.
          onPressed: enabled ? () => _generate(c) : null,
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.authNavy,
            foregroundColor: Colors.white,
            disabledBackgroundColor:
                AppColors.brandMuted.withValues(alpha: 0.3),
            minimumSize: const Size(0, 60),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(30),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              if (c.isGenerating)
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.3,
                    color: Colors.white,
                  ),
                )
              else
                const Icon(Icons.auto_awesome, size: 22),
              const SizedBox(width: 11),
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    c.isGenerating
                        ? 'Generating Worksheet…'
                        : 'Generate Worksheet',
                    maxLines: 1,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _footer(WorksheetGeneratorController c) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        Icon(
          c.offlineCapable ? Icons.lock_outline : Icons.cloud_off,
          size: 15,
          color: AppColors.brandNavy.withValues(alpha: 0.55),
        ),
        const SizedBox(width: 7),
        Flexible(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              // Only what is true: this generator runs on the device, so the
              // worksheet is made and kept without a connection.
              c.offlineCapable
                  ? 'Generated and saved on this device. Works offline.'
                  : 'Worksheet generation is not available on this device yet.',
              maxLines: 1,
              style: TextStyle(
                fontSize: 12.5,
                color: AppColors.brandNavy.withValues(alpha: 0.6),
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// A wrapping grid that keeps tiles at a readable width on any screen.
  Widget _grid({
    required double width,
    required double minTileWidth,
    required List<Widget> children,
  }) {
    final double available = width.clamp(0.0, 760.0) - 32;
    final int columns =
        (available / minTileWidth).floor().clamp(1, children.length);
    final double spacing = 10;
    final double tileWidth =
        (available - spacing * (columns - 1)) / columns;

    return Wrap(
      spacing: spacing,
      runSpacing: spacing,
      children: <Widget>[
        for (final Widget child in children)
          SizedBox(width: tileWidth, child: child),
      ],
    );
  }
}

/// Back, branding and the honest generator status.
class _Header extends StatelessWidget {
  const _Header({
    required this.status,
    required this.ready,
    required this.onBack,
    required this.onMore,
  });

  final String status;
  final bool ready;
  final VoidCallback onBack;
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final bool showWordmark = constraints.maxWidth >= 380;

        return Padding(
          padding: const EdgeInsets.fromLTRB(2, 4, 6, 0),
          child: Row(
            children: <Widget>[
              IconButton(
                key: WorksheetGeneratorScreen.backKey,
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
                key: WorksheetGeneratorScreen.statusKey,
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
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: ready
                                ? AppColors.setupLiteracy
                                : AppColors.warning,
                          ),
                        ),
                        const SizedBox(width: 8),
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 132),
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              status,
                              maxLines: 1,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: ready
                                    ? AppColors.setupLiteracy
                                    : AppColors.warning,
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
                key: WorksheetGeneratorScreen.moreKey,
                onPressed: onMore,
                tooltip: 'Worksheet options',
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

class _GeneratorShell extends StatelessWidget {
  const _GeneratorShell({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.homePage,
      appBar: AppBar(
        backgroundColor: AppColors.homePage,
        foregroundColor: AppColors.brandNavy,
        elevation: 0,
        title: const Text('Create Worksheet'),
      ),
      body: SafeArea(child: child),
    );
  }
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
            borderRadius: BorderRadius.circular(8),
          ),
        );

    return ListView(
      key: const Key('worksheet-skeleton'),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: <Widget>[
        bar(220, 32),
        bar(double.infinity, 74),
        const SizedBox(height: 10),
        bar(160, 20),
        bar(double.infinity, 66),
        bar(double.infinity, 66),
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
  });

  final IconData icon;
  final String title;
  final String body;
  final String? actionLabel;
  final VoidCallback? onAction;

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
                onPressed: onAction,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.authNavy,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(0, 48),
                ),
                child: Text(actionLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
