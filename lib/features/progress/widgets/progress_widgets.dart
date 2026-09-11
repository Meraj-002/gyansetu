import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/constants/app_assets.dart';
import '../../../core/constants/app_colors.dart';
import '../../../models/student_progress.dart';
import '../models/learning_insights.dart';

/// Back, brand, offline pill, more.
///
/// One pill rather than the reference's two: on a 360dp phone a second pill
/// crushes the wordmark. What it says comes from what the code can actually
/// do — every figure on this screen is calculated on the device — not from a
/// constant chosen to look reassuring.
class InsightsHeader extends StatelessWidget {
  const InsightsHeader({
    required this.onBack,
    this.onMore,
    this.backKey,
    this.moreKey,
    this.statusKey,
    super.key,
  });

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
                label: 'Calculated on this device',
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
                          constraints: const BoxConstraints(maxWidth: 130),
                          child: const FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              'Offline Insights',
                              maxLines: 1,
                              style: TextStyle(
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
                  tooltip: 'Insight options',
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

/// A pill that opens a menu — the week selector and the class selector.
class SelectorPill extends StatelessWidget {
  const SelectorPill({
    required this.label,
    required this.onTap,
    required this.semanticLabel,
    this.icon,
    this.compact = false,
    this.tint,
    super.key,
  });

  final String label;
  final IconData? icon;
  final VoidCallback onTap;
  final String semanticLabel;
  final bool compact;
  final Color? tint;

  @override
  Widget build(BuildContext context) {
    final Color colour = tint ?? AppColors.brandNavy;

    return Semantics(
      button: true,
      label: semanticLabel,
      child: ExcludeSemantics(
        child: Material(
          color: compact ? Colors.transparent : AppColors.authChip,
          borderRadius: BorderRadius.circular(26),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(26),
            child: Container(
              padding: EdgeInsets.symmetric(
                horizontal: compact ? 6 : 15,
                vertical: compact ? 6 : 13,
              ),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(26),
                border: compact
                    ? null
                    : Border.all(color: AppColors.authFieldBorder),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  if (icon != null) ...<Widget>[
                    Icon(icon, size: compact ? 17 : 20, color: colour),
                    const SizedBox(width: 8),
                  ],
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: compact ? 14 : 15,
                        fontWeight: FontWeight.w700,
                        color: colour,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(Icons.expand_more, size: 20, color: colour),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// One of the four figures across the top.
class StatCard extends StatelessWidget {
  const StatCard({
    required this.stat,
    required this.icon,
    required this.tint,
    required this.background,
    required this.periodWord,
    super.key,
  });

  final InsightStat stat;
  final IconData icon;
  final Color tint;
  final Color background;

  /// 'week' or 'period' — what the delta line says the change is over.
  final String periodWord;

  @override
  Widget build(BuildContext context) {
    final InsightDelta delta = stat.delta;

    return Semantics(
      label: '${stat.kind.label}, ${stat.value == null ? 'no data' : stat.display}. '
          '${delta.labelFor(periodWord)}',
      child: ExcludeSemantics(
        child: Container(
          padding: const EdgeInsets.fromLTRB(13, 13, 13, 14),
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.authFieldBorder),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Container(
                width: 38,
                height: 38,
                alignment: Alignment.center,
                decoration: BoxDecoration(shape: BoxShape.circle, color: tint),
                child: Icon(icon, size: 20, color: Colors.white),
              ),
              const SizedBox(height: 12),
              Text(
                stat.kind.label,
                style: const TextStyle(
                  fontSize: 13.5,
                  height: 1.25,
                  fontWeight: FontWeight.w700,
                  color: AppColors.brandNavy,
                ),
              ),
              const SizedBox(height: 4),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  stat.display,
                  maxLines: 1,
                  style: TextStyle(
                    fontSize: 30,
                    height: 1.1,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -1,
                    color: stat.value == null ? AppColors.brandMuted : tint,
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  if (delta.known && !delta.isFlat)
                    Padding(
                      padding: const EdgeInsets.only(top: 1),
                      child: Icon(
                        delta.isUp ? Icons.arrow_upward : Icons.arrow_downward,
                        size: 13,
                        color: delta.isUp ? tint : AppColors.brandMuted,
                      ),
                    ),
                  if (delta.known && !delta.isFlat) const SizedBox(width: 3),
                  Expanded(
                    child: Text(
                      delta.labelFor(periodWord),
                      style: TextStyle(
                        fontSize: 11.5,
                        height: 1.3,
                        fontWeight: FontWeight.w600,
                        color: delta.known && delta.isUp
                            ? tint
                            : AppColors.brandMuted,
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

/// A percentage drawn as a ring, animating up from empty once.
class ProgressRing extends StatelessWidget {
  const ProgressRing({
    required this.percentage,
    required this.colour,
    required this.band,
    this.size = 128,
    this.animate = true,
    super.key,
  });

  /// Null draws an empty track and says so, rather than a zero-length arc that
  /// reads as a measured nothing.
  final int? percentage;
  final Color colour;
  final String band;
  final double size;
  final bool animate;

  @override
  Widget build(BuildContext context) {
    final double target = (percentage ?? 0) / 100;

    return Semantics(
      label: percentage == null
          ? band
          : '$percentage per cent, $band',
      child: ExcludeSemantics(
        child: SizedBox(
          width: size,
          height: size,
          child: TweenAnimationBuilder<double>(
            tween: Tween<double>(begin: animate ? 0 : target, end: target),
            duration: animate
                ? const Duration(milliseconds: 650)
                : Duration.zero,
            curve: Curves.easeOutCubic,
            builder: (BuildContext context, double value, _) {
              return CustomPaint(
                painter: _RingPainter(
                  fraction: value,
                  colour: percentage == null ? AppColors.outlineVariant : colour,
                ),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      if (percentage != null)
                        Text(
                          '$percentage%',
                          style: TextStyle(
                            fontSize: size * 0.24,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -1,
                            color: colour,
                          ),
                        ),
                      Padding(
                        padding: EdgeInsets.symmetric(horizontal: size * 0.14),
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            band,
                            maxLines: 1,
                            style: TextStyle(
                              fontSize: size * 0.105,
                              fontWeight: FontWeight.w600,
                              color: percentage == null
                                  ? AppColors.brandMuted
                                  : colour,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  const _RingPainter({required this.fraction, required this.colour});

  final double fraction;
  final Color colour;

  @override
  void paint(Canvas canvas, Size size) {
    final double stroke = size.width * 0.095;
    final Rect rect = Offset(stroke / 2, stroke / 2) &
        Size(size.width - stroke, size.height - stroke);

    canvas.drawArc(
      rect,
      0,
      math.pi * 2,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..color = AppColors.authIconCircle,
    );

    if (fraction <= 0) return;
    canvas.drawArc(
      rect,
      -math.pi / 2,
      math.pi * 2 * fraction.clamp(0.0, 1.0),
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round
        ..color = colour,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.fraction != fraction || old.colour != colour;
}

/// One learning-area card: ring, blurb, improvement chip.
class LearningAreaCard extends StatelessWidget {
  const LearningAreaCard({
    required this.insight,
    required this.icon,
    required this.colour,
    required this.tint,
    required this.periodWord,
    this.ringSize = 128,
    super.key,
  });

  final LearningAreaInsight insight;
  final IconData icon;
  final Color colour;
  final Color tint;
  final String periodWord;
  final double ringSize;

  @override
  Widget build(BuildContext context) {
    final InsightDelta delta = insight.improvement;

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 16, 14, 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.authFieldBorder),
      ),
      child: Column(
        children: <Widget>[
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              insight.area.label,
              maxLines: 1,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: colour,
              ),
            ),
          ),
          const SizedBox(height: 14),
          ProgressRing(
            percentage: insight.percentage,
            colour: colour,
            band: insight.band,
            size: ringSize,
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Container(
                width: 34,
                height: 34,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: tint,
                ),
                child: Icon(icon, size: 18, color: colour),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  insight.area.blurb,
                  style: const TextStyle(
                    fontSize: 13,
                    height: 1.4,
                    color: AppColors.brandBody,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: tint,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  if (delta.known && !delta.isFlat)
                    Icon(
                      delta.isUp ? Icons.arrow_upward : Icons.arrow_downward,
                      size: 13,
                      color: colour,
                    ),
                  if (delta.known && !delta.isFlat) const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      delta.labelFor(periodWord),
                      maxLines: 2,
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.3,
                        fontWeight: FontWeight.w700,
                        color: delta.known ? colour : AppColors.brandMuted,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A child's initials in a coloured circle.
///
/// Initials rather than a picture. The app stores no photographs of children,
/// and a stock face standing in for a real pupil would be worse than a letter.
class StudentAvatar extends StatelessWidget {
  const StudentAvatar({required this.student, this.size = 40, super.key});

  final StudentProgress student;
  final double size;

  static const List<Color> _palette = <Color>[
    AppColors.setupNumeracy,
    AppColors.setupLiteracy,
    AppColors.brandOrange,
    AppColors.liveGlowViolet,
    AppColors.info,
    AppColors.brandNavy,
  ];

  Color get _colour =>
      _palette[student.studentId.hashCode.abs() % _palette.length];

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: student.name,
      child: ExcludeSemantics(
        child: Container(
          width: size,
          height: size,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: _colour.withValues(alpha: 0.14),
            border: Border.all(color: _colour.withValues(alpha: 0.45)),
          ),
          child: Text(
            student.initials,
            style: TextStyle(
              fontSize: size * 0.34,
              fontWeight: FontWeight.w800,
              color: _colour,
            ),
          ),
        ),
      ),
    );
  }
}

/// A row of avatars with a "+n" when there are more than fit.
class StudentAvatarRow extends StatelessWidget {
  const StudentAvatarRow({
    required this.students,
    this.max = 6,
    this.size = 40,
    super.key,
  });

  final List<StudentProgress> students;
  final int max;
  final double size;

  @override
  Widget build(BuildContext context) {
    final List<StudentProgress> shown = students.take(max).toList();
    final int extra = students.length - shown.length;

    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: <Widget>[
        for (final StudentProgress s in shown)
          StudentAvatar(student: s, size: size),
        if (extra > 0)
          Container(
            width: size,
            height: size,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white,
              border: Border.all(color: AppColors.authFieldBorder),
            ),
            child: Text(
              '+$extra',
              style: TextStyle(
                fontSize: size * 0.3,
                fontWeight: FontWeight.w700,
                color: AppColors.brandMuted,
              ),
            ),
          ),
      ],
    );
  }
}

/// A short note that is neither an error nor a success — used for the sample
/// data warning and the empty period.
class InsightNotice extends StatelessWidget {
  const InsightNotice({
    required this.message,
    this.icon = Icons.info_outline,
    this.tint = AppColors.warning,
    this.background = AppColors.homeBannerTint,
    this.border = AppColors.secondaryContainer,
    super.key,
  });

  final String message;
  final IconData icon;
  final Color tint;
  final Color background;
  final Color border;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(13, 12, 13, 12),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(icon, size: 17, color: tint),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                fontSize: 12.5,
                height: 1.45,
                color: AppColors.brandBody,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The strip along the bottom.
///
/// It says what the app actually did — arithmetic on this device — rather than
/// claiming a model was involved.
class InsightsFooter extends StatelessWidget {
  const InsightsFooter({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: AppColors.setupNumeracyTint,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.authFieldBorder),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Icon(
            Icons.calculate_outlined,
            size: 18,
            color: AppColors.setupNumeracy,
          ),
          const SizedBox(width: 10),
          const Expanded(
            child: Text.rich(
              TextSpan(
                children: <InlineSpan>[
                  TextSpan(
                    text: 'GyanSetu AI ',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      color: AppColors.brandNavy,
                    ),
                  ),
                  TextSpan(
                    text: 'works these figures out on this phone, from the '
                        'lessons, assessments and sessions you have recorded. '
                        'Nothing is sent anywhere.',
                  ),
                ],
                style: TextStyle(
                  fontSize: 12.5,
                  height: 1.45,
                  color: AppColors.brandBody,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
