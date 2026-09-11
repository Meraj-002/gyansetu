import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../models/lesson.dart';
import '../../setup/models/classroom_setup.dart';
import 'lesson_widgets.dart';

/// The large recommendation card at the top of the library.
class RecommendedLessonCard extends StatelessWidget {
  const RecommendedLessonCard({
    required this.card,
    required this.classroom,
    required this.busy,
    required this.onStart,
    required this.onDownload,
    super.key,
  });

  final LessonCard card;
  final ClassroomSetup? classroom;

  /// True while this lesson's download is running.
  final bool busy;

  final VoidCallback onStart;
  final VoidCallback onDownload;

  @override
  Widget build(BuildContext context) {
    final Lesson lesson = card.lesson;

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF7FAFE),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.authFieldBorder),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.all(14),
            child: LayoutBuilder(
              builder: (BuildContext context, BoxConstraints constraints) {
                final Widget art = LessonThumbnail(
                  lesson: lesson,
                  width: double.infinity,
                  height: 150,
                );
                final Widget details = _details(lesson);

                // Art beside the text where there is room, stacked below it on
                // a narrow handset.
                if (constraints.maxWidth < 340) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      art,
                      const SizedBox(height: 12),
                      details,
                    ],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    SizedBox(width: constraints.maxWidth * 0.42, child: art),
                    const SizedBox(width: 14),
                    Expanded(child: details),
                  ],
                );
              },
            ),
          ),
          _footer(context),
        ],
      ),
    );
  }

  Widget _details(Lesson lesson) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(
              child: Text(
                lesson.title,
                style: const TextStyle(
                  fontSize: 20,
                  height: 1.2,
                  fontWeight: FontWeight.w800,
                  color: AppColors.brandNavy,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: AppColors.brandGold.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(9),
                border: Border.all(
                  color: AppColors.brandOrange.withValues(alpha: 0.45),
                ),
              ),
              child: const Text(
                'Recommended',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: AppColors.brandOrange,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 9),
        Wrap(
          spacing: 14,
          runSpacing: 6,
          children: <Widget>[
            MetaChip(
              icon: lesson.subject == ClassroomSubject.numeracy
                  ? Icons.calculate_outlined
                  : Icons.menu_book_outlined,
              label: lesson.subject.shortLabel == 'FLN'
                  ? 'Literacy'
                  : lesson.subject.label,
            ),
            MetaChip(
              icon: Icons.groups_outlined,
              label: 'Class ${lesson.classNumber}',
            ),
          ],
        ),
        const SizedBox(height: 12),
        const _GoldLabel('Learning Outcome'),
        const SizedBox(height: 3),
        Text(
          lesson.learningOutcome,
          style: TextStyle(
            fontSize: 13.5,
            height: 1.35,
            color: AppColors.brandNavy.withValues(alpha: 0.85),
          ),
        ),
        if (classroom != null) ...<Widget>[
          const SizedBox(height: 11),
          const _GoldLabel('Language'),
          const SizedBox(height: 4),
          LanguagePairLine(classroom: classroom),
        ],
      ],
    );
  }

  Widget _footer(BuildContext context) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          final Widget stats = Wrap(
            spacing: 16,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: <Widget>[
              MetaChip(
                icon: Icons.schedule,
                label: '${card.lesson.durationMinutes} min',
              ),
              DownloadBadge(
                state: busy ? DownloadState.downloading : card.download,
                onTap: busy || card.downloaded ? null : onDownload,
              ),
              CompletionRing(percent: card.completionPercentage, size: 42),
            ],
          );

          final Widget action = FilledButton.icon(
            onPressed: onStart,
            icon: Icon(
              card.completed ? Icons.replay : Icons.play_arrow_rounded,
              size: 20,
            ),
            label: Text(
              card.completed ? 'Review Lesson' : 'Start Lesson',
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
            ),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.authNavy,
              foregroundColor: Colors.white,
              minimumSize: const Size(0, 50),
              padding: const EdgeInsets.symmetric(horizontal: 18),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          );

          if (constraints.maxWidth < 360) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                stats,
                const SizedBox(height: 12),
                action,
              ],
            );
          }
          return Row(
            children: <Widget>[
              Expanded(child: stats),
              const SizedBox(width: 12),
              action,
            ],
          );
        },
      ),
    );
  }
}

class _GoldLabel extends StatelessWidget {
  const _GoldLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 12.5,
        fontWeight: FontWeight.w700,
        color: AppColors.setupNumeracy,
      ),
    );
  }
}

/// A row in the All Lessons list.
class LessonListCard extends StatelessWidget {
  const LessonListCard({
    required this.card,
    required this.classroom,
    required this.busy,
    required this.onOpen,
    required this.onDownload,
    super.key,
  });

