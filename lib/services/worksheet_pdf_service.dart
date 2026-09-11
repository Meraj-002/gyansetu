import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../core/utils/app_logger.dart';
import '../features/worksheet/services/worksheet_shapes.dart';
import '../models/question.dart';
import '../models/worksheet.dart';

/// A built PDF, and what it turned out to contain.
class WorksheetPdf {
  const WorksheetPdf({
    required this.bytes,
    required this.pageCount,
    required this.fileName,
  });

  final Uint8List bytes;
  final int pageCount;
  final String fileName;

  bool get isEmpty => bytes.isEmpty;
}

/// Turns a [Worksheet] into a printable A4 PDF.
///
/// A real structured document, not a screenshot of the Flutter view: text is
/// text, the shapes are vectors, and it prints crisply at any size.
abstract interface class WorksheetPdfService {
  /// How many pages [worksheet] will occupy. Known before the PDF is built,
  /// because pagination is fixed rather than left to the layout engine — which
  /// is what lets the preview show an honest page count.
  int pageCountFor(Worksheet worksheet, {bool includeAnswerKey = true});

  /// A safe, meaningful file name, e.g. `GyanSetu_Counting_1-10_Class_1.pdf`.
  String fileNameFor(Worksheet worksheet);

  Future<WorksheetPdf> build(
    Worksheet worksheet, {
    bool includeAnswerKey = true,
  });
}

/// The real implementation, over the `pdf` package.
class PdfWorksheetService implements WorksheetPdfService {
  PdfWorksheetService();

  /// Questions per page, fixed so the page count is knowable up front and the
  /// same for the indicator, the PDF and the tests.
  static const int questionsPerPage = 5;

  static const PdfColor _navy = PdfColor.fromInt(0xFF14224B);
  static const PdfColor _ink = PdfColor.fromInt(0xFF1A1D26);
  static const PdfColor _muted = PdfColor.fromInt(0xFF5A6072);
  static const PdfColor _rule = PdfColor.fromInt(0xFFD9DEE8);
  static const PdfColor _green = PdfColor.fromInt(0xFF2E7D5B);
  static const PdfColor _gold = PdfColor.fromInt(0xFFC07E12);

  pw.Font? _regular;
  pw.Font? _bold;

  /// Loads the bundled Devanagari faces once.
  ///
  /// The PDF library's built-in fonts have no Devanagari, so without these the
  /// Hindi questions would print as empty boxes. They are bundled assets and
  /// are never fetched at runtime, so a worksheet still builds with no
  /// connection.
  Future<void> _loadFonts() async {
    if (_regular != null && _bold != null) return;
    _regular = pw.Font.ttf(
      await rootBundle.load('assets/fonts/NotoSansDevanagari-Regular.ttf'),
    );
    _bold = pw.Font.ttf(
      await rootBundle.load('assets/fonts/NotoSansDevanagari-Bold.ttf'),
    );
  }

  @override
  int pageCountFor(Worksheet worksheet, {bool includeAnswerKey = true}) {
    final int questionPages = worksheet.questions.isEmpty
        ? 1
        : (worksheet.questions.length + questionsPerPage - 1) ~/
            questionsPerPage;
    final bool answerKey = includeAnswerKey && worksheet.questions.isNotEmpty;
    return questionPages + (answerKey ? 1 : 0);
  }

  @override
  String fileNameFor(Worksheet worksheet) {
    final String topic = _sanitise(
      worksheet.title.replaceAll(RegExp(r'\s*—\s*Worksheet\s*$'), ''),
    );
    final String name =
        'GyanSetu_${topic}_Class_${worksheet.classNumber}';
    return '${name.isEmpty ? 'GyanSetu_Worksheet' : name}.pdf';
  }

  /// Keeps a file name to characters every platform accepts.
  ///
  /// The en dash in a title like "Counting 1–10" becomes a plain hyphen first:
  /// dropping it would name the file after "110", which is a different lesson.
  static String _sanitise(String value) => value
      .replaceAll(RegExp('[‐-―]'), '-')
      .replaceAll(RegExp(r'[^A-Za-z0-9ऀ-ॿ\- ]'), '')
      .trim()
      .replaceAll(RegExp(r'\s+'), '_');

