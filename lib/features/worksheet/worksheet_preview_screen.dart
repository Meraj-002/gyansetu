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
import '../../services/worksheet_pdf_service.dart';
import '../lessons/services/lesson_repository.dart';
import 'services/local_worksheet_generation_service.dart';
import 'services/printing_output_service.dart';
import 'services/worksheet_generation_service.dart';
import 'services/worksheet_preview_controller.dart';
import 'services/worksheet_repository.dart';
import 'services/worksheet_validator.dart';
import 'widgets/worksheet_paper.dart';

/// What the preview is opened with.
///
/// Only the id travels. The worksheet is read back from the repository, so
/// there is one copy of it and the preview, the PDF, the printer and the share
/// sheet all show the same thing.
class WorksheetPreviewArgs {
  const WorksheetPreviewArgs(this.worksheetId);

  final String worksheetId;

  static String? worksheetIdFrom(Object? arguments) => switch (arguments) {
        WorksheetPreviewArgs(:final String worksheetId) => worksheetId,
        final String id when id.isNotEmpty => id,
        _ => null,
      };
}

/// The generated worksheet, as it will be printed.
///
/// Every question, number and picture here came from the generator and was
/// saved before this screen opened. The same [Worksheet] powers the paper on
/// screen, the PDF, the print job and the share sheet — there is no second
/// template anywhere.
class WorksheetPreviewScreen extends StatefulWidget {
  const WorksheetPreviewScreen({
    this.worksheetId,
    this.worksheet,
    this.controller,
    this.worksheets,
    this.pdfService,
    this.output,
    this.lessons,
    this.generator,
    this.connectivity,
    super.key,
  });

  static const Key scrollKey = Key('worksheet-preview-scroll');
  static const Key skeletonKey = Key('worksheet-preview-skeleton');
  static const Key paperKey = Key('worksheet-preview-paper');
  static const Key backKey = Key('worksheet-preview-back');
  static const Key moreKey = Key('worksheet-preview-more');
  static const Key statusKey = Key('worksheet-preview-status');
  static const Key downloadKey = Key('worksheet-preview-download');
  static const Key printKey = Key('worksheet-preview-print');
  static const Key shareKey = Key('worksheet-preview-share');
  static const Key regenerateKey = Key('worksheet-preview-regenerate');
  static const Key answersKey = Key('worksheet-preview-answers');
  static const Key pageIndicatorKey = Key('worksheet-preview-pages');
  static const Key retryKey = Key('worksheet-preview-retry');

  final String? worksheetId;

  /// Handed straight in when the generator has just produced it.
  final Worksheet? worksheet;

  /// Supplied whole by tests; built from the parts below otherwise.
  final WorksheetPreviewController? controller;

  final WorksheetRepository? worksheets;
  final WorksheetPdfService? pdfService;
  final WorksheetOutputService? output;
  final LessonRepository? lessons;
  final WorksheetGenerationService? generator;
  final ConnectivityService? connectivity;

  @override
  State<WorksheetPreviewScreen> createState() => _WorksheetPreviewScreenState();
}

class _WorksheetPreviewScreenState extends State<WorksheetPreviewScreen> {
  WorksheetPreviewController? _controller;
  ConnectivityService? _ownedConnectivity;

  bool _built = false;
  bool _showAnswers = false;

