import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';

/// The cream ground with the faint tribal geometry that runs down the upper
/// corners of every onboarding page.
///
/// Painted rather than shipped as an image: the motif is pure geometry, so a
/// painter stays crisp at any density and costs nothing to bundle.
class TribalBackdrop extends StatelessWidget {
  const TribalBackdrop({super.key});

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[
            AppColors.brandCream,
            AppColors.brandCream,
            AppColors.brandCreamWarm,
          ],
          stops: <double>[0.0, 0.35, 1.0],
        ),
      ),
      child: CustomPaint(
        painter: _TribalPatternPainter(),
        size: Size.infinite,
      ),
    );
  }
}

class _TribalPatternPainter extends CustomPainter {
  const _TribalPatternPainter();

  /// Deliberately barely-there: the motif is texture behind the brand, not a
  /// decoration competing with it.
  static const double _opacity = 0.20;

  @override
  void paint(Canvas canvas, Size size) {
    final double band = math.min(size.width * 0.13, 62);
    final double depth = size.height * 0.30;

    final Paint stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.1
      ..color = AppColors.brandGold.withValues(alpha: _opacity);

    for (final bool mirrored in <bool>[false, true]) {
      canvas.save();
      if (mirrored) {
        canvas.translate(size.width, 0);
        canvas.scale(-1, 1);
      }
      _paintBand(canvas, stroke, band, depth);
      canvas.restore();
    }
  }

  void _paintBand(Canvas canvas, Paint stroke, double band, double depth) {
    const double cell = 26;
    final int rows = (depth / cell).ceil();
    final int cols = math.max(1, (band / cell).floor());

    for (int row = 0; row < rows; row++) {
      // Fade the motif out as it travels down the page.
      final double fade = 1 - (row / rows);
      final Paint p = Paint()
        ..style = stroke.style
        ..strokeWidth = stroke.strokeWidth
        ..color = stroke.color.withValues(alpha: _opacity * fade);

      for (int col = 0; col < cols; col++) {
        final Offset centre =
            Offset(col * cell + cell / 2, row * cell + cell / 2);
        _diamond(canvas, p, centre, cell * 0.34);
        _diamond(canvas, p, centre, cell * 0.16);
        if ((row + col).isEven) {
          canvas.drawLine(
            centre.translate(-cell * 0.42, 0),
            centre.translate(cell * 0.42, 0),
            p,
          );
        }
      }
    }
  }

  void _diamond(Canvas canvas, Paint paint, Offset centre, double r) {
    final Path path = Path()
      ..moveTo(centre.dx, centre.dy - r)
      ..lineTo(centre.dx + r, centre.dy)
      ..lineTo(centre.dx, centre.dy + r)
      ..lineTo(centre.dx - r, centre.dy)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _TribalPatternPainter oldDelegate) => false;
}