  final LessonCard card;
  final ClassroomSetup? classroom;
  final bool busy;
  final VoidCallback onOpen;
  final VoidCallback onDownload;

  @override
  Widget build(BuildContext context) {
    final Lesson lesson = card.lesson;

    return Semantics(
      button: true,
      label: '${lesson.title}. ${lesson.subject.label}, class '
          '${lesson.classNumber}. ${card.completionPercentage} per cent '
          'complete. ${card.download.label}.',
      child: ExcludeSemantics(
        child: Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            onTap: onOpen,
            borderRadius: BorderRadius.circular(14),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.authFieldBorder),
              ),
              clipBehavior: Clip.antiAlias,
              child: LayoutBuilder(
                builder: (BuildContext context, BoxConstraints constraints) {
                  final Widget main = Padding(
                    padding: const EdgeInsets.all(11),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        LessonThumbnail(
                          lesson: lesson,
                          width: 84,
                          height: 84,
                        ),
                        const SizedBox(width: 12),
                        Expanded(child: _details(lesson)),
                      ],
                    ),
                  );

                  // The reference puts the stats in a divided right-hand
                  // column; below ~430dp that column has nowhere to go, so it
                  // becomes a strip underneath.
                  if (constraints.maxWidth < 430) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        main,
                        const Divider(
                          height: 1,
                          color: AppColors.authFieldBorder,
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(11, 10, 11, 10),
                          child: _stats(context, horizontal: true),
                        ),
                      ],
                    );
                  }

                  return IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        Expanded(child: main),
                        const VerticalDivider(
                          width: 1,
                          color: AppColors.authFieldBorder,
                        ),
                        SizedBox(
                          width: 168,
                          child: Padding(
                            padding: const EdgeInsets.all(11),
                            child: _stats(context, horizontal: false),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _details(Lesson lesson) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          lesson.title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 15.5,
            height: 1.25,
            fontWeight: FontWeight.w800,
            color: AppColors.brandNavy,
          ),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 12,
          runSpacing: 4,
          children: <Widget>[
            MetaChip(
              icon: lesson.subject == ClassroomSubject.numeracy
                  ? Icons.calculate_outlined
                  : Icons.menu_book_outlined,
              label: lesson.subject == ClassroomSubject.numeracy
                  ? 'Numeracy'
                  : 'Literacy',
            ),
            MetaChip(
              icon: Icons.groups_outlined,
              label: 'Class ${lesson.classNumber}',
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          lesson.learningOutcome,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 12.5,
            height: 1.3,
            color: AppColors.brandNavy.withValues(alpha: 0.7),
          ),
        ),
        const SizedBox(height: 6),
        LanguagePairLine(classroom: classroom, compact: true),
      ],
    );
  }

  Widget _stats(BuildContext context, {required bool horizontal}) {
    final Widget duration = MetaChip(
      icon: Icons.schedule,
      label: '${card.lesson.durationMinutes} min',
    );
    // Icon only in the list, as in the reference. The state is still carried by
    // the icon's shape and by the badge's semantics label, so it does not rest
    // on colour; the recommendation card spells it out in words.
    final Widget download = DownloadBadge(
      state: busy ? DownloadState.downloading : card.download,
      showLabel: false,
      onTap: busy || card.downloaded ? null : onDownload,
    );
    final Widget ring = CompletionRing(percent: card.completionPercentage);
    final Widget action = OutlinedButton.icon(
      onPressed: onOpen,
      icon: Icon(
        card.completed ? Icons.replay : Icons.play_arrow_rounded,
        size: 18,
      ),
      label: Text(
        card.actionLabel,
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
      ),
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.authNavy,
        minimumSize: const Size(0, 44),
        padding: const EdgeInsets.symmetric(horizontal: 14),
        side: const BorderSide(color: AppColors.authFieldBorder),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(11)),
      ),
    );

    if (horizontal) {
      return LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          // Duration, download, ring and button cannot share one line on a
          // 320dp handset; below that they split across two.
          if (constraints.maxWidth < 340) {
            return Column(
              children: <Widget>[
                Row(
                  children: <Widget>[
                    duration,
                    const SizedBox(width: 12),
                    Flexible(child: download),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: <Widget>[
                    ring,
                    const SizedBox(width: 12),
                    Expanded(child: action),
                  ],
                ),
              ],
            );
          }
          return Row(
            children: <Widget>[
              duration,
              const SizedBox(width: 12),
              Flexible(child: download),
              const Spacer(),
              ring,
              const SizedBox(width: 10),
              action,
            ],
          );
        },
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: <Widget>[
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: <Widget>[
            Flexible(child: duration),
            const SizedBox(width: 8),
            download,
          ],
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: <Widget>[
            ring,
            const SizedBox(width: 8),
            Flexible(child: action),
          ],
        ),
      ],
    );
  }
}
