import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/constants/app_assets.dart';
import '../../../core/constants/app_colors.dart';
import '../../../models/lesson.dart';
import '../../setup/models/classroom_setup.dart';

/// The circular lesson portrait at the top of lesson detail.
///
/// Falls back to a tinted subject glyph, because most prototype lessons have no
/// artwork and an empty circle would read as a broken image.
class LessonAvatar extends StatelessWidget {
  const LessonAvatar({required this.lesson, this.size = 112, super.key});

  final Lesson lesson;
  final double size;

  @override
  Widget build(BuildContext context) {
    final String? asset = lesson.thumbnailAsset;
    final Color tint = lesson.subject == ClassroomSubject.numeracy
        ? AppColors.setupNumeracy
        : AppColors.setupLiteracy;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        border: Border.all(color: AppColors.outlineVariant, width: 1.4),
      ),
      child: ClipOval(
        child: Padding(
          padding: const EdgeInsets.all(3),
          child: ClipOval(
            child: asset == null
                ? ColoredBox(
                    color: tint.withValues(alpha: 0.12),
                    child: Center(
                      child: Icon(
                        lesson.subject == ClassroomSubject.numeracy
                            ? Icons.calculate_outlined
                            : Icons.menu_book_outlined,
                        size: size * 0.36,
                        color: tint,
                      ),
                    ),
                  )
                : Image.asset(
                    asset,
                    fit: BoxFit.cover,
                    excludeFromSemantics: true,
                  ),
          ),
        ),
      ),
    );
  }
}

/// A small outlined pill, as used for Class and Subject.
class DetailChip extends StatelessWidget {
  const DetailChip({required this.label, this.icon, super.key});

  final String label;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: AppColors.authFieldBorder),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (icon != null) ...<Widget>[
            Icon(icon, size: 16, color: AppColors.brandNavy),
            const SizedBox(width: 6),
          ],
          // Scales down rather than overflowing when a long subject name meets
          // a narrow phone.
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                label,
                maxLines: 1,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppColors.brandNavy,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The provenance badge.
///
/// It renders what the lesson's content metadata actually says. A plan written
/// by a curriculum author shows "Curriculum aligned" and nothing else; the
/// "AI-generated" half appears only once the AI layer has really produced or
/// adapted the content.
class ProvenanceBadge extends StatelessWidget {
  const ProvenanceBadge({
    required this.aiLabel,
    required this.curriculumAligned,
    super.key,
  });

