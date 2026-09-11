import '../../../models/worksheet.dart';

/// A point in a shape's own 0..1 box.
typedef ShapePoint = ({double x, double y});

/// One drawing instruction, in a unit box.
///
/// Deliberately primitive. The worksheet is drawn twice — once on screen with
/// Flutter's canvas and once into the PDF with the PDF library's — and these
/// ops are the single description both follow, so the printed sheet cannot
/// drift away from the one the teacher approved.
sealed class ShapeOp {
  const ShapeOp();
}

final class CircleOp extends ShapeOp {
  const CircleOp(this.centre, this.radius, {this.filled = false});

  final ShapePoint centre;
  final double radius;
  final bool filled;
}

final class PolygonOp extends ShapeOp {
  const PolygonOp(this.points, {this.filled = false});

  final List<ShapePoint> points;
  final bool filled;
}

final class LineOp extends ShapeOp {
  const LineOp(this.from, this.to);

  final ShapePoint from;
  final ShapePoint to;
}

/// The countable objects a worksheet draws.
///
/// Outlines rather than photographs or emoji, for three reasons: they print
/// legibly on a school's black-and-white printer, they need no image asset or
/// emoji font, and the same instructions produce the same shape on screen and
/// on paper.
abstract final class WorksheetShapes {
  static List<ShapeOp> forExample(VisualExample example) =>
      switch (example) {
        VisualExample.apples => _apple,
        VisualExample.trees => _tree,
        VisualExample.animals => _animal,
        VisualExample.householdObjects => _pot,
      };

  static const List<ShapeOp> _apple = <ShapeOp>[
    CircleOp((x: 0.5, y: 0.58), 0.34),
    LineOp((x: 0.5, y: 0.24), (x: 0.5, y: 0.08)),
    PolygonOp(<ShapePoint>[
      (x: 0.52, y: 0.14),
      (x: 0.74, y: 0.04),
      (x: 0.66, y: 0.20),
    ]),
  ];

  static const List<ShapeOp> _tree = <ShapeOp>[
    PolygonOp(<ShapePoint>[
      (x: 0.5, y: 0.06),
      (x: 0.86, y: 0.62),
      (x: 0.14, y: 0.62),
    ]),
    PolygonOp(<ShapePoint>[
      (x: 0.42, y: 0.62),
      (x: 0.58, y: 0.62),
      (x: 0.58, y: 0.94),
      (x: 0.42, y: 0.94),
    ]),
  ];

  static const List<ShapeOp> _animal = <ShapeOp>[
    // Body, head and two legs: enough to read as an animal at 20 pixels,
    // without pretending to be a particular one.
    PolygonOp(<ShapePoint>[
      (x: 0.10, y: 0.36),
      (x: 0.72, y: 0.36),
      (x: 0.72, y: 0.70),
      (x: 0.10, y: 0.70),
    ]),
    CircleOp((x: 0.82, y: 0.34), 0.16),
    LineOp((x: 0.22, y: 0.70), (x: 0.22, y: 0.94)),
    LineOp((x: 0.60, y: 0.70), (x: 0.60, y: 0.94)),
  ];

  static const List<ShapeOp> _pot = <ShapeOp>[
    PolygonOp(<ShapePoint>[
      (x: 0.22, y: 0.20),
      (x: 0.78, y: 0.20),
      (x: 0.88, y: 0.92),
      (x: 0.12, y: 0.92),
    ]),
    LineOp((x: 0.16, y: 0.20), (x: 0.84, y: 0.20)),
  ];
}
