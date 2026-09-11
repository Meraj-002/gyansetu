import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../models/flashcard.dart';
import '../../../models/worksheet.dart';
import '../../worksheet/services/worksheet_shapes.dart';

/// The picture on a flashcard.
///
/// A bundled asset, never a URL: the whole feature has to work with the radio
/// off. A card with no picture — a numeral — draws its digit and that many
/// counters instead, using the same shapes the printable worksheet uses.
class FlashcardVisual extends StatelessWidget {
  const FlashcardVisual({required this.card, super.key});

  final Flashcard card;

  @override
  Widget build(BuildContext context) {
    if (card.isDrawn) return _NumeralVisual(card: card);

    final String? asset = card.imageAsset;
    if (asset == null) return const _MissingVisual();

    return Image.asset(
      asset,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.medium,
      excludeFromSemantics: true,
      errorBuilder: (BuildContext context, Object error, StackTrace? stack) {
        // A missing asset is a build mistake, not something a teacher should
        // see as a broken image in front of a class.
        if (kDebugMode) {
          debugPrint('flashcard asset missing: $asset');
        }
        return const _MissingVisual();
      },
    );
  }
}

class _NumeralVisual extends StatelessWidget {
  const _NumeralVisual({required this.card});

  final Flashcard card;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double side = math.min(constraints.maxWidth, constraints.maxHeight);

        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              '${card.numeral}',
              style: TextStyle(
                fontSize: side * 0.42,
                height: 1,
                fontWeight: FontWeight.w800,
                color: AppColors.authNavy,
              ),
            ),
            SizedBox(height: side * 0.06),
            SizedBox(
              width: side * 0.78,
              child: Wrap(
                alignment: WrapAlignment.center,
                spacing: side * 0.045,
                runSpacing: side * 0.04,
                children: <Widget>[
                  for (int i = 0; i < card.counters; i++)
                    SizedBox(
                      width: side * 0.11,
                      height: side * 0.11,
                      child: CustomPaint(
                        painter: _CounterPainter(
                          WorksheetShapes.forExample(VisualExample.apples),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _CounterPainter extends CustomPainter {
  _CounterPainter(this.ops);

  final List<ShapeOp> ops;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeJoin = StrokeJoin.round
      ..color = AppColors.secondaryDark;

    double fx(double x) => x * size.width;
    double fy(double y) => y * size.height;

    for (final ShapeOp op in ops) {
      switch (op) {
        case CircleOp(:final ShapePoint centre, :final double radius):
          canvas.drawOval(
            Rect.fromCenter(
              center: Offset(fx(centre.x), fy(centre.y)),
              width: radius * 2 * size.width,
              height: radius * 2 * size.height,
            ),
            paint,
          );
        case PolygonOp(:final List<ShapePoint> points):
          final Path path = Path()
            ..moveTo(fx(points.first.x), fy(points.first.y));
          for (final ShapePoint point in points.skip(1)) {
            path.lineTo(fx(point.x), fy(point.y));
          }
          canvas.drawPath(path..close(), paint);
        case LineOp(:final ShapePoint from, :final ShapePoint to):
          canvas.drawLine(
            Offset(fx(from.x), fy(from.y)),
            Offset(fx(to.x), fy(to.y)),
            paint,
          );
      }
    }
  }

  @override
  bool shouldRepaint(_CounterPainter old) => old.ops != ops;
}

/// Shown in place of a picture that is not on the device.
class _MissingVisual extends StatelessWidget {
  const _MissingVisual();

  @override
  Widget build(BuildContext context) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(
              Icons.image_not_supported_outlined,
              size: 40,
              color: AppColors.brandMuted,
            ),
            const SizedBox(height: 8),
            Text(
              'No picture for this card',
              style: TextStyle(
                fontSize: 12.5,
                color: AppColors.brandNavy.withValues(alpha: 0.6),
              ),
            ),
          ],
        ),
      );
}

/// The small tinted label above a word.
class LanguageTag extends StatelessWidget {
  const LanguageTag({required this.label, required this.tint, super.key});

  final String label;
  final Color tint;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: tint.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(7),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            color: tint,
          ),
        ),
      );
}

