import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../models/lesson.dart';
import '../../setup/models/classroom_setup.dart';
import '../services/lesson_query.dart';

/// Ring showing how far through a lesson the teacher is.
///
/// The percentage is written inside the ring, so completion never rests on the
/// arc's colour alone.
class CompletionRing extends StatelessWidget {
  const CompletionRing({required this.percent, this.size = 44, super.key});

  final int percent;
  final double size;

  Color get _tint {
    if (percent >= 100) return AppColors.setupLiteracy;
    if (percent >= 60) return AppColors.setupLiteracy;
    if (percent > 0) return AppColors.brandOrange;
    return AppColors.brandMuted;
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '$percent per cent complete',
      child: ExcludeSemantics(
        child: SizedBox(
          width: size,
          height: size,
          child: Stack(
            alignment: Alignment.center,
            children: <Widget>[
              SizedBox.expand(
                child: CircularProgressIndicator(
                  value: (percent / 100).clamp(0.0, 1.0),
                  strokeWidth: 3,
                  backgroundColor: AppColors.authFieldBorder,
                  valueColor: AlwaysStoppedAnimation<Color>(_tint),
                ),
              ),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Padding(
                  padding: const EdgeInsets.all(6),
                  child: Text(
                    '$percent%',
                    style: TextStyle(
                      fontSize: size * 0.26,
                      fontWeight: FontWeight.w800,
                      color: AppColors.brandNavy,
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
}

/// Download state as an icon plus a word, never colour alone.
class DownloadBadge extends StatelessWidget {
  const DownloadBadge({
    required this.state,
    this.showLabel = true,
    this.onTap,
    super.key,
  });

  final DownloadState state;
  final bool showLabel;

  /// Null while a download is running, which is what blocks a second tap.
  final VoidCallback? onTap;

  ({IconData icon, Color tint}) get _style => switch (state) {
    DownloadState.downloaded => (
      icon: Icons.cloud_done_outlined,
      tint: AppColors.setupLiteracy,
    ),
    DownloadState.downloading => (
      icon: Icons.cloud_sync_outlined,
      tint: AppColors.info,
    ),
    DownloadState.failed => (icon: Icons.cloud_off, tint: AppColors.error),
    DownloadState.notDownloaded => (
      icon: Icons.cloud_download_outlined,
      tint: AppColors.brandOrange,
    ),
  };

  @override
  Widget build(BuildContext context) {
    final ({IconData icon, Color tint}) s = _style;

    final Widget content = Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        if (state == DownloadState.downloading)
          SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(s.tint),
            ),
          )
        else
          Icon(s.icon, size: 20, color: s.tint),
        if (showLabel) ...<Widget>[
          const SizedBox(width: 7),
          Text(
            state.label,
            maxLines: 1,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.brandNavy.withValues(alpha: 0.82),
            ),
          ),
        ],
      ],
    );

    final Widget scaled = FittedBox(fit: BoxFit.scaleDown, child: content);

    return Semantics(
      button: onTap != null,
      label: state.label,
      child: ExcludeSemantics(
        child: onTap == null
            ? scaled
            : InkWell(
                onTap: onTap,
                borderRadius: BorderRadius.circular(10),
                child: Padding(padding: const EdgeInsets.all(6), child: scaled),
              ),
      ),
    );
  }
}

/// Subject / class metadata pill.
class MetaChip extends StatelessWidget {
  const MetaChip({required this.icon, required this.label, super.key});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(
            icon,
            size: 15,
            color: AppColors.brandNavy.withValues(alpha: 0.7),
          ),
          const SizedBox(width: 5),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 150),
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: AppColors.brandNavy.withValues(alpha: 0.78),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The Hindi → Santali line, built from the classroom rather than the lesson.
class LanguagePairLine extends StatelessWidget {
  const LanguagePairLine({
    required this.classroom,
    this.compact = false,
    super.key,
  });

  final ClassroomSetup? classroom;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final ClassroomSetup? c = classroom;
    if (c == null) return const SizedBox.shrink();

    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(
            Icons.translate,
            size: compact ? 14 : 16,
            color: AppColors.setupLiteracy,
          ),
          const SizedBox(width: 6),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 190),
            child: Text(
              '${c.teachingMedium.label} → ${c.targetLanguage.label}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: compact ? 12 : 13,
                fontWeight: FontWeight.w600,
                color: AppColors.brandNavy.withValues(alpha: 0.85),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Lesson thumbnail, falling back to a tinted initial when no art exists.
class LessonThumbnail extends StatelessWidget {
  const LessonThumbnail({
    required this.lesson,
    required this.width,
    required this.height,
    super.key,
  });

  final Lesson lesson;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    final String? asset = lesson.thumbnailAsset;
    final Color tint = lesson.subject == ClassroomSubject.numeracy
        ? AppColors.setupNumeracy
        : AppColors.setupLiteracy;

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        width: width,
        height: height,
        child: asset == null
            // Most prototype lessons have no artwork yet; a tinted monogram is
            // honest about that and costs nothing to render.
            ? ColoredBox(
                color: tint.withValues(alpha: 0.12),
                child: Center(
                  child: Icon(
                    lesson.subject == ClassroomSubject.numeracy
                        ? Icons.calculate_outlined
                        : Icons.menu_book_outlined,
                    size: math.min(width, height) * 0.42,
                    color: tint,
                  ),
                ),
              )
            : Image.asset(asset, fit: BoxFit.cover, excludeFromSemantics: true),
      ),
    );
  }
}

/// Horizontal, scrollable filter chips.
class LessonFilterChips extends StatelessWidget {
  const LessonFilterChips({
    required this.query,
    required this.onClass,
    required this.onSubject,
    required this.onCompletion,
    required this.onDownload,
    super.key,
  });

