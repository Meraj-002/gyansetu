import 'package:flutter/material.dart';

/// Feathers a photograph's edges to nothing so it dissolves into the cream
/// ground instead of ending on a hard rectangular seam.
///
/// The crops come out of a flat presentation image, so every edge is a straight
/// cut. Masking is what makes them read as part of the page.
class PhotoFade extends StatelessWidget {
  const PhotoFade({
    required this.child,
    this.top = 0,
    this.bottom = 0,
    this.right = 0,
    this.left = 0,
    super.key,
  });

  final Widget child;

  /// Fade depth on each edge, as a fraction of the box. Zero leaves it sharp.
  final double top;
  final double bottom;
  final double right;
  final double left;

  bool get _hasVertical => top > 0 || bottom > 0;
  bool get _hasHorizontal => left > 0 || right > 0;

  @override
  Widget build(BuildContext context) {
    Widget result = child;

    if (_hasVertical) {
      result = ShaderMask(
        blendMode: BlendMode.dstIn,
        shaderCallback: (Rect bounds) => LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: const <Color>[
            Colors.transparent,
            Colors.white,
            Colors.white,
            Colors.transparent,
          ],
          stops: <double>[0, top, 1 - bottom, 1],
        ).createShader(bounds),
        child: result,
      );
    }

    if (_hasHorizontal) {
      result = ShaderMask(
        blendMode: BlendMode.dstIn,
        shaderCallback: (Rect bounds) => LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: const <Color>[
            Colors.transparent,
            Colors.white,
            Colors.white,
            Colors.transparent,
          ],
          stops: <double>[0, left, 1 - right, 1],
        ).createShader(bounds),
        child: result,
      );
    }

    return result;
  }
}
