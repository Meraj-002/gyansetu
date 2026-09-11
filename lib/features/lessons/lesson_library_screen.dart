import 'package:flutter/material.dart';

import '../../app/routes.dart';
import '../../core/constants/app_assets.dart';
import '../../core/constants/app_colors.dart';
import '../../core/widgets/app_bottom_navigation.dart';
import '../../models/lesson.dart';
import '../../services/connectivity/connectivity_service.dart';
import '../../services/service_registry.dart';
import '../../services/storage/secure_storage_service.dart';
import '../auth/services/auth_session_store.dart';
import '../setup/data/classroom_setup_storage.dart';
import '../setup/models/classroom_setup.dart';
import '../setup/services/classroom_setup_repository.dart';
import '../setup/services/offline_resource_manager.dart';
import 'lesson_navigation.dart';
import 'services/lesson_download_service.dart';
import 'services/lesson_library_controller.dart';
import 'services/lesson_query.dart';
import 'services/lesson_repository.dart';
import 'services/recommendation_repository.dart';
import 'widgets/lesson_cards.dart';
import 'widgets/lesson_widgets.dart';

/// Browse, filter and open lessons.
///
/// The screen renders a [LessonLibraryController]; searching, filtering,
/// sorting, ranking and downloading all live behind repositories, so nothing
/// here changes when the FastAPI catalogue arrives.
class LessonLibraryScreen extends StatefulWidget {
  const LessonLibraryScreen({
    this.lessons,
    this.progress,
    this.downloads,
    this.downloader,
    this.recommendations,
    this.classrooms,
    this.resources,
    this.connectivityService,
    this.teacherId,
    super.key,
  });

  final LessonRepository? lessons;
  final LessonProgressRepository? progress;
  final LessonDownloadRepository? downloads;
  final LessonDownloadService? downloader;
  final RecommendationRepository? recommendations;
  final ClassroomSetupRepository? classrooms;
  final OfflineResourceManager? resources;
  final ConnectivityService? connectivityService;
  final String? teacherId;

  static const Key searchFieldKey = Key('lessons.search');
  static const Key skeletonKey = Key('lessons.skeleton');

  @override
  State<LessonLibraryScreen> createState() => _LessonLibraryScreenState();
}

class _LessonLibraryScreenState extends State<LessonLibraryScreen> {
  LessonLibraryController? _controller;
  ConnectivityService? _ownedConnectivity;
  final TextEditingController _search = TextEditingController();

  @override
  void initState() {
    super.initState();
    _create();
  }

  Future<void> _create() async {
    final SecureStorageService storage = PlatformSecureStorageService();
    final String teacherId = widget.teacherId ??
        (await AuthSessionStore(storage).account())?.id ??
        'local-teacher';
    if (!mounted) return;

    final ConnectivityService connectivity = widget.connectivityService ??
        (_ownedConnectivity = PlatformConnectivityService());
    final LessonDownloadRepository downloads =
        widget.downloads ?? LocalLessonDownloadRepository(storage);

    setState(() {
      _controller = LessonLibraryController(
        lessons: widget.lessons ??
            defaultLessonRepository(storage: storage, downloads: downloads),
        progress:
            widget.progress ?? LocalLessonProgressRepository(storage),
        downloads: downloads,
        downloader: widget.downloader ??
            ManagedLessonDownloadService(
              downloads: downloads,
              downloadManager: ServiceRegistry.instance.downloadManager,
              catalogue: ServiceRegistry.instance.resourceCatalogue,
              connectivity: connectivity,
            ),
        recommendations:
            widget.recommendations ?? const RuleBasedRecommendationRepository(),
        classrooms: widget.classrooms ??
            LocalClassroomSetupRepository(defaultClassroomSetupStorage()),
        resources: widget.resources ?? const BundledOfflineResourceManager(),
        connectivity: connectivity,
        teacherId: teacherId,
      );
    });
  }

  @override
  void dispose() {
    _controller?.dispose();
    _ownedConnectivity?.dispose();
    _search.dispose();
    super.dispose();
  }

