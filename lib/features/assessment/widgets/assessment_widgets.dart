import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/constants/app_assets.dart';
import '../../../core/constants/app_colors.dart';
import '../../../models/assessment_question.dart';
import '../../../models/assessment_result.dart';

/// The bar across the top of the assessment screens.
///
/// One status pill, not the two in the design reference: on a 360dp phone two
/// pills and a wordmark cannot share a line without the labels shrinking to
/// nothing. What the pill says comes from the device, never from a constant.
class AssessmentHeader extends StatelessWidget {
  const AssessmentHeader({
    required this.status,
    required this.onBack,
    this.onMore,
    this.backKey,
    this.moreKey,
    this.statusKey,
    super.key,
  });

  final String status;
  final VoidCallback onBack;
  final VoidCallback? onMore;
  final Key? backKey;
  final Key? moreKey;
  final Key? statusKey;

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
                key: backKey,
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
                    child: const ExcludeSemantics(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text.rich(
                          TextSpan(
                            children: <InlineSpan>[
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
                key: statusKey,
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
                        const Icon(
                          Icons.cloud_off_outlined,
                          size: 15,
                          color: AppColors.setupLiteracy,
                        ),
                        const SizedBox(width: 7),
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 130),
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
              if (onMore != null)
                IconButton(
                  key: moreKey,
                  onPressed: onMore,
                  tooltip: 'Assessment options',
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

/// "Question 4 of 10", a bar, and "40% Completed".
class QuizProgressBar extends StatelessWidget {
  const QuizProgressBar({
    required this.label,
    required this.progress,
    required this.percent,
    super.key,
  });

  final String label;

  /// 0..1.
  final double progress;
  final int percent;

  @override
  Widget build(BuildContext context) {
    final Widget bar = ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: LinearProgressIndicator(
        value: progress.clamp(0.0, 1.0),
        minHeight: 8,
        backgroundColor: AppColors.authIconCircle,
        valueColor: const AlwaysStoppedAnimation<Color>(AppColors.setupNumeracy),
      ),
    );

    return Semantics(
      label: '$label, $percent per cent completed',
      child: ExcludeSemantics(
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            // Below this the three parts cannot share a line legibly, so the
            // bar drops to its own row. "Question 10 of 10" beside
            // "100% Completed" is the widest this ever gets.
            if (constraints.maxWidth < 440) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: <Widget>[
                      Flexible(child: _label(label, AppColors.brandNavy)),
                      const SizedBox(width: 10),
                      Flexible(
                        child: _label(
                          '$percent% Completed',
                          AppColors.setupNumeracy,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  bar,
                ],
              );
            }

            return Row(
              children: <Widget>[
                Flexible(child: _label(label, AppColors.brandNavy)),
                const SizedBox(width: 12),
                Expanded(flex: 3, child: bar),
                const SizedBox(width: 12),
                Flexible(
                  child: _label(
                    '$percent% Completed',
                    AppColors.setupNumeracy,
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  static Widget _label(String text, Color color) => FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          text,
          maxLines: 1,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
      );
}

/// The countable group above the options.
///
/// Every picture is a bundled asset. Nothing here can fetch anything, which is
/// what lets the assessment run in a classroom with no signal.
class QuestionVisual extends StatelessWidget {
  const QuestionVisual({required this.visual, super.key});

  final QuizVisual visual;

  @override
  Widget build(BuildContext context) {
    final List<QuizObject> objects = visual.objects;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.authFieldBorder),
      ),
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          // Four across at most, so a group of nine reads as rows a child can
          // count rather than one long line.
          final int perRow = math.min(4, math.max(3, objects.length));
          final double gap = 12;
          final double size = ((constraints.maxWidth - gap * (perRow - 1)) /
                  perRow)
              .clamp(44.0, 78.0);

          return Semantics(
            label: _semanticLabel(objects),
            child: ExcludeSemantics(
              child: Wrap(
                alignment: WrapAlignment.center,
                runAlignment: WrapAlignment.center,
                spacing: gap,
                runSpacing: gap,
                children: <Widget>[
                  for (final QuizObject o in objects)
                    SizedBox(
                      width: size,
                      height: size,
                      child: Image.asset(
                        o.asset,
                        fit: BoxFit.contain,
                        filterQuality: FilterQuality.medium,
                        excludeFromSemantics: true,
                        errorBuilder: (_, _, _) => _MissingPicture(label: o.label),
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  /// Read aloud by a screen reader in place of the pictures. It names the
  /// objects but never the total, which is the answer.
  static String _semanticLabel(List<QuizObject> objects) {
    final Set<String> kinds = <String>{
      for (final QuizObject o in objects) o.label,
    };
    return kinds.length == 1
        ? 'A group of ${kinds.first}s to count'
        : 'A group of ${kinds.join(' and ')} to count';
  }
}

/// Shown in place of a picture that will not decode, so a broken asset is
/// visible in testing rather than an invisible gap.
class _MissingPicture extends StatelessWidget {
  const _MissingPicture({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.authIconCircle,
        borderRadius: BorderRadius.circular(10),
      ),
      alignment: Alignment.center,
      child: Text(
        label,
        textAlign: TextAlign.center,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: AppColors.brandMuted,
        ),
      ),
    );
  }
}

/// One answer tile: a letter badge above the answer itself.
class OptionTile extends StatelessWidget {
  const OptionTile({
    required this.letter,
    required this.label,
    required this.selected,
    required this.onTap,
    this.state = OptionState.unmarked,
    super.key,
  });

  final String letter;
  final String label;
  final bool selected;
  final VoidCallback? onTap;

  /// Whether this tile is being shown with the marking revealed.
  final OptionState state;

  @override
  Widget build(BuildContext context) {
    final (Color border, Color fill, Color ink) = switch (state) {
      OptionState.correct => (
          AppColors.setupLiteracy,
          AppColors.setupLiteracyTint,
          AppColors.setupLiteracy,
        ),
      OptionState.wrong => (
          AppColors.error,
          const Color(0xFFFDF3F2),
          AppColors.error,
        ),
      OptionState.unmarked when selected => (
          AppColors.setupNumeracy,
          AppColors.setupNumeracyTint,
          AppColors.brandNavy,
        ),
      OptionState.unmarked => (
          AppColors.authFieldBorder,
          Colors.white,
          AppColors.brandNavy,
        ),
    };

    return Semantics(
      button: onTap != null,
      selected: selected,
      label: 'Option $letter, $label',
      child: ExcludeSemantics(
        child: Material(
          color: fill,
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(14),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: border,
                  width: selected || state != OptionState.unmarked ? 2 : 1,
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Container(
                    width: 24,
                    height: 24,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: border),
                    ),
                    child: Text(
                      letter,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: ink,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      label,
                      maxLines: 1,
                      style: TextStyle(
                        fontSize: 30,
                        height: 1.05,
                        fontWeight: FontWeight.w700,
                        color: ink,
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

/// Whether an option tile is showing the marking.
enum OptionState { unmarked, correct, wrong }

/// The score, drawn as a ring.
class ScoreRing extends StatelessWidget {
  const ScoreRing({
    required this.score,
    required this.total,
    required this.percentage,
    this.size = 132,
    super.key,
  });

  final int score;
  final int total;
  final int percentage;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '$score out of $total, $percentage per cent',
      child: ExcludeSemantics(
        child: SizedBox(
          width: size,
          height: size,
          child: CustomPaint(
            painter: _RingPainter(
              fraction: total == 0 ? 0 : score / total,
              colour: _ringColour(percentage),
            ),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text.rich(
                    TextSpan(
                      children: <InlineSpan>[
                        TextSpan(
                          text: '$score',
                          style: TextStyle(
                            fontSize: size * 0.30,
                            fontWeight: FontWeight.w800,
                            color: _ringColour(percentage),
                          ),
                        ),
                        TextSpan(
                          text: '/$total',
                          style: TextStyle(
                            fontSize: size * 0.14,
                            fontWeight: FontWeight.w700,
                            color: AppColors.brandMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    '$percentage%',
                    style: TextStyle(
                      fontSize: size * 0.11,
                      fontWeight: FontWeight.w600,
                      color: AppColors.brandMuted,
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

  static Color _ringColour(int percentage) => switch (percentage) {
        >= 70 => AppColors.setupLiteracy,
        >= 40 => AppColors.warning,
        _ => AppColors.error,
      };
}

class _RingPainter extends CustomPainter {
  const _RingPainter({required this.fraction, required this.colour});

  final double fraction;
  final Color colour;

  @override
  void paint(Canvas canvas, Size size) {
    const double stroke = 11;
    final Rect rect = Offset(stroke / 2, stroke / 2) &
        Size(size.width - stroke, size.height - stroke);

    final Paint track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..color = AppColors.authIconCircle;

    final Paint arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..color = colour;

    canvas.drawArc(rect, 0, math.pi * 2, false, track);
    if (fraction > 0) {
      canvas.drawArc(
        rect,
        -math.pi / 2,
        math.pi * 2 * fraction.clamp(0.0, 1.0),
        false,
        arc,
      );
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.fraction != fraction || old.colour != colour;
}

/// A titled list of concepts, used for both halves of the summary.
class ConceptList extends StatelessWidget {
  const ConceptList({
    required this.title,
    required this.icon,
    required this.colour,
    required this.concepts,
    required this.emptyLabel,
    this.showCounts = false,
    super.key,
  });

  final String title;
  final IconData icon;
  final Color colour;
  final List<ConceptPerformance> concepts;

  /// What to say when the list is empty. An empty list is a real result — every
  /// concept understood, or none of them — and says so rather than vanishing.
  final String emptyLabel;

  /// Shows "2 of 3" beside each concept, on the detailed screen.
  final bool showCounts;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.authFieldBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(icon, size: 18, color: colour),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: colour,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (concepts.isEmpty)
            Text(
              emptyLabel,
              style: const TextStyle(
                fontSize: 13,
                height: 1.45,
                color: AppColors.brandMuted,
              ),
            )
          else
            for (final ConceptPerformance c in concepts)
              Padding(
                padding: const EdgeInsets.only(bottom: 9),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Icon(
                        c.understood
                            ? Icons.check_circle
                            : Icons.circle,
                        size: c.understood ? 16 : 11,
                        color: colour,
                      ),
                    ),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Text(
                        c.concept.label,
                        style: const TextStyle(
                          fontSize: 13.5,
                          height: 1.35,
                          fontWeight: FontWeight.w600,
                          color: AppColors.brandBody,
                        ),
                      ),
                    ),
                    if (showCounts) ...<Widget>[
                      const SizedBox(width: 8),
                      Text(
                        '${c.correct} of ${c.total}',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: AppColors.brandMuted,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
        ],
      ),
    );
  }
}

/// A note the teacher should read but that is not an error.
class AssessmentNotice extends StatelessWidget {
  const AssessmentNotice({
    required this.message,
    this.onDismiss,
    super.key,
  });

  final String message;
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(13, 11, 6, 11),
      decoration: BoxDecoration(
        color: AppColors.homeBannerTint,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: AppColors.secondaryContainer),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Padding(
            padding: EdgeInsets.only(top: 1),
            child: Icon(
              Icons.info_outline,
              size: 17,
              color: AppColors.warning,
            ),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                fontSize: 13,
                height: 1.4,
                color: AppColors.brandBody,
              ),
            ),
          ),
          if (onDismiss != null)
            IconButton(
              onPressed: onDismiss,
              tooltip: 'Dismiss',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.close, size: 17),
              color: AppColors.brandMuted,
            ),
        ],
      ),
    );
  }
}