  /// Set before the controller exists, so the screen shows a skeleton rather
  /// than claiming there is no worksheet.
  String? _pendingId;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_built) return;
    _built = true;

    final WorksheetPreviewController? given = widget.controller;
    if (given != null) {
      _controller = given;
      return;
    }

    final Object? routeArgs = ModalRoute.of(context)?.settings.arguments;
    final String? id = widget.worksheetId ??
        widget.worksheet?.id ??
        WorksheetPreviewArgs.worksheetIdFrom(routeArgs);
    _pendingId = id;
    if (id != null) _build(id);
  }

  void _build(String id) {
    final SecureStorageService storage = PlatformSecureStorageService();
    final ConnectivityService connectivity = widget.connectivity ??
        (_ownedConnectivity = PlatformConnectivityService());

    setState(() {
      _controller = WorksheetPreviewController(
        worksheetId: id,
        initial: widget.worksheet,
        worksheets: widget.worksheets ?? LocalWorksheetRepository(storage),
        pdfService: widget.pdfService ?? PdfWorksheetService(),
        output: widget.output ?? const PrintingOutputService(),
        lessons: widget.lessons ??
            defaultLessonRepository(
              storage: storage,
              downloads: LocalLessonDownloadRepository(storage),
            ),
        // The same generator the previous screen used, so Regenerate keeps the
        // teacher's choices and produces a comparable sheet.
        generator: widget.generator ??
            LocalWorksheetGenerationService(
              translator: CachedTextTranslationService(
                inner: const DevelopmentTextTranslationService(),
                store: ServiceRegistry.instance.translationCacheStore,
                connectivity: connectivity,
              ),
            ),
        connectivity: connectivity,
      );
    });
  }

  @override
  void dispose() {
    if (widget.controller == null) _controller?.dispose();
    unawaited(_ownedConnectivity?.dispose());
    super.dispose();
  }

  // --- Actions -------------------------------------------------------------

  Future<void> _regenerate(WorksheetPreviewController c) async {
    final bool? go = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('Generate a new worksheet?'),
        content: const Text(
          'Your current worksheet will be replaced. The lesson, class, '
          'languages and every option you chose stay the same.',
          style: TextStyle(height: 1.45),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.authNavy,
            ),
            child: const Text('Regenerate'),
          ),
        ],
      ),
    );
    if (go == true) await c.regenerate();
  }

  Future<void> _openMenu(WorksheetPreviewController c) async {
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
              key: WorksheetPreviewScreen.answersKey,
              leading: Icon(
                _showAnswers ? Icons.visibility_off : Icons.visibility,
              ),
              title: Text(
                _showAnswers
                    ? 'Hide the answer key'
                    : 'Show the answer key',
              ),
              subtitle: const Text(
                'The printed sheet never shows answers to the child',
              ),
              onTap: () {
                Navigator.of(sheetContext).pop();
                setState(() => _showAnswers = !_showAnswers);
              },
            ),
            ListTile(
              leading: const Icon(Icons.tune),
              title: const Text('Change the options'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                Navigator.of(context).maybePop();
              },
            ),
            ListTile(
              leading: const Icon(Icons.folder_open_outlined),
              title: const Text('Saved worksheets'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                Navigator.of(context).pushNamed(AppRoutes.resources);
              },
            ),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }

  // --- Build ---------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final WorksheetPreviewController? c = _controller;

    if (c == null) {
      return _PreviewShell(
        child: _pendingId != null
            ? const _Skeleton()
            : const _Message(
                icon: Icons.description_outlined,
                title: 'No worksheet was chosen.',
                body: 'Generate a worksheet first, then it can be previewed '
                    'here.',
              ),
      );
    }

    return AnimatedBuilder(
      animation: c,
      builder: (BuildContext context, _) {
        switch (c.loadState) {
          case PreviewLoadState.loading:
            return const _PreviewShell(child: _Skeleton());
          case PreviewLoadState.error:
            return _PreviewShell(
              child: _Message(
                icon: Icons.error_outline,
                title: "Couldn't load this worksheet.",
                body: 'It may have been removed from this device.',
                actionLabel: 'Retry',
                onAction: c.load,
                secondaryLabel: 'Back',
                onSecondary: () => Navigator.of(context).maybePop(),
              ),
            );
          case PreviewLoadState.loaded:
            return _loaded(context, c);
        }
      },
    );
  }

  Widget _loaded(BuildContext context, WorksheetPreviewController c) {
    final Worksheet worksheet = c.worksheet!;

    return Scaffold(
      backgroundColor: AppColors.homePage,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: <Widget>[
            _Header(
              status: c.status,
              onBack: () => Navigator.of(context).maybePop(),
              onMore: () => _openMenu(c),
            ),
            Expanded(
              child: LayoutBuilder(
                builder: (BuildContext context, BoxConstraints constraints) {
                  final double width = constraints.maxWidth;
                  final double contentWidth = width.clamp(0.0, 780.0);
                  final double side = ((width - contentWidth) / 2) + 14;

                  return ListView(
                    key: WorksheetPreviewScreen.scrollKey,
                    padding: EdgeInsets.fromLTRB(side, 4, side, 16),
                    children: <Widget>[
                      if (!c.isValid) ...<Widget>[
                        _ValidationWarning(problems: c.problems),
                        const SizedBox(height: 12),
                      ],
                      _paper(worksheet),
                      const SizedBox(height: 14),
                      _pageIndicator(c),
                      if (c.message != null) ...<Widget>[
                        const SizedBox(height: 12),
                        _Notice(
                          message: c.message!,
                          failed: c.lastActionFailed,
                          onDismiss: c.dismissMessage,
                        ),
                      ],
                      const SizedBox(height: 14),
                    ],
                  );
                },
              ),
            ),
            _ActionBar(
              controller: c,
              onDownload: c.savePdf,
              onPrint: c.printPdf,
              onShare: c.sharePdf,
              onRegenerate: () => _regenerate(c),
            ),
          ],
        ),
      ),
    );
  }

  /// The worksheet paper, drawn from the generated worksheet and nothing else.
  Widget _paper(Worksheet worksheet) {
    return Container(
      key: WorksheetPreviewScreen.paperKey,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.outlineVariant),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: AppColors.brandNavy.withValues(alpha: 0.06),
            blurRadius: 16,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          PaperHeader(worksheet: worksheet),
          const SizedBox(height: 12),
          const Divider(height: 1, color: AppColors.outlineVariant),
          const SizedBox(height: 14),
          if (worksheet.questions.isEmpty)
            Text(
              'This worksheet has no questions.',
              style: TextStyle(
                fontSize: 14,
                color: AppColors.brandNavy.withValues(alpha: 0.7),
              ),
            )
          else
            for (final WorksheetQuestion question in worksheet.questions)
              PaperQuestion(
                question: question,
                targetLanguageLabel: worksheet.targetLanguage.label,
                // The teacher can turn the key on; a printed sheet never shows
                // it beside the question.
                showAnswer: _showAnswers,
              ),
          const SizedBox(height: 4),
          PaperFooter(bilingual: worksheet.isFullyBilingual),
        ],
      ),
    );
  }

  Widget _pageIndicator(WorksheetPreviewController c) {
    return Center(
      child: Semantics(
        label: 'The printed worksheet is ${c.pageCount} '
            '${c.pageCount == 1 ? 'page' : 'pages'}',
        child: ExcludeSemantics(
          child: Container(
            key: WorksheetPreviewScreen.pageIndicatorKey,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
            decoration: BoxDecoration(
              color: AppColors.authNavy,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              // The real page count, from the same pagination the PDF uses.
              '1 / ${c.pageCount}',
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Back, title, generation status, options.
class _Header extends StatelessWidget {
  const _Header({
    required this.status,
    required this.onBack,
    required this.onMore,
  });

  final ({String title, String subtitle, bool ai}) status;
  final VoidCallback onBack;
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 4, 6, 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          IconButton(
            key: WorksheetPreviewScreen.backKey,
            onPressed: onBack,
            tooltip: 'Back',
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.arrow_back, size: 23),
            color: AppColors.brandNavy,
          ),
          const SizedBox(width: 2),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Worksheet Preview',
                    maxLines: 1,
                    style: TextStyle(
                      fontSize: 24,
                      height: 1.1,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.6,
                      color: AppColors.brandNavy,
                    ),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Review before download or print',
                  style: TextStyle(
                    fontSize: 13,
                    color: AppColors.brandNavy.withValues(alpha: 0.68),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Semantics(
            key: WorksheetPreviewScreen.statusKey,
            label: '${status.title}. ${status.subtitle}',
            child: ExcludeSemantics(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 11,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.authFieldBorder),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Icon(
                      status.ai ? Icons.auto_awesome : Icons.check_circle,
                      size: 17,
                      color: status.ai
                          ? AppColors.brandGold
                          : AppColors.setupLiteracy,
                    ),
                    const SizedBox(width: 8),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 116),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Text(
                              status.title,
                              maxLines: 1,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: status.ai
                                    ? AppColors.secondaryDark
                                    : AppColors.setupLiteracy,
                              ),
                            ),
                          ),
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Text(
                              status.subtitle,
                              maxLines: 1,
                              style: TextStyle(
                                fontSize: 11.5,
                                color: AppColors.brandNavy
                                    .withValues(alpha: 0.65),
                              ),
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
          IconButton(
            key: WorksheetPreviewScreen.moreKey,
            onPressed: onMore,
            tooltip: 'Worksheet options',
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.more_vert, size: 21),
            color: AppColors.brandNavy,
          ),
        ],
      ),
    );
  }
}