/// Turns a card over.
///
/// A real rotation about the vertical axis, cut off at a quarter turn so the
/// back is never seen mirrored. Kept to 320ms: long enough to read as a flip,
/// short enough not to slow a teacher down.
class FlipCard extends StatefulWidget {
  const FlipCard({
    required this.flipped,
    required this.front,
    required this.back,
    this.onTap,
    super.key,
  });

  final bool flipped;
  final Widget front;
  final Widget back;
  final VoidCallback? onTap;

  @override
  State<FlipCard> createState() => _FlipCardState();
}

class _FlipCardState extends State<FlipCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 320),
    value: widget.flipped ? 1 : 0,
  );

  @override
  void didUpdateWidget(FlipCard old) {
    super.didUpdateWidget(old);
    if (widget.flipped == old.flipped) return;
    if (widget.flipped) {
      _controller.forward();
    } else {
      _controller.reverse();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (BuildContext context, _) {
          final double turn = _controller.value * math.pi;
          final bool showingBack = _controller.value > 0.5;

          return Transform(
            alignment: Alignment.center,
            transform: Matrix4.identity()
              // A little perspective, so it reads as a card turning rather
              // than a picture being squashed.
              ..setEntry(3, 2, 0.0012)
              ..rotateY(turn),
            child: showingBack
                ? Transform(
                    alignment: Alignment.center,
                    transform: Matrix4.identity()..rotateY(math.pi),
                    child: widget.back,
                  )
                : widget.front,
          );
        },
      ),
    );
  }
}

/// A category chip along the top.
class CategoryChip extends StatelessWidget {
  const CategoryChip({
    required this.category,
    required this.selected,
    required this.enabled,
    required this.onTap,
    super.key,
  });

  final FlashcardCategory category;
  final bool selected;

  /// False when the category holds no cards. It stays visible and tappable so
  /// the teacher can see its empty state, but is drawn as the quiet one.
  final bool enabled;

  final VoidCallback onTap;

  ({IconData icon, Color tint}) get _style => switch (category) {
        FlashcardCategory.numbers => (
            icon: Icons.pin_outlined,
            tint: AppColors.liveGlowViolet,
          ),
        FlashcardCategory.animals => (
            icon: Icons.pets,
            tint: AppColors.setupLiteracy,
          ),
        FlashcardCategory.nature => (
            icon: Icons.eco_outlined,
            tint: AppColors.setupLiteracy,
          ),
        FlashcardCategory.objects => (
            icon: Icons.category_outlined,
            tint: AppColors.setupNumeracy,
          ),
        FlashcardCategory.actions => (
            icon: Icons.directions_run,
            tint: AppColors.brandOrange,
          ),
        FlashcardCategory.programming => (
            icon: Icons.code,
            tint: AppColors.setupNumeracy,
          ),
      };