  final LessonQuery query;
  final ValueChanged<int?> onClass;
  final ValueChanged<ClassroomSubject?> onSubject;
  final ValueChanged<CompletionFilter> onCompletion;
  final ValueChanged<DownloadFilter> onDownload;

  @override
  Widget build(BuildContext context) {
    final bool literacy =
        query.subject == ClassroomSubject.foundationalLiteracy;
    final bool numeracy = query.subject == ClassroomSubject.numeracy;
    final bool completed = query.completion == CompletionFilter.completed;
    final bool downloaded = query.download == DownloadFilter.downloaded;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: <Widget>[
          _Chip(
            icon: Icons.groups_outlined,
            label: query.classNumber == null
                ? 'All classes'
                : 'Class ${query.classNumber}',
            selected: query.classNumber != null,
            trailing: Icons.expand_more,
            onTap: () => _showClassMenu(context),
          ),
          const SizedBox(width: 9),
          _Chip(
            icon: Icons.menu_book_outlined,
            label: 'Literacy',
            selected: literacy,
            onTap: () => onSubject(
              literacy ? null : ClassroomSubject.foundationalLiteracy,
            ),
          ),
          const SizedBox(width: 9),
          _Chip(
            icon: Icons.calculate_outlined,
            label: 'Numeracy',
            selected: numeracy,
            onTap: () => onSubject(numeracy ? null : ClassroomSubject.numeracy),
          ),
          const SizedBox(width: 9),
          _Chip(
            icon: Icons.check_circle_outline,
            label: 'Completed',
            selected: completed,
            onTap: () => onCompletion(
              completed ? CompletionFilter.all : CompletionFilter.completed,
            ),
          ),
          const SizedBox(width: 9),
          _Chip(
            icon: Icons.download_outlined,
            label: 'Downloaded',
            selected: downloaded,
            onTap: () => onDownload(
              downloaded ? DownloadFilter.all : DownloadFilter.downloaded,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showClassMenu(BuildContext context) async {
    final int? chosen = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (BuildContext context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const SizedBox(height: 14),
            const Text(
              'Class',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: AppColors.brandNavy,
              ),
            ),
            const SizedBox(height: 8),
            ListTile(
              title: const Text('All classes'),
              trailing: query.classNumber == null
                  ? const Icon(Icons.check, color: AppColors.authNavy)
                  : null,
              onTap: () => Navigator.of(context).pop(-1),
            ),
            for (final int level in kSupportedClasses)
              ListTile(
                title: Text('Class $level'),
                trailing: query.classNumber == level
                    ? const Icon(Icons.check, color: AppColors.authNavy)
                    : null,
                onTap: () => Navigator.of(context).pop(level),
              ),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );

    if (chosen == null) return;
    onClass(chosen == -1 ? null : chosen);
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
    this.trailing,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? trailing;

  @override
  Widget build(BuildContext context) {
    final Color foreground = selected ? Colors.white : AppColors.brandNavy;

    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: ExcludeSemantics(
        child: Material(
          color: selected ? AppColors.authNavy : Colors.white,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              height: 48,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: selected
                      ? AppColors.authNavy
                      : AppColors.authFieldBorder,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Icon(icon, size: 18, color: foreground),
                  const SizedBox(width: 8),
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: foreground,
                    ),
                  ),
                  if (trailing != null) ...<Widget>[
                    const SizedBox(width: 5),
                    Icon(trailing, size: 18, color: foreground),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