/// The navy bar of actions, plus the offline note under it.
class _ActionBar extends StatelessWidget {
  const _ActionBar({
    required this.controller,
    required this.onDownload,
    required this.onPrint,
    required this.onShare,
    required this.onRegenerate,
  });

  final WorksheetPreviewController controller;
  final Future<void> Function() onDownload;
  final Future<void> Function() onPrint;
  final Future<void> Function() onShare;
  final Future<void> Function() onRegenerate;

  @override
  Widget build(BuildContext context) {
    final bool busy = controller.busy;

    return Container(
      color: AppColors.homePage,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 6, 14, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.authNavy,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: LayoutBuilder(
                  builder: (BuildContext context, BoxConstraints constraints) {
                    final List<Widget> actions = <Widget>[
                      _Action(
                        key: WorksheetPreviewScreen.downloadKey,
                        icon: controller.isSaved
                            ? Icons.download_done
                            : Icons.picture_as_pdf_outlined,
                        label: switch (controller.task) {
                          PdfTask.saving => 'Generating PDF…',
                          _ when controller.isSaved => 'PDF Saved',
                          _ => 'Download PDF',
                        },
                        tint: AppColors.error,
                        busy: controller.task == PdfTask.saving,
                        // One heavy job at a time: building the same document
                        // twice on a 2 GB phone helps nobody.
                        onPressed: busy ? null : onDownload,
                      ),
                      _Action(
                        key: WorksheetPreviewScreen.printKey,
                        icon: Icons.print_outlined,
                        label: controller.task == PdfTask.printing
                            ? 'Printing…'
                            : 'Print',
                        tint: AppColors.brandNavy,
                        busy: controller.task == PdfTask.printing,
                        onPressed:
                            busy || !controller.capability.canPrint
                                ? null
                                : onPrint,
                      ),
                      _Action(
                        key: WorksheetPreviewScreen.shareKey,
                        icon: Icons.share_outlined,
                        label: controller.task == PdfTask.sharing
                            ? 'Sharing…'
                            : 'Share',
                        tint: AppColors.setupLiteracy,
                        busy: controller.task == PdfTask.sharing,
                        onPressed:
                            busy || !controller.capability.canShare
                                ? null
                                : onShare,
                      ),
                      _Action(
                        key: WorksheetPreviewScreen.regenerateKey,
                        icon: Icons.auto_awesome,
                        label: controller.task == PdfTask.regenerating
                            ? 'Generating…'
                            : 'Regenerate',
                        tint: AppColors.liveGlowViolet,
                        busy: controller.task == PdfTask.regenerating,
                        onPressed: busy || !controller.canRegenerate
                            ? null
                            : onRegenerate,
                      ),
                    ];

                    // Two rows of two on a phone: four labelled buttons across
                    // 360dp leave each one too narrow to read.
                    if (constraints.maxWidth < 560) {
                      return Column(
                        children: <Widget>[
                          Row(
                            children: <Widget>[
                              Expanded(child: actions[0]),
                              const SizedBox(width: 8),
                              Expanded(child: actions[1]),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: <Widget>[
                              Expanded(child: actions[2]),
                              const SizedBox(width: 8),
                              Expanded(child: actions[3]),
                            ],
                          ),
                        ],
                      );
                    }

                    return Row(
                      children: <Widget>[
                        for (int i = 0; i < actions.length; i++) ...<Widget>[
                          Expanded(child: actions[i]),
                          if (i < actions.length - 1) const SizedBox(width: 8),
                        ],
                      ],
                    );
                  },
                ),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  Icon(
                    Icons.wifi_off,
                    size: 15,
                    color: AppColors.brandNavy.withValues(alpha: 0.55),
                  ),
                  const SizedBox(width: 7),
                  Flexible(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        // True of everything on this screen: the worksheet is
                        // on the device and the PDF is built here.
                        'Works offline. No internet required.',
                        maxLines: 1,
                        style: TextStyle(
                          fontSize: 12.5,
                          color: AppColors.brandNavy.withValues(alpha: 0.6),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Action extends StatelessWidget {
  const _Action({
    required this.icon,
    required this.label,
    required this.tint,
    required this.onPressed,
    this.busy = false,
    super.key,
  });

  final IconData icon;
  final String label;
  final Color tint;
  final Future<void> Function()? onPressed;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final bool enabled = onPressed != null;

    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      child: ExcludeSemantics(
        child: Material(
          color: enabled ? Colors.white : Colors.white.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            onTap: enabled ? () => onPressed!() : null,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              height: 52,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              alignment: Alignment.center,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  if (busy)
                    SizedBox(
                      width: 17,
                      height: 17,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.1,
                        color: tint,
                      ),
                    )
                  else
                    Icon(
                      icon,
                      size: 20,
                      color: enabled ? tint : AppColors.brandMuted,
                    ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        label,
                        maxLines: 1,
                        style: TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w700,
                          color: enabled
                              ? AppColors.brandNavy
                              : AppColors.brandMuted,
                        ),
                      ),
                    ),
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

/// Shown when the worksheet itself does not pass validation.
class _ValidationWarning extends StatelessWidget {
  const _ValidationWarning({required this.problems});

  final List<WorksheetProblem> problems;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.error.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.error.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Text(
            'This worksheet has a problem.',
            style: TextStyle(
              fontSize: 14.5,
              fontWeight: FontWeight.w700,
              color: AppColors.error,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            // Named plainly so the teacher can decide whether to regenerate.
            problems.first.message,
            style: TextStyle(
              fontSize: 13,
              height: 1.4,
              color: AppColors.brandNavy.withValues(alpha: 0.8),
            ),
          ),
        ],
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({
    required this.message,
    required this.failed,
    required this.onDismiss,
  });

  final String message;
  final bool failed;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final Color tint = failed ? AppColors.error : AppColors.setupLiteracy;

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 11, 4, 11),
      decoration: BoxDecoration(
        color: tint.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: tint.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: <Widget>[
          Icon(
            failed ? Icons.error_outline : Icons.check_circle_outline,
            size: 19,
            color: tint,
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
            icon: const Icon(Icons.close, size: 18),
            color: AppColors.brandNavy.withValues(alpha: 0.6),
          ),
        ],
      ),
    );
  }
}

class _PreviewShell extends StatelessWidget {
  const _PreviewShell({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.homePage,
      appBar: AppBar(
        backgroundColor: AppColors.homePage,
        foregroundColor: AppColors.brandNavy,
        elevation: 0,
        title: Row(
          children: <Widget>[
            Image.asset(
              AppAssets.loginBrandMark,
              height: 26,
              excludeFromSemantics: true,
            ),
            const SizedBox(width: 8),
            const Text('Worksheet Preview'),
          ],
        ),
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
      key: WorksheetPreviewScreen.skeletonKey,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: <Widget>[
        bar(double.infinity, 80),
        const SizedBox(height: 10),
        bar(double.infinity, 120),
        bar(double.infinity, 120),
        bar(double.infinity, 120),
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
                key: WorksheetPreviewScreen.retryKey,
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