  @override
  Widget build(BuildContext context) {
    final ({IconData icon, Color tint}) style = _style;

    return Semantics(
      button: true,
      selected: selected,
      label: enabled
          ? category.label
          : '${category.label}, no cards yet',
      child: ExcludeSemantics(
        child: Material(
          color: selected ? style.tint.withValues(alpha: 0.10) : Colors.white,
          borderRadius: BorderRadius.circular(13),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(13),
            child: Container(
              height: 52,
              padding: const EdgeInsets.symmetric(horizontal: 15),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(13),
                border: Border.all(
                  color: selected
                      ? style.tint.withValues(alpha: 0.7)
                      : AppColors.authFieldBorder,
                  width: selected ? 1.6 : 1,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Icon(
                    style.icon,
                    size: 20,
                    color: enabled
                        ? style.tint
                        : style.tint.withValues(alpha: 0.4),
                  ),
                  const SizedBox(width: 9),
                  Text(
                    category.label,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: enabled
                          ? style.tint
                          : AppColors.brandNavy.withValues(alpha: 0.4),
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

/// A round arrow beside the card.
class DeckArrow extends StatelessWidget {
  const DeckArrow({
    required this.icon,
    required this.label,
    required this.onPressed,
    super.key,
  });

  final IconData icon;
  final String label;

  /// Null disables it — which is how the ends of the deck are shown, rather
  /// than by letting a tap do nothing.
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final bool enabled = onPressed != null;

    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      child: ExcludeSemantics(
        child: Material(
          color: Colors.white,
          shape: CircleBorder(
            side: BorderSide(
              color: enabled
                  ? AppColors.authFieldBorder
                  : AppColors.outlineVariant,
            ),
          ),
          elevation: enabled ? 1.5 : 0,
          shadowColor: AppColors.brandNavy.withValues(alpha: 0.2),
          child: InkWell(
            onTap: onPressed,
            customBorder: const CircleBorder(),
            child: SizedBox(
              width: 48,
              height: 48,
              child: Icon(
                icon,
                size: 22,
                color: enabled
                    ? AppColors.brandNavy
                    : AppColors.brandMuted.withValues(alpha: 0.5),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// One of the three controls under the card.
class DeckControl extends StatelessWidget {
  const DeckControl({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.iconOnRight = false,
    super.key,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final bool iconOnRight;

  @override
  Widget build(BuildContext context) {
    final bool enabled = onPressed != null;
    final Color tint =
        enabled ? AppColors.brandNavy : AppColors.brandMuted.withValues(alpha: 0.6);

    final Widget glyph = Icon(icon, size: 19, color: tint);
    final Widget text = Flexible(
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          label,
          maxLines: 1,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: tint,
          ),
        ),
      ),
    );

    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      child: ExcludeSemantics(
        child: Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(13),
          child: InkWell(
            onTap: onPressed,
            borderRadius: BorderRadius.circular(13),
            child: Container(
              height: 52,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(13),
                border: Border.all(color: AppColors.authFieldBorder),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  if (!iconOnRight) ...<Widget>[glyph, const SizedBox(width: 9)],
                  text,
                  if (iconOnRight) ...<Widget>[const SizedBox(width: 9), glyph],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The row of claims under the deck.
class FeatureRow extends StatelessWidget {
  const FeatureRow({required this.languagePair, required this.bilingual, super.key});

  final String languagePair;

  /// False when the card on screen has no mother-tongue word, so the row does
  /// not claim bilingual learning that is not there.
  final bool bilingual;

  @override
  Widget build(BuildContext context) {
    final List<({IconData icon, String title, String subtitle})> items =
        <({IconData icon, String title, String subtitle})>[
      (
        icon: Icons.translate,
        title: bilingual ? 'Bilingual Learning' : 'One language so far',
        subtitle: bilingual ? languagePair : 'Mother tongue coming',
      ),
      (
        icon: Icons.volume_up_outlined,
        title: 'Audio Support',
        subtitle: 'Device voice',
      ),
      (
        icon: Icons.cloud_off,
        title: 'Offline Ready',
        subtitle: 'Works everywhere',
      ),
      (
        icon: Icons.groups_outlined,
        title: 'Culturally Relevant',
        subtitle: 'Local • Familiar',
      ),
    ];

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.authFieldBorder),
      ),
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          // Two by two on a phone: four of these across 360dp leaves each one
          // too narrow to read.
          final int columns = constraints.maxWidth >= 600 ? 4 : 2;
          final double width =
              (constraints.maxWidth - 12) / columns;

          return Wrap(
            children: <Widget>[
              for (final ({IconData icon, String title, String subtitle}) item
                  in items)
                SizedBox(
                  width: width,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 6,
                    ),
                    child: Row(
                      children: <Widget>[
                        Icon(
                          item.icon,
                          size: 20,
                          color: AppColors.setupNumeracy,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  item.title,
                                  maxLines: 1,
                                  style: const TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.brandNavy,
                                  ),
                                ),
                              ),
                              FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  item.subtitle,
                                  maxLines: 1,
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: AppColors.brandNavy
                                        .withValues(alpha: 0.6),
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
            ],
          );
        },
      ),
    );
  }
}