  /// Null when no AI touched this content.
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
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
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
          const SizedBox(width: 7),
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                parts.join('  •  '),
                maxLines: 1,
                style: TextStyle(
                  fontSize: 13,
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

/// The gold Learning Outcome card.
class LearningOutcomeCard extends StatelessWidget {
  const LearningOutcomeCard({
    required this.outcome,
    this.competency,
    super.key,
  });

  final String outcome;

  /// The FLN goal this outcome maps to, shown when the lesson names one.
  final String? competency;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.homeBannerTint,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.brandGold.withValues(alpha: 0.45)),
      ),
      child: Stack(
        children: <Widget>[
          // Tribal motif, faint, purely decorative and excluded from semantics.
          Positioned(
            right: 0,
            top: 0,
            bottom: 0,
            child: Opacity(
              opacity: 0.14,
              child: Image.asset(
                AppAssets.tribalCorner,
                fit: BoxFit.fitHeight,
                excludeFromSemantics: true,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: AppColors.brandGold.withValues(alpha: 0.5),
                    ),
                  ),
                  child: const Icon(
                    Icons.track_changes,
                    size: 22,
                    color: AppColors.secondaryDark,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      const Text(
                        'Learning Outcome',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          color: AppColors.brandNavy,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        outcome,
                        style: TextStyle(
                          fontSize: 14.5,
                          height: 1.4,
                          color: AppColors.brandNavy.withValues(alpha: 0.82),
                        ),
                      ),
                      if (competency != null) ...<Widget>[
                        const SizedBox(height: 8),
                        Text(
                          competency!,
                          style: TextStyle(
                            fontSize: 11.5,
                            height: 1.35,
                            fontWeight: FontWeight.w600,
                            color: AppColors.secondaryDark
                                .withValues(alpha: 0.95),
                          ),
                        ),
                      ],
                    ],
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

/// A round speaker button beside a passage of text.
class SpeakButton extends StatelessWidget {
  const SpeakButton({
    required this.label,
    required this.playing,
    required this.loading,
    required this.onPressed,
    this.tint = AppColors.brandNavy,
    super.key,
  });

  /// Spoken by a screen reader, e.g. "Play the Hindi script".
  final String label;

  final bool playing;
  final bool loading;

  /// Null disables the button, which is how a passage with no voice is shown.
  final VoidCallback? onPressed;

  final Color tint;

  @override
  Widget build(BuildContext context) {
    final bool enabled = onPressed != null;

    return Semantics(
      button: true,
      enabled: enabled,
      label: playing ? 'Pause $label' : label,
      child: ExcludeSemantics(
        child: Material(
          color: Colors.white,
          shape: CircleBorder(
            side: BorderSide(
              color: enabled
                  ? tint.withValues(alpha: 0.25)
                  : AppColors.outlineVariant,
            ),
          ),
          child: InkWell(
            onTap: onPressed,
            customBorder: const CircleBorder(),
            child: SizedBox(
              width: 44,
              height: 44,
              child: Center(
                child: loading
                    ? SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.2,
                          color: tint,
                        ),
                      )
                    : Icon(
                        playing ? Icons.pause : Icons.volume_up_outlined,
                        size: 21,
                        color: enabled
                            ? tint
                            : AppColors.brandMuted.withValues(alpha: 0.6),
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A passage of lesson text with its own speak button.
class PassageCard extends StatelessWidget {
  const PassageCard({
    required this.text,
    required this.speak,
    required this.tint,
    required this.background,
    this.languageLabel,
    this.roleLabel,
    this.footnote,
    super.key,
  });

  /// 'Hindi', 'Santali' — always from the classroom, never a constant.
  ///
  /// Null on the translated card, whose language is already named by the
  /// translate control directly above it; repeating it there would put the same
  /// words on screen twice.
  final String? languageLabel;

  /// '(Teaching Language)' or '(Mother Tongue)'.
  final String? roleLabel;

  final String text;
  final Widget speak;
  final Color tint;
  final Color background;

  /// A caveat shown under the text, e.g. that a translation is unreviewed.
  final String? footnote;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 14, 16),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: tint.withValues(alpha: 0.28)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          // Two Text widgets rather than one rich span: the language name is
          // the classroom's own value and is asserted on directly in tests.
          if (languageLabel != null)
            FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: <Widget>[
                Text(
                  languageLabel!,
                  maxLines: 1,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: tint,
                  ),
                ),
                if (roleLabel != null) ...<Widget>[
                  const SizedBox(width: 7),
                  Text(
                    roleLabel!,
                    maxLines: 1,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w500,
                      color: AppColors.brandNavy.withValues(alpha: 0.55),
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (languageLabel != null) const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: <Widget>[
              Container(
                width: 3.5,
                constraints: const BoxConstraints(minHeight: 26),
                height: text.length > 60 ? 48 : 26,
                decoration: BoxDecoration(
                  color: tint,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  text,
                  style: const TextStyle(
                    fontSize: 16,
                    height: 1.45,
                    fontWeight: FontWeight.w600,
                    color: AppColors.brandNavy,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              speak,
            ],
          ),
          if (footnote != null) ...<Widget>[
            const SizedBox(height: 10),
            Text(
              footnote!,
              style: TextStyle(
                fontSize: 11.5,
                height: 1.35,
                color: AppColors.brandNavy.withValues(alpha: 0.6),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// The waveform on the player card.
///
/// A custom painter rather than an animation package: it is a few dozen lines
/// and costs one repaint per progress tick, which matters on a 2 GB phone.
///
/// The filled portion reflects a position the speech engine actually reported.
/// When nothing has been reported the bars stay uniform, so the waveform never
/// implies a position it does not have.
class AudioWaveform extends StatelessWidget {
  const AudioWaveform({
    required this.progress,
    required this.active,
    this.barCount = 34,
    super.key,
  });

  final double progress;
  final bool active;
  final int barCount;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _WaveformPainter(
        progress: progress,
        active: active,
        barCount: barCount,
      ),
      size: Size.infinite,
    );
  }
}

class _WaveformPainter extends CustomPainter {
  _WaveformPainter({
    required this.progress,
    required this.active,
    required this.barCount,
  });

  final double progress;
  final bool active;
  final int barCount;

  /// Fixed heights so the shape is stable between repaints — a waveform that
  /// reshuffles on every tick reads as noise.
  static final List<double> _heights = List<double>.generate(
    64,
    (int i) {
      final double a = math.sin(i * 0.9) * 0.5 + 0.5;
      final double b = math.sin(i * 0.31 + 1.1) * 0.5 + 0.5;
      return 0.22 + (a * 0.55 + b * 0.45) * 0.78;
    },
  );

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;

    final double gap = size.width / barCount;
    final double barWidth = math.max(1.5, gap * 0.42);
    final Paint paint = Paint()..strokeCap = StrokeCap.round;
    final double centre = size.height / 2;
    final int filled = (barCount * progress).round();

    for (int i = 0; i < barCount; i++) {
      final double height = _heights[i % _heights.length] * size.height;
      final double x = gap * i + gap / 2;
      final bool played = active && i < filled;

      paint
        ..color = Colors.white.withValues(alpha: played ? 0.95 : 0.34)
        ..strokeWidth = barWidth;

      canvas.drawLine(
        Offset(x, centre - height / 2),
        Offset(x, centre + height / 2),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_WaveformPainter old) =>
      old.progress != progress ||
      old.active != active ||
      old.barCount != barCount;
}

/// One of the three controls under the player: Slow, Repeat, Save Audio.
class PlayerControl extends StatelessWidget {
  const PlayerControl({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.active = false,
    this.busy = false,
    this.semanticLabel,
    super.key,
  });

  final IconData icon;
  final String label;

  /// Null disables the control, which is how an unavailable action is shown
  /// rather than by letting a tap do nothing.
  final VoidCallback? onPressed;

  final bool active;
  final bool busy;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      enabled: onPressed != null,
      selected: active,
      label: semanticLabel ?? label,
      child: ExcludeSemantics(
        child: OutlinedButton(
          onPressed: busy ? null : onPressed,
          style: OutlinedButton.styleFrom(
            foregroundColor:
                active ? AppColors.secondaryDark : AppColors.brandNavy,
            backgroundColor: active
                ? AppColors.secondary.withValues(alpha: 0.12)
                : Colors.white,
            minimumSize: const Size(0, 56),
            padding: const EdgeInsets.symmetric(horizontal: 8),
            side: BorderSide(
              color: active
                  ? AppColors.secondary.withValues(alpha: 0.7)
                  : AppColors.authFieldBorder,
              width: active ? 1.6 : 1,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(13),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              if (busy)
                const SizedBox(
                  width: 17,
                  height: 17,
                  child: CircularProgressIndicator(strokeWidth: 2.1),
                )
              else
                Icon(icon, size: 19),
              const SizedBox(width: 8),
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    label,
                    maxLines: 1,
                    style: const TextStyle(
                      fontSize: 14.5,
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
}

/// The Classroom Activity and Quick Assessment cards.
class SectionCard extends StatelessWidget {
  const SectionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.tint,
    required this.background,
    required this.onTap,
    this.footnote,
    super.key,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color tint;
  final Color background;
  final VoidCallback onTap;

  /// Shown under the subtitle, e.g. the last recorded assessment result.
  final String? footnote;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '$title. $subtitle',
      child: ExcludeSemantics(
        child: Material(
          color: background,
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(16),
            child: Container(
              padding: const EdgeInsets.fromLTRB(14, 16, 12, 16),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: tint.withValues(alpha: 0.22)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(color: tint, shape: BoxShape.circle),
                    child: Icon(icon, size: 22, color: Colors.white),
                  ),
                  const SizedBox(width: 13),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          title,
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                            color: tint,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          subtitle,
                          style: TextStyle(
                            fontSize: 14,
                            height: 1.4,
                            color: AppColors.brandNavy.withValues(alpha: 0.8),
                          ),
                        ),
                        if (footnote != null) ...<Widget>[
                          const SizedBox(height: 7),
                          Text(
                            footnote!,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: tint.withValues(alpha: 0.95),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Icon(
                      Icons.chevron_right,
                      size: 24,
                      color: tint.withValues(alpha: 0.75),
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

/// The teaching-tip card.
///
/// The title depends on where the tip came from: content the AI layer wrote is
/// labelled as such, and content a person wrote is not.
class TeachingTipCard extends StatelessWidget {
  const TeachingTipCard({
    required this.text,
    required this.fromAi,
    super.key,
  });

  final String text;
  final bool fromAi;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 16, 15),
      decoration: BoxDecoration(
        color: AppColors.homeBannerTint,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.brandGold.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(
            fromAi ? Icons.auto_awesome : Icons.lightbulb_outline,
            size: 26,
            color: AppColors.brandGold,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  fromAi ? 'AI Tip for Teachers' : 'Tip for Teachers',
                  style: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w800,
                    color: AppColors.brandNavy,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  text,
                  style: TextStyle(
                    fontSize: 13.5,
                    height: 1.4,
                    color: AppColors.brandNavy.withValues(alpha: 0.82),
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