  /// Opens a lesson, or explains why it cannot be opened.
  Future<void> _open(LessonCard card) async {
    final LessonLibraryController c = _controller!;
    if (await c.canOpen(card)) {
      if (!mounted) return;
      Navigator.of(context).pushNamed(
        AppRoutes.lessonDetail,
        arguments: LessonDetailArgs(card.lesson.id),
      );
      return;
    }
    if (!mounted) return;

    await showDialog<void>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text(LessonLibraryController.unavailableMessage),
        content: const Text(
          'Download it once while you are online and it will open anywhere '
          'after that.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(context).pop();
              Navigator.of(context).pushNamed(AppRoutes.offline);
            },
            style: FilledButton.styleFrom(backgroundColor: AppColors.authNavy),
            child: const Text('Manage Downloads'),
          ),
        ],
      ),
    );
  }

  Future<void> _download(LessonCard card) async {
    final DownloadOutcome outcome = await _controller!.download(card);
    if (!mounted || outcome is! DownloadRefused) return;

    if (outcome.reason == DownloadRefusal.needsConnection) {
      await showDialog<void>(
        context: context,
        builder: (BuildContext context) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          title: const Text('Internet needed for the first download'),
          content: Text(outcome.message),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.authNavy,
              ),
              child: const Text('Connect to Internet'),
            ),
          ],
        ),
      );
    }
  }

  Future<void> _openFilters() async {
    final LessonLibraryController c = _controller!;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (BuildContext context) => _FilterSheet(controller: c),
    );
  }

  Future<void> _openSort() async {
    final LessonLibraryController c = _controller!;
    final LessonSort? chosen = await showModalBottomSheet<LessonSort>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (BuildContext context) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const SizedBox(height: 14),
              const Text(
                'Sort by',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: AppColors.brandNavy,
                ),
              ),
              const SizedBox(height: 6),
              for (final LessonSort sort in LessonSort.values)
                ListTile(
                  title: Text(sort.label),
                  trailing: c.query.sort == sort
                      ? const Icon(Icons.check, color: AppColors.authNavy)
                      : null,
                  onTap: () => Navigator.of(context).pop(sort),
                ),
              const SizedBox(height: 10),
            ],
          ),
        ),
      ),
    );
    if (chosen != null) c.setSort(chosen);
  }

  @override
  Widget build(BuildContext context) {
    final LessonLibraryController? controller = _controller;

    return Scaffold(
      backgroundColor: AppColors.homePage,
      body: SafeArea(
        bottom: false,
        child: controller == null
            ? const _LibrarySkeleton()
            : ListenableBuilder(
                listenable: controller,
                builder: (BuildContext context, Widget? _) =>
                    _body(context, controller),
              ),
      ),
      // The same shell Home uses; only the selected destination differs.
      bottomNavigationBar:
          const AppBottomNavigation(current: AppDestination.lessons),
    );
  }

  Widget _body(BuildContext context, LessonLibraryController c) {
    if (c.loading && c.catalogue.isEmpty) return const _LibrarySkeleton();
    if (c.failed) return _errorState(c);

    final List<LessonCard> results = c.results;

    return RefreshIndicator(
      onRefresh: c.refresh,
      color: AppColors.authNavy,
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          final double width = constraints.maxWidth;
          final double contentWidth = width.clamp(0.0, 760.0);
          final double sidePad = ((width - contentWidth) / 2) + 16;

          return ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.fromLTRB(sidePad, 10, sidePad, 26),
            children: <Widget>[
              _Header(state: c.offlineState),
              const SizedBox(height: 18),
              const Text(
                'Lesson Library',
                style: TextStyle(
                  fontSize: 28,
                  height: 1.1,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.6,
                  color: AppColors.brandNavy,
                ),
              ),
              const SizedBox(height: 7),
              Text(
                'Find and teach the right lesson, in the right language.',
                style: TextStyle(
                  fontSize: 13.5,
                  color: AppColors.brandNavy.withValues(alpha: 0.7),
                ),
              ),
              const SizedBox(height: 16),
              _searchRow(c),
              const SizedBox(height: 14),
              LessonFilterChips(
                query: c.query,
                onClass: c.setClass,
                onSubject: c.setSubject,
                onCompletion: c.setCompletion,
                onDownload: c.setDownload,
              ),
              if (c.message != null) ...<Widget>[
                const SizedBox(height: 14),
                _Notice(message: c.message!, onDismiss: c.dismissMessage),
              ],
              if (c.recommended.isNotEmpty) ...<Widget>[
                const SizedBox(height: 22),
                _RecommendedSection(
                  controller: c,
                  onStart: _open,
                  onDownload: _download,
                ),
              ],
              const SizedBox(height: 24),
              _listHeader(c, results.length),
              const SizedBox(height: 12),
              if (results.isEmpty)
                _EmptyResults(
                  hasSearch: c.query.hasSearch,
                  onClearFilters: c.clearFilters,
                  onClearSearch: () {
                    _search.clear();
                    c.clearSearch();
                  },
                )
              else
                for (final LessonCard card in results)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: LessonListCard(
                      card: card,
                      classroom: c.classroom,
                      busy: c.isDownloading(card.lesson.id),
                      onOpen: () => _open(card),
                      onDownload: () => _download(card),
                    ),
                  ),
              const SizedBox(height: 10),
              _OfflineBanner(
                state: c.offlineState,
                onManage: () =>
                    Navigator.of(context).pushNamed(AppRoutes.offline),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _searchRow(LessonLibraryController c) {
    final int filters = c.query.activeFilterCount;

    return Row(
      children: <Widget>[
        Expanded(
          child: Container(
            height: 54,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(13),
              border: Border.all(color: AppColors.authFieldBorder),
            ),
            child: Row(
              children: <Widget>[
                Icon(
                  Icons.search,
                  size: 21,
                  color: AppColors.brandNavy.withValues(alpha: 0.6),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    key: LessonLibraryScreen.searchFieldKey,
                    controller: _search,
                    onChanged: c.search,
                    textInputAction: TextInputAction.search,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: AppColors.brandNavy,
                    ),
                    decoration: const InputDecoration(
                      isDense: true,
                      filled: false,
                      border: InputBorder.none,
                      hintText: 'Search lessons...',
                      hintStyle: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w400,
                        color: AppColors.authHint,
                      ),
                    ),
                  ),
                ),
                if (c.query.hasSearch)
                  IconButton(
                    tooltip: 'Clear search',
                    onPressed: () {
                      _search.clear();
                      c.clearSearch();
                    },
                    icon: const Icon(Icons.close, size: 19),
                    color: AppColors.brandNavy.withValues(alpha: 0.6),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 10),
        // Height via minimumSize, not a SizedBox: a Row hands its non-flexible
        // children unbounded width, which a sized box would pass straight on.
        OutlinedButton.icon(
          onPressed: _openFilters,
          icon: const Icon(Icons.tune, size: 19),
          label: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 92),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                filters == 0 ? 'Filters' : 'Filters ($filters)',
                maxLines: 1,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.brandNavy,
            minimumSize: const Size(0, 54),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            side: const BorderSide(color: AppColors.authFieldBorder),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(13),
            ),
          ),
        ),
      ],
    );
  }

  Widget _listHeader(LessonLibraryController c, int count) {
    return Row(
      children: <Widget>[
        Expanded(
          child: Text(
            c.listHeading,
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w800,
              color: AppColors.brandNavy,
            ),
          ),
        ),
        Semantics(
          button: true,
          label: 'Sort by ${c.query.sort.label}',
          child: ExcludeSemantics(
            child: TextButton(
              onPressed: _openSort,
              style: TextButton.styleFrom(
                foregroundColor: AppColors.brandNavy,
                minimumSize: const Size(48, 44),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    'Sort by: ${c.query.sort.label}',
                    style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 3),
                  const Icon(Icons.expand_more, size: 19),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _errorState(LessonLibraryController c) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(
              Icons.menu_book_outlined,
              size: 38,
              color: AppColors.brandMuted,
            ),
            const SizedBox(height: 14),
            const Text(
              "Couldn't load lessons.",
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppColors.brandNavy,
              ),
            ),
            const SizedBox(height: 18),
            FilledButton(
              onPressed: c.load,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.authNavy,
                minimumSize: const Size(160, 48),
              ),
              child: const Text('Try Again'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Logo lock-up and the offline status pill.
class _Header extends StatelessWidget {
  const _Header({required this.state});

  final LibraryOfflineState state;

  ({Color tint, IconData icon}) get _style => switch (state) {
        LibraryOfflineState.online =>
          (tint: AppColors.info, icon: Icons.cloud_done_outlined),
        LibraryOfflineState.offlineReady =>
          (tint: AppColors.setupLiteracy, icon: Icons.cloud_done_outlined),
        LibraryOfflineState.syncRequired =>
          (tint: AppColors.warning, icon: Icons.cloud_sync_outlined),
        LibraryOfflineState.resourcesMissing =>
          (tint: AppColors.warning, icon: Icons.cloud_off),
        LibraryOfflineState.unknown =>
          (tint: AppColors.brandMuted, icon: Icons.cloud_queue),
      };

  @override
  Widget build(BuildContext context) {
    final ({Color tint, IconData icon}) s = _style;

    return Row(
      children: <Widget>[
        Image.asset(
          AppAssets.loginBrandMark,
          height: 38,
          filterQuality: FilterQuality.medium,
          excludeFromSemantics: true,
        ),
        const SizedBox(width: 9),
        Flexible(
          child: Semantics(
            label: 'GyanSetu AI',
            child: ExcludeSemantics(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  FittedBox(
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
                          fontSize: 19,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.3,
                        ),
                      ),
                    ),
                  ),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Bridging Languages. Building Futures.',
                      maxLines: 1,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: AppColors.brandNavy.withValues(alpha: 0.7),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Semantics(
          liveRegion: true,
          label: state.label,
          child: ExcludeSemantics(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.authChip,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Icon(s.icon, size: 17, color: s.tint),
                  const SizedBox(width: 7),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 128),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        state.label,
                        maxLines: 1,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: s.tint,
                        ),
                      ),
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
}

/// The recommendation heading and its carousel.
class _RecommendedSection extends StatefulWidget {
  const _RecommendedSection({
    required this.controller,
    required this.onStart,
    required this.onDownload,
  });

  final LessonLibraryController controller;
  final void Function(LessonCard) onStart;
  final void Function(LessonCard) onDownload;

  @override
  State<_RecommendedSection> createState() => _RecommendedSectionState();
}

class _RecommendedSectionState extends State<_RecommendedSection> {
  final PageController _page = PageController();
  int _index = 0;

  @override
  void dispose() {
    _page.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final List<LessonCard> cards = widget.controller.recommended;
    final ClassroomSetup? classroom = widget.controller.classroom;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Container(
              width: 34,
              height: 34,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.authNavy,
              ),
              child: const Icon(
                Icons.star_border_rounded,
                size: 20,
                color: Colors.white,
              ),
            ),
            const SizedBox(width: 11),
            const Expanded(
              child: Text(
                'Recommended for Today',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: AppColors.brandNavy,
                ),
              ),
            ),
            TextButton(
              onPressed: () {
                // "View all" is a filter, not another screen: it drops the
                // narrowing so the whole catalogue for this class is visible.
                widget.controller.clearFilters();
                widget.controller.setCompletion(CompletionFilter.inProgress);
              },
              style: TextButton.styleFrom(
                foregroundColor: AppColors.brandNavy,
                minimumSize: const Size(48, 44),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    'View all',
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  SizedBox(width: 3),
                  Icon(Icons.chevron_right, size: 18),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _CarouselViewport(
            controller: _page,
            onChanged: (int i) => setState(() => _index = i),
            children: <Widget>[
              for (final LessonCard card in cards)
                RecommendedLessonCard(
                  card: card,
                  classroom: classroom,
                  busy: widget.controller.isDownloading(card.lesson.id),
                  onStart: () => widget.onStart(card),
                  onDownload: () => widget.onDownload(card),
                ),
          ],
        ),
        if (cards.length > 1) ...<Widget>[
          const SizedBox(height: 12),
          Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                for (int i = 0; i < cards.length; i++)
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 220),
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    width: i == _index ? 20 : 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: i == _index
                          ? AppColors.authNavy
                          : AppColors.authFieldBorder,
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// A PageView sized from the layout width.
///
/// A PageView is a viewport and cannot report an intrinsic height, so the
/// height is chosen from the width instead: the card stacks its artwork above
/// the text on a narrow handset and needs more room there. Each page scrolls
/// internally, so an unusually long outcome is never clipped.
class _CarouselViewport extends StatelessWidget {
  const _CarouselViewport({
    required this.controller,
    required this.onChanged,
    required this.children,
  });

  final PageController controller;
  final ValueChanged<int> onChanged;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    if (children.length == 1) return children.first;

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double height = constraints.maxWidth >= 368 ? 330 : 500;
        return SizedBox(
          height: height,
          child: PageView(
            controller: controller,
            onPageChanged: onChanged,
            children: <Widget>[
              for (final Widget child in children)
                SingleChildScrollView(child: child),
            ],
          ),
        );
      },
    );
  }
}

/// Filter sheet: class, subject, completion, downloaded.
class _FilterSheet extends StatefulWidget {
  const _FilterSheet({required this.controller});

  final LessonLibraryController controller;

  @override
  State<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<_FilterSheet> {
  @override
  Widget build(BuildContext context) {
    final LessonLibraryController c = widget.controller;
    final LessonQuery q = c.query;

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.authFieldBorder,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Row(
              children: <Widget>[
                const Expanded(
                  child: Text(
                    'Filters',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: AppColors.brandNavy,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () {
                    c.clearFilters();
                    setState(() {});
                  },
                  child: const Text('Clear All'),
                ),
              ],
            ),
            const SizedBox(height: 6),
            _group(
              'Class',
              <Widget>[
                _option('All', q.classNumber == null, () => c.setClass(null)),
                for (final int level in kSupportedClasses)
                  _option(
                    'Class $level',
                    q.classNumber == level,
                    () => c.setClass(level),
                  ),
              ],
            ),
            _group(
              'Subject',
              <Widget>[
                _option('All', q.subject == null, () => c.setSubject(null)),
                _option(
                  'Literacy',
                  q.subject == ClassroomSubject.foundationalLiteracy,
                  () => c.setSubject(ClassroomSubject.foundationalLiteracy),
                ),
                _option(
                  'Numeracy',
                  q.subject == ClassroomSubject.numeracy,
                  () => c.setSubject(ClassroomSubject.numeracy),
                ),
              ],
            ),
            _group(
              'Completion',
              <Widget>[
                for (final CompletionFilter f in CompletionFilter.values)
                  _option(f.label, q.completion == f, () => c.setCompletion(f)),
              ],
            ),
            _group(
              'Downloaded',
              <Widget>[
                for (final DownloadFilter f in DownloadFilter.values)
                  _option(f.label, q.download == f, () => c.setDownload(f)),
              ],
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.authNavy,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(13),
                  ),
                ),
                child: Text('Show ${c.results.length} lessons'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _group(String title, List<Widget> options) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            title,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: AppColors.brandNavy,
            ),
          ),
          const SizedBox(height: 9),
          Wrap(spacing: 8, runSpacing: 8, children: options),
        ],
      ),
    );
  }

  Widget _option(String label, bool selected, VoidCallback onTap) {
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) {
        onTap();
        setState(() {});
      },
      showCheckmark: true,
      selectedColor: AppColors.authNavy,
      backgroundColor: Colors.white,
      labelStyle: TextStyle(
        fontSize: 13.5,
        fontWeight: FontWeight.w600,
        color: selected ? Colors.white : AppColors.brandNavy,
      ),
      side: BorderSide(
        color: selected ? AppColors.authNavy : AppColors.authFieldBorder,
      ),
    );
  }
}

/// Nothing matched the current search and filters.
class _EmptyResults extends StatelessWidget {
  const _EmptyResults({
    required this.hasSearch,
    required this.onClearFilters,
    required this.onClearSearch,
  });

  final bool hasSearch;
  final VoidCallback onClearFilters;
  final VoidCallback onClearSearch;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(26),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.authFieldBorder),
      ),
      child: Column(
        children: <Widget>[
          Icon(
            Icons.search_off,
            size: 34,
            color: AppColors.brandNavy.withValues(alpha: 0.4),
          ),
          const SizedBox(height: 12),
          const Text(
            'No lessons found',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: AppColors.brandNavy,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Try changing your search or filters.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              color: AppColors.brandNavy.withValues(alpha: 0.7),
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            alignment: WrapAlignment.center,
            children: <Widget>[
              OutlinedButton(
                onPressed: onClearFilters,
                child: const Text('Clear Filters'),
              ),
              if (hasSearch)
                OutlinedButton(
                  onPressed: onClearSearch,
                  child: const Text('Clear Search'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// The banner above the navigation bar.
class _OfflineBanner extends StatelessWidget {
  const _OfflineBanner({required this.state, required this.onManage});

  final LibraryOfflineState state;
  final VoidCallback onManage;

  String get _title => switch (state) {
        LibraryOfflineState.offlineReady => 'All lessons are available offline',
        LibraryOfflineState.online => 'Downloads are available',
        LibraryOfflineState.syncRequired => 'Some resources need syncing',
        LibraryOfflineState.resourcesMissing =>
          'Some lessons are not on this device',
        LibraryOfflineState.unknown => 'Checking downloads',
      };

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 13, 12, 13),
      decoration: BoxDecoration(
        color: AppColors.homeBannerTint,
        borderRadius: BorderRadius.circular(14),
      ),
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          final Widget text = Row(
            children: <Widget>[
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: AppColors.setupCta.withValues(alpha: 0.9),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: const Icon(
                  Icons.download_outlined,
                  size: 22,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      _title,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppColors.brandNavy,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Download once and teach anytime, anywhere.',
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.3,
                        color: AppColors.brandNavy.withValues(alpha: 0.66),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );

          final Widget action = OutlinedButton(
            onPressed: onManage,
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.brandNavy,
              backgroundColor: Colors.white,
              minimumSize: const Size(0, 46),
              side: const BorderSide(color: AppColors.authFieldBorder),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(11),
              ),
            ),
            child: const FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    'Manage Downloads',
                    maxLines: 1,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  SizedBox(width: 4),
                  Icon(Icons.chevron_right, size: 18),
                ],
              ),
            ),
          );

          if (constraints.maxWidth < 460) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[text, const SizedBox(height: 12), action],
            );
          }
          return Row(
            children: <Widget>[
              Expanded(child: text),
              const SizedBox(width: 12),
              action,
            ],
          );
        },
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.message, required this.onDismiss});

  final String message;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.fromLTRB(13, 10, 6, 10),
        decoration: BoxDecoration(
          color: AppColors.warning.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.warning.withValues(alpha: 0.28)),
        ),
        child: Row(
          children: <Widget>[
            const Icon(Icons.info_outline, size: 17, color: AppColors.warning),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                message,
                style: TextStyle(
                  fontSize: 12.5,
                  height: 1.4,
                  fontWeight: FontWeight.w500,
                  color: AppColors.brandNavy.withValues(alpha: 0.85),
                ),
              ),
            ),
            IconButton(
              onPressed: onDismiss,
              icon: const Icon(Icons.close, size: 17),
              tooltip: 'Dismiss',
              color: AppColors.brandNavy.withValues(alpha: 0.6),
            ),
          ],
        ),
      ),
    );
  }
}

/// Lightweight placeholders while the catalogue is read.
class _LibrarySkeleton extends StatelessWidget {
  const _LibrarySkeleton();

  @override
  Widget build(BuildContext context) {
    Widget block(double height) => Container(
          height: height,
          margin: const EdgeInsets.only(bottom: 14),
          decoration: BoxDecoration(
            color: AppColors.authFieldBorder.withValues(alpha: 0.45),
            borderRadius: BorderRadius.circular(13),
          ),
        );

    return ListView(
      key: LessonLibraryScreen.skeletonKey,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 26),
      children: <Widget>[
        block(46),
        block(38),
        block(54),
        block(48),
        block(230),
        block(110),
        block(110),
      ],
    );
  }
}
