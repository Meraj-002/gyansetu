import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../models/question.dart';
import '../../../models/worksheet.dart';

/// A numbered section heading, as in "2. Question Types (Select all that
/// apply)".
class SectionHeading extends StatelessWidget {
  const SectionHeading({required this.number, required this.title, this.hint, super.key});

  final int number;
  final String title;

  /// The lighter note in brackets.
  final String? hint;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text.rich(
        TextSpan(
          children: <InlineSpan>[
            TextSpan(text: '$number. $title'),
            if (hint != null)
              TextSpan(
                text: '  ($hint)',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: AppColors.brandNavy.withValues(alpha: 0.62),
                ),
              ),
          ],
          style: const TextStyle(
            fontSize: 16.5,
            fontWeight: FontWeight.w800,
            color: AppColors.brandNavy,
          ),
        ),
      ),
    );
  }
}

/// A selectable card. Used for difficulty, question types, counts and visual
/// examples, so selection looks and behaves the same everywhere.
class ChoiceCard extends StatelessWidget {
  const ChoiceCard({
    required this.selected,
    required this.onTap,
    required this.child,
    required this.semanticLabel,
    this.tint = AppColors.liveGlowViolet,
    this.indicator = ChoiceIndicator.check,
    this.padding = const EdgeInsets.fromLTRB(12, 12, 12, 12),
    super.key,
  });

  final bool selected;
  final VoidCallback onTap;
  final Widget child;

  /// Read aloud in place of the card's contents.
  final String semanticLabel;

