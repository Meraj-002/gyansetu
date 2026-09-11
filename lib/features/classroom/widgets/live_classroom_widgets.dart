import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../models/classroom_state.dart';

/// A row of vertical bars driven by microphone level.
///
/// A custom painter rather than an animation package. The shape is fixed and
/// only its height scales, so a repaint is a few dozen `drawLine` calls — which
/// is what makes it affordable on a 2 GB phone at speaking speed.
///
/// The bars are driven by a real amplitude where the platform reports one. Where
/// it does not, [amplitude] stays at its resting value and the bars simply sit
/// still, rather than animating to imply audio nobody measured.
class LiveWaveform extends StatelessWidget {
  const LiveWaveform({
    required this.amplitude,
    required this.tint,
    this.barCount = 44,
    this.mirrored = false,
    this.active = true,
    super.key,
  });

  /// 0..1.
  final ValueListenable<double> amplitude;

  final Color tint;
  final int barCount;

  /// Draws the taller end towards the right, for the waveform left of the
  /// microphone.
  final bool mirrored;

  /// False dims the whole row, for a card that is not the one speaking.
  final bool active;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: ValueListenableBuilder<double>(
        valueListenable: amplitude,
        builder: (BuildContext context, double level, _) => CustomPaint(
          painter: _WaveformPainter(
            level: level,
            tint: tint,
            barCount: barCount,
            mirrored: mirrored,
            active: active,
          ),
          size: Size.infinite,
        ),
      ),
    );
  }
}

class _WaveformPainter extends CustomPainter {
  _WaveformPainter({
    required this.level,
    required this.tint,
    required this.barCount,
    required this.mirrored,
    required this.active,
  });

  final double level;
  final Color tint;
  final int barCount;
  final bool mirrored;
  final bool active;

  /// Fixed profile, so the shape does not reshuffle between frames. A waveform
  /// that jumps around every repaint reads as noise rather than as speech.
  static final List<double> _profile = List<double>.generate(
    72,
    (int i) => 0.18 +
        ((math.sin(i * 0.77) * 0.5 + 0.5) * 0.6 +
                (math.sin(i * 0.23 + 2.1) * 0.5 + 0.5) * 0.4) *
            0.82,
  );

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0 || barCount <= 0) return;

    final double gap = size.width / barCount;
    final double barWidth = math.max(1.2, gap * 0.34);
    final double centre = size.height / 2;
    final Paint paint = Paint()..strokeCap = StrokeCap.round;

    // A resting level so the row is visible before anyone speaks, without
    // implying activity: it is a flat, dim line, not a moving one.
    final double reach = active ? (0.28 + level * 0.72) : 0.16;

    for (int i = 0; i < barCount; i++) {
      final int index = mirrored ? barCount - 1 - i : i;
      // Tapers towards the outer edge, as in the artwork.
      final double falloff = 0.35 + 0.65 * (index / barCount);
      final double height =
          _profile[i % _profile.length] * size.height * reach * falloff;

      paint
        ..color = tint.withValues(alpha: active ? 0.28 + level * 0.5 : 0.2)
        ..strokeWidth = barWidth;

      final double x = gap * i + gap / 2;
      canvas.drawLine(
        Offset(x, centre - height / 2),
        Offset(x, centre + height / 2),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_WaveformPainter old) =>
      old.level != level ||
      old.active != active ||
      old.tint != tint ||
      old.barCount != barCount ||
      old.mirrored != mirrored;
}

/// The glowing microphone in the middle of the screen.
class MicrophoneOrb extends StatelessWidget {
  const MicrophoneOrb({
    required this.state,
    required this.enabled,
    required this.onTap,
    this.size = 190,
    super.key,
  });

  static const Key orbKey = Key('live-microphone');

  final ClassroomState state;

  /// False when the pipeline cannot run — a missing recogniser, or a muted
  /// session. The orb dims and the tap does nothing rather than starting
  /// something that must fail.
  final bool enabled;

  final VoidCallback onTap;
  final double size;

  IconData get _icon => switch (state) {
        ClassroomState.muted => Icons.mic_off,
        ClassroomState.playing => Icons.graphic_eq,
        ClassroomState.error => Icons.refresh,
        _ => Icons.mic,
      };

