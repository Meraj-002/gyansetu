import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../models/question.dart';
import '../../../models/worksheet.dart';
import '../services/worksheet_shapes.dart';

/// The countable objects, drawn from the shared shape instructions.
///
/// The PDF draws the same instructions with the same geometry, so the printed
/// sheet is the one the teacher approved rather than a second design that has
/// to be kept in step by hand.
class WorksheetObjects extends StatelessWidget {
  const WorksheetObjects({
    required this.example,
    required this.count,
    this.size = 26,
    super.key,
  });

  final VisualExample example;
  final int count;
  final double size;

  @override
  Widget build(BuildContext context) {
    if (count <= 0) return const SizedBox.shrink();

    return Semantics(
      label: '$count ${example.label}',
      child: ExcludeSemantics(
        child: Wrap(
          spacing: 8,
          runSpacing: 7,
          children: <Widget>[
            for (int i = 0; i < count; i++)
              SizedBox(
                width: size,
                height: size,
                child: CustomPaint(
                  painter: _ShapePainter(WorksheetShapes.forExample(example)),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ShapePainter extends CustomPainter {
  _ShapePainter(this.ops);

  final List<ShapeOp> ops;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
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
  bool shouldRepaint(_ShapePainter old) => old.ops != ops;
}

/// A blank box for the child's answer.
class AnswerBox extends StatelessWidget {
  const AnswerBox({this.width = 62, this.height = 34, super.key});

  final double width;
  final double height;

  @override
  Widget build(BuildContext context) => Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(7),
          border: Border.all(color: AppColors.outline),
        ),
      );
}

/// A ruled field, as in "Name: ______".
class PaperField extends StatelessWidget {
  const PaperField({required this.label, super.key});

  final String label;

  @override
  Widget build(BuildContext context) => Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: <Widget>[
          Text(
            label,
            style: const TextStyle(
              fontSize: 12.5,
              color: AppColors.brandNavy,
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Container(
              height: 1,
              margin: const EdgeInsets.only(bottom: 3),
              color: AppColors.outline,
            ),
          ),
        ],
      );
}

/// The masthead across the top of the worksheet paper.
class PaperHeader extends StatelessWidget {
  const PaperHeader({required this.worksheet, super.key});

  final Worksheet worksheet;

  /// The lesson name without the "— Worksheet" the title carries.
  String get _topic => worksheet.title
      .replaceAll(RegExp(r'\s*—\s*Worksheet\s*$'), '')
      .trim();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final Widget brand = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Semantics(
              label: 'GyanSetu AI',
              child: const ExcludeSemantics(
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
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.3,
                    ),
                  ),
                ),
              ),
            ),
            Text(
              'Bridging Languages. Building Futures.',
              style: TextStyle(
                fontSize: 8.5,
                color: AppColors.brandNavy.withValues(alpha: 0.65),
              ),
            ),
          ],
        );

        final Widget subject = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                // Class and subject from the worksheet's own metadata.
                'Class ${worksheet.classNumber}   •   '
                '${worksheet.subject.label}',
                maxLines: 1,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppColors.brandNavy,
                ),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              'Topic: $_topic',
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: AppColors.brandNavy,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              'Language: ${worksheet.languagePair}',
              style: TextStyle(
                fontSize: 11.5,
                color: AppColors.brandNavy.withValues(alpha: 0.65),
              ),
            ),
          ],
        );

        const Widget fields = Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            PaperField(label: 'Name:'),
            SizedBox(height: 12),
            PaperField(label: 'Date:'),
          ],
        );

        // Stacked on a narrow phone: three columns across 300dp would squeeze
        // the topic into one word a line.
        if (constraints.maxWidth < 460) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              brand,
              const SizedBox(height: 10),
              subject,
              const SizedBox(height: 12),
              fields,
            ],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(flex: 4, child: brand),
            const SizedBox(width: 10),
            Expanded(flex: 5, child: subject),
            const SizedBox(width: 10),
            const Expanded(flex: 4, child: fields),
          ],
        );
      },
    );
  }
}

/// One question, laid out for its type.
class PaperQuestion extends StatelessWidget {
  const PaperQuestion({
    required this.question,
    required this.targetLanguageLabel,
    this.showAnswer = false,
    super.key,
  });

  final WorksheetQuestion question;

  /// Named so a missing translation can say which language is missing.
  final String targetLanguageLabel;