  final Color tint;
  final ChoiceIndicator indicator;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: semanticLabel,
      child: ExcludeSemantics(
        child: Material(
          color: selected ? tint.withValues(alpha: 0.06) : Colors.white,
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(14),
            child: Container(
              // Comfortably above the 44dp floor, which matters for a teacher
              // tapping quickly at the front of a class.
              constraints: const BoxConstraints(minHeight: 56),
              padding: padding,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: selected
                      ? tint.withValues(alpha: 0.75)
                      : AppColors.authFieldBorder,
                  width: selected ? 1.6 : 1,
                ),
              ),
              child: Stack(
                children: <Widget>[
                  child,
                  if (indicator != ChoiceIndicator.none)
                    Positioned(
                      top: 0,
                      right: 0,
                      child: _Indicator(
                        selected: selected,
                        tint: tint,
                        indicator: indicator,
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

enum ChoiceIndicator { check, radio, none }

class _Indicator extends StatelessWidget {
  const _Indicator({
    required this.selected,
    required this.tint,
    required this.indicator,
  });

  final bool selected;
  final Color tint;
  final ChoiceIndicator indicator;

  @override
  Widget build(BuildContext context) {
    if (indicator == ChoiceIndicator.radio) {
      return Container(
        width: 20,
        height: 20,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: selected ? tint : Colors.white,
          border: Border.all(
            color: selected ? tint : AppColors.outline,
            width: 1.6,
          ),
        ),
        child: selected
            ? Center(
                child: Container(
                  width: 7,
                  height: 7,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white,
                  ),
                ),
              )
            : null,
      );
    }

    return Container(
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(6),
        color: selected ? tint : Colors.white,
        border: Border.all(
          color: selected ? tint : AppColors.outline,
          width: 1.4,
        ),
      ),
      child: selected
          ? const Icon(Icons.check, size: 15, color: Colors.white)
          : null,
    );
  }
}

/// The lesson and learning-outcome pair under the title.
class ContextCard extends StatelessWidget {
  const ContextCard({
    required this.icon,
    required this.tint,
    required this.label,
    required this.value,
    super.key,
  });

  final IconData icon;
  final Color tint;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.authFieldBorder),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: tint.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 20, color: tint),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12.5,
                    color: AppColors.brandNavy.withValues(alpha: 0.65),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 15.5,
                    height: 1.3,
                    fontWeight: FontWeight.w700,
                    color: AppColors.brandNavy,
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

/// A row of the same object repeated, which is what a counting question shows.
///
/// Font glyphs rather than images: a worksheet has to render with no
/// connection, and four bitmaps for four shapes would be weight for nothing.
class VisualRow extends StatelessWidget {
  const VisualRow({
    required this.example,
    required this.count,
    this.size = 24,
    this.maxPerRow = 10,
    super.key,
  });

  final VisualExample example;
  final int count;
  final double size;
  final int maxPerRow;

  @override
  Widget build(BuildContext context) {
    if (count <= 0) return const SizedBox.shrink();

    return Semantics(
      label: '$count ${example.label}',
      child: ExcludeSemantics(
        child: Wrap(
          spacing: 6,
          runSpacing: 4,
          children: <Widget>[
            for (int i = 0; i < count.clamp(0, maxPerRow * 3); i++)
              Text(example.glyph, style: TextStyle(fontSize: size)),
          ],
        ),
      ),
    );
  }
}

/// One generated question, as the preview renders it.
class QuestionCard extends StatelessWidget {
  const QuestionCard({
    required this.question,
    required this.targetLanguageLabel,
    this.showAnswers = true,
    super.key,
  });

  final WorksheetQuestion question;

  /// Named so a missing translation can say which language is missing.
  final String targetLanguageLabel;

  final bool showAnswers;

  @override
  Widget build(BuildContext context) {
    final VisualExample? example =
        VisualExample.byName(question.visualAsset);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(14, 13, 14, 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.authFieldBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Container(
                width: 26,
                height: 26,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.setupNumeracy.withValues(alpha: 0.12),
                ),
                child: Text(
                  '${question.order}',
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                    color: AppColors.setupNumeracy,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      question.questionText,
                      style: const TextStyle(
                        fontSize: 16,
                        height: 1.4,
                        fontWeight: FontWeight.w600,
                        color: AppColors.brandNavy,
                      ),
                    ),
                    if (question.isBilingual) ...<Widget>[
                      const SizedBox(height: 4),
                      Text(
                        question.translatedQuestionText!,
                        style: TextStyle(
                          fontSize: 14.5,
                          height: 1.4,
                          color: AppColors.setupLiteracy.withValues(alpha: 0.95),
                        ),
                      ),
                    ] else ...<Widget>[
                      const SizedBox(height: 4),
                      Text(
                        // Said plainly rather than printed as a blank line: a
                        // worksheet goes home with a child.
                        'No $targetLanguageLabel text for this question yet.',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.brandNavy.withValues(alpha: 0.55),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          if (example != null && question.visualCount > 0) ...<Widget>[
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.only(left: 36),
              child: VisualRow(
                example: example,
                count: question.visualCount,
              ),
            ),
          ],
          if (question.options.isNotEmpty) ...<Widget>[
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.only(left: 36),
              child: Wrap(
                spacing: 10,
                runSpacing: 8,
                children: <Widget>[
                  for (final String option in question.options)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppColors.outline),
                      ),
                      child: Text(
                        option,
                        style: const TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w600,
                          color: AppColors.brandNavy,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
          if (showAnswers) ...<Widget>[
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.only(left: 36),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const Icon(
                    Icons.check_circle_outline,
                    size: 16,
                    color: AppColors.setupLiteracy,
                  ),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      question.explanation == null
                          ? 'Answer: ${question.correctAnswer}'
                          : 'Answer: ${question.correctAnswer} — '
                              '${question.explanation}',
                      style: TextStyle(
                        fontSize: 12.5,
                        height: 1.35,
                        color: AppColors.setupLiteracy.withValues(alpha: 0.95),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// The pill under the screen title.
class CapabilityBadge extends StatelessWidget {
  const CapabilityBadge({
    required this.aiLabel,
    required this.curriculumAligned,
    super.key,
  });

  /// Null when no model wrote anything, which is what keeps the badge honest.
  final String? aiLabel;

  final bool curriculumAligned;

  @override
  Widget build(BuildContext context) {
    final String? ai = aiLabel;
    final List<String> parts = <String>[
      ?ai,
      if (curriculumAligned) 'Curriculum aligned',
    ];
    if (parts.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
      decoration: BoxDecoration(
        color: AppColors.authChip,
        borderRadius: BorderRadius.circular(11),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(
            ai != null ? Icons.auto_awesome : Icons.verified_outlined,
            size: 16,
            color: ai != null ? AppColors.brandGold : AppColors.setupLiteracy,
          ),
          const SizedBox(width: 8),
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                parts.join('  •  '),
                maxLines: 1,
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  color: AppColors.brandNavy.withValues(alpha: 0.85),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class WorksheetNotice extends StatelessWidget {
  const WorksheetNotice({
    required this.message,
    required this.onDismiss,
    this.onRetry,
    super.key,
  });

  final String message;
  final VoidCallback onDismiss;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 11, 4, 11),
      decoration: BoxDecoration(
        color: AppColors.homeBannerTint,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.brandGold.withValues(alpha: 0.45)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Icon(
            Icons.info_outline,
            size: 19,
            color: AppColors.secondaryDark,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  message,
                  style: TextStyle(
                    fontSize: 13.5,
                    height: 1.4,
                    color: AppColors.brandNavy.withValues(alpha: 0.88),
                  ),
                ),
                if (onRetry != null)
                  TextButton(
                    key: const Key('worksheet-retry'),
                    onPressed: onRetry,
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.authNavy,
                      minimumSize: const Size(48, 40),
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                    ),
                    child: const Text(
                      'Try Again',
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
              ],
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