  @override
  Widget build(BuildContext context) {
    final double inner = size * 0.66;

    return Semantics(
      button: true,
      enabled: enabled,
      label: 'Microphone. ${state.microphoneLabel}',
      child: ExcludeSemantics(
        child: GestureDetector(
          key: MicrophoneOrb.orbKey,
          onTap: enabled ? onTap : null,
          behavior: HitTestBehavior.opaque,
          child: SizedBox(
            width: size,
            height: size,
            child: Stack(
              alignment: Alignment.center,
              children: <Widget>[
                // The dashed outer ring, drawn rather than animated: a rotating
                // ring is a per-frame repaint for no information.
                CustomPaint(
                  size: Size.square(size),
                  painter: _OrbRingPainter(
                    active: enabled && state != ClassroomState.muted,
                    listening: state == ClassroomState.listening,
                  ),
                ),
                Container(
                  width: inner,
                  height: inner,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: enabled
                          ? const <Color>[
                              AppColors.liveGlowCyan,
                              AppColors.liveGlowBlue,
                              AppColors.liveGlowViolet,
                            ]
                          : <Color>[
                              AppColors.liveBorder,
                              AppColors.liveCard,
                            ],
                    ),
                    boxShadow: enabled
                        ? <BoxShadow>[
                            BoxShadow(
                              color: AppColors.liveGlowBlue.withValues(
                                alpha: state == ClassroomState.listening
                                    ? 0.55
                                    : 0.3,
                              ),
                              blurRadius: 34,
                              spreadRadius: 2,
                            ),
                          ]
                        : null,
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                      Icon(
                        _icon,
                        size: inner * 0.31,
                        color: Colors.white,
                      ),
                      SizedBox(height: inner * 0.06),
                      Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: inner * 0.12,
                        ),
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            state.microphoneLabel,
                            maxLines: 1,
                            style: TextStyle(
                              fontSize: inner * 0.115,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
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
    );
  }
}

class _OrbRingPainter extends CustomPainter {
  _OrbRingPainter({required this.active, required this.listening});

  final bool active;
  final bool listening;

  @override
  void paint(Canvas canvas, Size size) {
    final Offset centre = Offset(size.width / 2, size.height / 2);
    final double radius = size.width / 2 - 2;

    final Paint dashed = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = listening ? 2.2 : 1.4
      ..strokeCap = StrokeCap.round
      ..color = (active ? AppColors.liveGlowBlue : AppColors.liveBorder)
          .withValues(alpha: listening ? 0.85 : 0.5);

    const int dashes = 44;
    const double sweep = (math.pi * 2) / dashes;
    for (int i = 0; i < dashes; i++) {
      canvas.drawArc(
        Rect.fromCircle(center: centre, radius: radius),
        i * sweep,
        sweep * 0.55,
        false,
        dashed,
      );
    }

    // The soft inner halo between the ring and the orb.
    canvas.drawCircle(
      centre,
      radius * 0.82,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 10
        ..color = (active ? AppColors.liveGlowViolet : AppColors.liveBorder)
            .withValues(alpha: 0.12),
    );
  }

  @override
  bool shouldRepaint(_OrbRingPainter old) =>
      old.active != active || old.listening != listening;
}

/// A card belonging to one speaker: the teacher, the AI or a pupil.
class SpeakerCard extends StatelessWidget {
  const SpeakerCard({
    required this.tint,
    required this.icon,
    required this.title,
    required this.status,
    required this.child,
    this.trailing,
    this.statusIcon,
    super.key,
  });

  final Color tint;
  final IconData icon;
  final String title;

  /// 'Speaking…', 'AI Processing', 'Listening…'. Comes from the state machine.
  final String status;

  final IconData? statusIcon;
  final Widget? trailing;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 16),
      decoration: BoxDecoration(
        color: AppColors.liveCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.liveBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: tint.withValues(alpha: 0.14),
                  border: Border.all(color: tint.withValues(alpha: 0.7)),
                ),
                child: Icon(icon, size: 22, color: tint),
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
                        title,
                        maxLines: 1,
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: tint,
                        ),
                      ),
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: <Widget>[
                        Icon(
                          statusIcon ?? Icons.circle,
                          size: statusIcon == null ? 8 : 14,
                          color: tint,
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            status,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w500,
                              color: AppColors.liveTextMuted,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (trailing != null) ...<Widget>[
                const SizedBox(width: 8),
                trailing!,
              ],
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

/// The round speaker button on a card.
class LiveSpeakButton extends StatelessWidget {
  const LiveSpeakButton({
    required this.label,
    required this.onPressed,
    this.tint = AppColors.liveAi,
    this.playing = false,
    super.key,
  });

  final String label;

  /// Null disables it — which is how a sentence with no voice is shown.
  final VoidCallback? onPressed;

  final Color tint;
  final bool playing;

  @override
  Widget build(BuildContext context) {
    final bool enabled = onPressed != null;
    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      child: ExcludeSemantics(
        child: Material(
          color: enabled
              ? tint.withValues(alpha: 0.18)
              : AppColors.liveBorder.withValues(alpha: 0.4),
          shape: const CircleBorder(),
          child: InkWell(
            onTap: onPressed,
            customBorder: const CircleBorder(),
            child: SizedBox(
              width: 46,
              height: 46,
              child: Icon(
                playing ? Icons.pause : Icons.volume_up,
                size: 22,
                color: enabled ? tint : AppColors.liveTextMuted,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The dotted progress indicator on the AI card.
class ProcessingDots extends StatelessWidget {
  const ProcessingDots({required this.stage, super.key});

  /// 0..4, one per pipeline stage reached. Not an animation: it advances only
  /// when the pipeline actually advances.
  final int stage;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        for (int i = 0; i < 5; i++)
          Padding(
            padding: const EdgeInsets.only(right: 5),
            child: Container(
              width: i <= stage ? 7 : 5,
              height: i <= stage ? 7 : 5,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: i <= stage
                    ? (i >= 4 ? AppColors.liveGlowViolet : AppColors.liveAi)
                    : AppColors.liveBorder,
              ),
            ),
          ),
      ],
    );
  }
}

/// A bottom-bar control.
class LiveControlButton extends StatelessWidget {
  const LiveControlButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.tint,
    this.background,
    this.active = false,
    this.semanticLabel,
    super.key,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final Color? tint;
  final Color? background;
  final bool active;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final Color foreground = tint ?? AppColors.liveTextPrimary;

    return Semantics(
      button: true,
      enabled: onPressed != null,
      selected: active,
      label: semanticLabel ?? label,
      child: ExcludeSemantics(
        child: Material(
          color: background ??
              (active
                  ? AppColors.liveGlowBlue.withValues(alpha: 0.24)
                  : AppColors.liveCardRaised),
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            onTap: onPressed,
            borderRadius: BorderRadius.circular(14),
            child: Container(
              height: 58,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              alignment: Alignment.center,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  Icon(
                    icon,
                    size: 21,
                    color: onPressed == null
                        ? AppColors.liveTextMuted
                        : foreground,
                  ),
                  const SizedBox(width: 9),
                  Flexible(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        label,
                        maxLines: 1,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: onPressed == null
                              ? AppColors.liveTextMuted
                              : foreground,
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