  /// The teacher's view may show the answer; the printed sheet does not.
  final bool showAnswer;

  @override
  Widget build(BuildContext context) {
    final VisualExample? example = VisualExample.byName(question.visualAsset);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(13, 12, 13, 13),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: AppColors.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              SizedBox(
                width: 22,
                child: Text(
                  '${question.order}.',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: AppColors.brandNavy,
                  ),
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      question.questionText,
                      style: const TextStyle(
                        fontSize: 15.5,
                        height: 1.35,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    if (question.isBilingual) ...<Widget>[
                      const SizedBox(height: 3),
                      Text(
                        question.translatedQuestionText!,
                        style: const TextStyle(
                          fontSize: 14.5,
                          height: 1.35,
                          color: AppColors.setupLiteracy,
                        ),
                      ),
                    ] else ...<Widget>[
                      const SizedBox(height: 3),
                      Text(
                        'No $targetLanguageLabel text for this question yet.',
                        style: TextStyle(
                          fontSize: 11.5,
                          color:
                              AppColors.brandNavy.withValues(alpha: 0.55),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.only(left: 22),
            child: _body(example),
          ),
          if (showAnswer) ...<Widget>[
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.only(left: 22),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const Icon(
                    Icons.check_circle_outline,
                    size: 15,
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
                        fontSize: 12,
                        height: 1.35,
                        color:
                            AppColors.setupLiteracy.withValues(alpha: 0.95),
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

  Widget _body(VisualExample? example) {
    switch (question.type) {
      case QuestionType.countingObjects:
        return Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: <Widget>[
            Expanded(child: _objects(example)),
            const SizedBox(width: 10),
            const AnswerBox(),
          ],
        );

      case QuestionType.matchNumbers:
        return Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: <Widget>[
            Container(
              width: 46,
              height: 34,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(7),
                border: Border.all(color: AppColors.outline),
              ),
              child: Text(
                question.correctAnswer,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
            const SizedBox(width: 8),
            const _Dot(),
            Expanded(
              child: Container(
                height: 1,
                margin: const EdgeInsets.symmetric(horizontal: 8),
                color: AppColors.outlineVariant,
              ),
            ),
            const _Dot(),
            const SizedBox(width: 8),
            Expanded(flex: 3, child: _objects(example)),
          ],
        );

      case QuestionType.fillInTheBlanks:
        return Text(
          // The sequence is in the question itself; this only says what to do.
          'Write the missing number in the blank above.',
          style: TextStyle(
            fontSize: 12.5,
            color: AppColors.brandNavy.withValues(alpha: 0.6),
          ),
        );

      case QuestionType.visualIdentification:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            _objects(example),
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              runSpacing: 8,
              children: <Widget>[
                for (final String option in question.options)
                  Container(
                    width: 50,
                    height: 32,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(7),
                      border: Border.all(color: AppColors.outline),
                    ),
                    child: Text(
                      option,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
              ],
            ),
          ],
        );
    }
  }

  /// The objects, or an honest note when the question names one this build
  /// cannot draw.
  Widget _objects(VisualExample? example) {
    if (example == null || question.visualCount <= 0) {
      return Text(
        'No picture for this question.',
        style: TextStyle(
          fontSize: 12,
          color: AppColors.brandNavy.withValues(alpha: 0.5),
        ),
      );
    }
    return WorksheetObjects(example: example, count: question.visualCount);
  }
}

class _Dot extends StatelessWidget {
  const _Dot();

  @override
  Widget build(BuildContext context) => Container(
        width: 6,
        height: 6,
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          color: AppColors.brandMuted,
        ),
      );
}

/// The band across the bottom of the paper.
class PaperFooter extends StatelessWidget {
  const PaperFooter({required this.bilingual, super.key});

  final bool bilingual;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(13, 12, 13, 12),
      decoration: BoxDecoration(
        color: AppColors.authChip,
        borderRadius: BorderRadius.circular(11),
      ),
      child: Row(
        children: <Widget>[
          const Icon(
            Icons.verified_user_outlined,
            size: 22,
            color: AppColors.setupNumeracy,
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Curriculum aligned  •  '
                    '${bilingual ? 'Bilingual  •  ' : ''}Offline ready',
                    maxLines: 1,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.setupNumeracy,
                    ),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Designed for every child. In every language.',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: AppColors.brandNavy.withValues(alpha: 0.62),
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
