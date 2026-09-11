import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';

/// The deep navy panel that closes every onboarding page, with the gold wave
/// along its top edge.
///
/// The curve is a path rather than an image so it stretches to any width
/// without the seam an asset would show at unusual aspect ratios.
class WavePanel extends StatelessWidget {
  const WavePanel({required this.child, super.key});

  /// Content laid out below the wave: indicators and the call to action.
  final Widget child;

  /// Height of the curved band above the flat part of the panel.
  static const double waveHeight = 40;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: const _WavePainter(),
      child: Padding(
        padding: const EdgeInsets.only(top: waveHeight),
        child: child,
      ),
    );
  }
}

class _WavePainter extends CustomPainter {
  const _WavePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final double w = size.width;
    final double h = size.height;
    final double wave = WavePanel.waveHeight;

    // Traced from the key art: high at the left shoulder, a trough just past
    // a third of the way across, then rising to the right edge.
    final Path edge = Path()
      ..moveTo(0, wave * 0.10)
      ..cubicTo(w * 0.12, wave * 0.60, w * 0.26, wave, w * 0.40, wave)
      ..cubicTo(w * 0.62, wave, w * 0.80, wave * 0.20, w, 0);

    final Path fill = Path.from(edge)
      ..lineTo(w, h)
      ..lineTo(0, h)
      ..close();

    canvas.drawPath(
      fill,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[AppColors.brandNavyPanel, AppColors.brandNavyDeep],
        ).createShader(Offset.zero & size),
    );

    // Gold band riding the edge.
    canvas.drawPath(
      edge,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 7
        ..strokeCap = StrokeCap.round
        ..shader = const LinearGradient(
          colors: <Color>[
            AppColors.brandGold,
            AppColors.brandOrangeBright,
            AppColors.brandGold,
          ],
        ).createShader(Offset.zero & size),
    );

    // A hairline of cream above the gold, as in the artwork.
    canvas.save();
    canvas.translate(0, -7);
    canvas.drawPath(
      edge,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = AppColors.brandCream.withValues(alpha: 0.85),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _WavePainter oldDelegate) => false;
}