  @override
  Future<WorksheetPdf> build(
    Worksheet worksheet, {
    bool includeAnswerKey = true,
  }) async {
    await _loadFonts();

    final pw.ThemeData theme = pw.ThemeData.withFont(
      base: _regular!,
      bold: _bold!,
    );
    final pw.Document document = pw.Document(
      title: worksheet.title,
      author: 'GyanSetu AI',
      creator: 'GyanSetu AI',
      subject: worksheet.learningOutcome,
    );

    final int totalPages =
        pageCountFor(worksheet, includeAnswerKey: includeAnswerKey);
    final bool answerKey =
        includeAnswerKey && worksheet.questions.isNotEmpty;
    int pageNumber = 0;

    for (int start = 0;
        start < worksheet.questions.length || start == 0;
        start += questionsPerPage) {
      final List<WorksheetQuestion> chunk = worksheet.questions
          .skip(start)
          .take(questionsPerPage)
          .toList(growable: false);
      pageNumber++;
      final int number = pageNumber;

      document.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          theme: theme,
          margin: const pw.EdgeInsets.fromLTRB(28, 26, 28, 22),
          build: (pw.Context context) => pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: <pw.Widget>[
              if (number == 1)
                _header(worksheet)
              else
                _continuationHeader(worksheet),
              pw.SizedBox(height: 12),
              pw.Expanded(
                child: chunk.isEmpty
                    ? pw.Text(
                        'This worksheet has no questions.',
                        style: pw.TextStyle(color: _muted, fontSize: 11),
                      )
                    : pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: <pw.Widget>[
                          for (final WorksheetQuestion question in chunk)
                            _question(worksheet, question),
                        ],
                      ),
              ),
              _footer(worksheet, number, totalPages),
            ],
          ),
        ),
      );

      if (start + questionsPerPage >= worksheet.questions.length) break;
    }

    if (answerKey) {
      pageNumber++;
      final int number = pageNumber;
      document.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          theme: theme,
          margin: const pw.EdgeInsets.fromLTRB(28, 26, 28, 22),
          build: (pw.Context context) => pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: <pw.Widget>[
              _continuationHeader(worksheet),
              pw.SizedBox(height: 12),
              pw.Text(
                'Answer Key — for the teacher',
                style: pw.TextStyle(
                  fontSize: 15,
                  fontWeight: pw.FontWeight.bold,
                  color: _navy,
                ),
              ),
              pw.SizedBox(height: 8),
              pw.Expanded(child: _answerKey(worksheet)),
              _footer(worksheet, number, totalPages),
            ],
          ),
        ),
      );
    }

    final Uint8List bytes = Uint8List.fromList(await document.save());
    if (bytes.isEmpty) {
      // A zero-byte document is never shown or saved: the caller reports a
      // failure instead of handing the teacher an empty file.
      AppLogger.error('worksheet pdf came out empty');
    }
    return WorksheetPdf(
      bytes: bytes,
      pageCount: totalPages,
      fileName: fileNameFor(worksheet),
    );
  }

  // --- Page furniture ------------------------------------------------------

  pw.Widget _header(Worksheet worksheet) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: <pw.Widget>[
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: <pw.Widget>[
            pw.Expanded(
              flex: 4,
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: <pw.Widget>[
                  pw.Text(
                    'GyanSetu AI',
                    style: pw.TextStyle(
                      fontSize: 17,
                      fontWeight: pw.FontWeight.bold,
                      color: _navy,
                    ),
                  ),
                  pw.Text(
                    'Bridging Languages. Building Futures.',
                    style: pw.TextStyle(fontSize: 7.5, color: _muted),
                  ),
                ],
              ),
            ),
            pw.Expanded(
              flex: 5,
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: <pw.Widget>[
                  pw.Text(
                    'Class ${worksheet.classNumber}   •   '
                    '${worksheet.subject.label}',
                    style: pw.TextStyle(
                      fontSize: 11,
                      fontWeight: pw.FontWeight.bold,
                      color: _navy,
                    ),
                  ),
                  pw.SizedBox(height: 2),
                  pw.Text(
                    'Topic: ${worksheet.title.replaceAll(
                      RegExp(r'\s*—\s*Worksheet\s*$'),
                      '',
                    )}',
                    style: pw.TextStyle(
                      fontSize: 11,
                      fontWeight: pw.FontWeight.bold,
                      color: _navy,
                    ),
                  ),
                  pw.SizedBox(height: 2),
                  pw.Text(
                    'Language: ${worksheet.languagePair}',
                    style: pw.TextStyle(fontSize: 9, color: _muted),
                  ),
                ],
              ),
            ),
            pw.Expanded(
              flex: 4,
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: <pw.Widget>[
                  _fieldLine('Name:'),
                  pw.SizedBox(height: 10),
                  _fieldLine('Date:'),
                ],
              ),
            ),
          ],
        ),
        pw.SizedBox(height: 8),
        pw.Text(
          worksheet.learningOutcome,
          style: pw.TextStyle(fontSize: 9, color: _muted),
        ),
        pw.SizedBox(height: 8),
        pw.Divider(color: _rule, height: 1, thickness: 1),
      ],
    );
  }

  pw.Widget _continuationHeader(Worksheet worksheet) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: <pw.Widget>[
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: <pw.Widget>[
              pw.Text(
                'GyanSetu AI',
                style: pw.TextStyle(
                  fontSize: 11,
                  fontWeight: pw.FontWeight.bold,
                  color: _navy,
                ),
              ),
              pw.Text(
                'Class ${worksheet.classNumber}  •  '
                '${worksheet.title.replaceAll(
                  RegExp(r'\s*—\s*Worksheet\s*$'),
                  '',
                )}',
                style: pw.TextStyle(fontSize: 9, color: _muted),
              ),
            ],
          ),
          pw.SizedBox(height: 6),
          pw.Divider(color: _rule, height: 1, thickness: 1),
        ],
      );

  pw.Widget _fieldLine(String label) => pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.end,
        children: <pw.Widget>[
          pw.Text(
            label,
            style: pw.TextStyle(fontSize: 10, color: _ink),
          ),
          pw.SizedBox(width: 5),
          pw.Expanded(
            child: pw.Container(
              height: 1,
              color: _rule,
              margin: const pw.EdgeInsets.only(bottom: 2),
            ),
          ),
        ],
      );

  pw.Widget _footer(Worksheet worksheet, int page, int total) => pw.Column(
        children: <pw.Widget>[
          pw.Divider(color: _rule, height: 1, thickness: 1),
          pw.SizedBox(height: 5),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: <pw.Widget>[
              pw.Text(
                'Curriculum aligned  •  '
                '${worksheet.isFullyBilingual ? 'Bilingual  •  ' : ''}'
                'Offline ready',
                style: pw.TextStyle(fontSize: 8, color: _muted),
              ),
              pw.Text(
                'GyanSetu AI   $page / $total',
                style: pw.TextStyle(fontSize: 8, color: _muted),
              ),
            ],
          ),
          pw.SizedBox(height: 2),
          pw.Align(
            alignment: pw.Alignment.centerLeft,
            child: pw.Text(
              'Designed for every child. In every language.',
              style: pw.TextStyle(fontSize: 7.5, color: _muted),
            ),
          ),
        ],
      );

  // --- Questions -----------------------------------------------------------

  pw.Widget _question(Worksheet worksheet, WorksheetQuestion question) {
    return pw.Container(
      margin: const pw.EdgeInsets.only(bottom: 12),
      padding: const pw.EdgeInsets.fromLTRB(10, 9, 10, 11),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: _rule),
        borderRadius: pw.BorderRadius.circular(6),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: <pw.Widget>[
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: <pw.Widget>[
              pw.SizedBox(
                width: 18,
                child: pw.Text(
                  '${question.order}.',
                  style: pw.TextStyle(
                    fontSize: 11,
                    fontWeight: pw.FontWeight.bold,
                    color: _navy,
                  ),
                ),
              ),
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: <pw.Widget>[
                    pw.Text(
                      question.questionText,
                      style: pw.TextStyle(
                        fontSize: 12,
                        fontWeight: pw.FontWeight.bold,
                        color: _ink,
                      ),
                    ),
                    if (question.isBilingual) ...<pw.Widget>[
                      pw.SizedBox(height: 2),
                      pw.Text(
                        question.translatedQuestionText!,
                        style: pw.TextStyle(fontSize: 11, color: _green),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 8),
          pw.Padding(
            padding: const pw.EdgeInsets.only(left: 18),
            child: _questionBody(question),
          ),
        ],
      ),
    );
  }

  pw.Widget _questionBody(WorksheetQuestion question) {
    switch (question.type) {
      case QuestionType.countingObjects:
        return pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: <pw.Widget>[
            pw.Expanded(child: _objects(question)),
            _answerBox(),
          ],
        );

      case QuestionType.matchNumbers:
        return pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.center,
          children: <pw.Widget>[
            pw.Container(
              width: 40,
              height: 26,
              alignment: pw.Alignment.center,
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: _rule),
                borderRadius: pw.BorderRadius.circular(5),
              ),
              child: pw.Text(
                question.correctAnswer,
                style: pw.TextStyle(
                  fontSize: 14,
                  fontWeight: pw.FontWeight.bold,
                  color: _ink,
                ),
              ),
            ),
            pw.SizedBox(width: 10),
            pw.Text('•', style: pw.TextStyle(color: _muted)),
            pw.Expanded(
              child: pw.Container(
                height: 1,
                color: _rule,
                margin: const pw.EdgeInsets.symmetric(horizontal: 8),
              ),
            ),
            pw.Text('•', style: pw.TextStyle(color: _muted)),
            pw.SizedBox(width: 10),
            pw.Expanded(flex: 3, child: _objects(question)),
          ],
        );

      case QuestionType.fillInTheBlanks:
        // The sequence is already in the question text; the child writes into
        // the blank the generator left there.
        return pw.Container(
          height: 22,
          alignment: pw.Alignment.centerLeft,
          child: pw.Text(
            'Write the missing number in the blank above.',
            style: pw.TextStyle(fontSize: 9.5, color: _muted),
          ),
        );

      case QuestionType.visualIdentification:
        return pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: <pw.Widget>[
            _objects(question),
            pw.SizedBox(height: 8),
            pw.Row(
              children: <pw.Widget>[
                for (final String option in question.options)
                  pw.Container(
                    width: 42,
                    height: 24,
                    margin: const pw.EdgeInsets.only(right: 8),
                    alignment: pw.Alignment.center,
                    decoration: pw.BoxDecoration(
                      border: pw.Border.all(color: _rule),
                      borderRadius: pw.BorderRadius.circular(5),
                    ),
                    child: pw.Text(
                      option,
                      style: pw.TextStyle(fontSize: 12, color: _ink),
                    ),
                  ),
              ],
            ),
          ],
        );
    }
  }

  pw.Widget _answerBox() => pw.Container(
        width: 52,
        height: 28,
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: _rule),
          borderRadius: pw.BorderRadius.circular(5),
        ),
      );

  /// The countable objects, drawn from the shared shape instructions so the
  /// printed sheet matches what the teacher approved on screen.
  pw.Widget _objects(WorksheetQuestion question) {
    final VisualExample? example =
        VisualExample.byName(question.visualAsset);
    if (example == null || question.visualCount <= 0) {
      return pw.SizedBox(height: 4);
    }

    final List<ShapeOp> ops = WorksheetShapes.forExample(example);
    const double size = 20;

    return pw.Wrap(
      spacing: 7,
      runSpacing: 6,
      children: <pw.Widget>[
        for (int i = 0; i < question.visualCount; i++)
          pw.SizedBox(
            width: size,
            height: size,
            child: pw.CustomPaint(
              size: const PdfPoint(size, size),
              painter: (PdfGraphics canvas, PdfPoint bounds) =>
                  _paint(canvas, bounds, ops),
            ),
          ),
      ],
    );
  }

  /// Renders the shared shape instructions onto a PDF canvas.
  ///
  /// The PDF's origin is bottom-left while the shapes are described top-down,
  /// so y is flipped here and nowhere else.
  static void _paint(
    PdfGraphics canvas,
    PdfPoint bounds,
    List<ShapeOp> ops,
  ) {
    final double w = bounds.x;
    final double h = bounds.y;
    double fx(double x) => x * w;
    double fy(double y) => h - y * h;

    canvas
      ..setStrokeColor(_gold)
      ..setFillColor(_gold)
      ..setLineWidth(0.9);

    for (final ShapeOp op in ops) {
      switch (op) {
        case CircleOp(:final ShapePoint centre, :final double radius):
          canvas
            ..drawEllipse(
              fx(centre.x),
              fy(centre.y),
              radius * w,
              radius * h,
            )
            ..strokePath();
        case PolygonOp(:final List<ShapePoint> points):
          canvas.moveTo(fx(points.first.x), fy(points.first.y));
          for (final ShapePoint point in points.skip(1)) {
            canvas.lineTo(fx(point.x), fy(point.y));
          }
          canvas
            ..closePath()
            ..strokePath();
        case LineOp(:final ShapePoint from, :final ShapePoint to):
          canvas
            ..moveTo(fx(from.x), fy(from.y))
            ..lineTo(fx(to.x), fy(to.y))
            ..strokePath();
      }
    }
  }

  // --- Answer key ----------------------------------------------------------

  pw.Widget _answerKey(Worksheet worksheet) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: <pw.Widget>[
          for (final WorksheetQuestion question in worksheet.questions)
            pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 7),
              child: pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: <pw.Widget>[
                  pw.SizedBox(
                    width: 26,
                    child: pw.Text(
                      '${question.order}.',
                      style: pw.TextStyle(
                        fontSize: 10,
                        fontWeight: pw.FontWeight.bold,
                        color: _navy,
                      ),
                    ),
                  ),
                  pw.Expanded(
                    child: pw.Text(
                      question.explanation == null
                          ? question.correctAnswer
                          : '${question.correctAnswer}  —  '
                              '${question.explanation}',
                      style: pw.TextStyle(fontSize: 10, color: _ink),
                    ),
                  ),
                ],
              ),
            ),
          if (worksheet.teacherNotes != null) ...<pw.Widget>[
            pw.SizedBox(height: 8),
            pw.Text(
              'Teacher notes',
              style: pw.TextStyle(
                fontSize: 11,
                fontWeight: pw.FontWeight.bold,
                color: _navy,
              ),
            ),
            pw.SizedBox(height: 3),
            pw.Text(
              worksheet.teacherNotes!,
              style: pw.TextStyle(fontSize: 9.5, color: _muted),
            ),
          ],
        ],
      );
}
