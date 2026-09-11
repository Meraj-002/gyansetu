// ignore_for_file: prefer_initializing_formals
// Private fields cannot be initialising formals: a named parameter may not
// start with an underscore.
import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../core/utils/app_logger.dart';
import '../../../models/lesson.dart';
import '../../../models/worksheet.dart';
import '../../../services/connectivity/connectivity_service.dart';
import '../../../services/files/document_writer.dart';
import '../../../services/files/saved_file.dart';
import '../../../services/worksheet_pdf_service.dart';
import '../../lessons/services/lesson_repository.dart';
import 'worksheet_generation_service.dart';
import 'worksheet_repository.dart';
import 'worksheet_validator.dart';

/// Where the screen is in its own lifecycle.
enum PreviewLoadState { loading, loaded, error }

/// What the PDF actions are doing. One at a time: building a document twice at
/// once on a 2 GB phone helps nobody.
enum PdfTask { none, saving, printing, sharing, regenerating }

/// What the platform can actually do with a PDF here.
class PrintingCapability {
  const PrintingCapability({required this.canPrint, required this.canShare});

  const PrintingCapability.unknown()
      : canPrint = false,
        canShare = false;

  final bool canPrint;
  final bool canShare;
}

/// Asks the platform what it supports, and does the printing and sharing.
///
/// An interface so the screen can be tested without a print dialog, and so the
/// plugin stays replaceable.
abstract interface class WorksheetOutputService {
  Future<PrintingCapability> capability();

  /// Opens the system print preview with these exact bytes.
  Future<bool> printPdf(WorksheetPdf pdf);

  /// Opens the system share sheet with these exact bytes.
  Future<bool> sharePdf(WorksheetPdf pdf);
}

/// Drives the worksheet preview.
///
/// It loads one worksheet by id and never invents one. Everything the screen
/// shows, the PDF prints, the printer receives and the share sheet sends comes
/// from that single [Worksheet].
class WorksheetPreviewController extends ChangeNotifier {
  WorksheetPreviewController({
    required String worksheetId,
    required WorksheetRepository worksheets,
    required WorksheetPdfService pdfService,
    required WorksheetOutputService output,
    required LessonRepository lessons,
    required ConnectivityService connectivity,
    WorksheetGenerationService? generator,
    Worksheet? initial,
  })  : _worksheetId = worksheetId,
        _worksheets = worksheets,
        _pdfService = pdfService,
        _output = output,
        _lessons = lessons,
        _connectivity = connectivity,
        _generator = generator,
        _worksheet = initial {
    unawaited(load());
  }

  String _worksheetId;
  final WorksheetRepository _worksheets;
  final WorksheetPdfService _pdfService;
  final WorksheetOutputService _output;
  final LessonRepository _lessons;
  final ConnectivityService _connectivity;

  /// Null when this build has no generator wired in; Regenerate then says so
  /// rather than appearing to work.
  final WorksheetGenerationService? _generator;

  PreviewLoadState _loadState = PreviewLoadState.loading;
  PreviewLoadState get loadState => _loadState;

  Worksheet? _worksheet;
  Worksheet? get worksheet => _worksheet;

  Lesson? _lesson;

  /// The lesson this worksheet was built for, used to keep a regeneration
  /// aligned to the same concepts.
  Lesson? get lesson => _lesson;

  PrintingCapability _capability = const PrintingCapability.unknown();
  PrintingCapability get capability => _capability;

  PdfTask _task = PdfTask.none;
  PdfTask get task => _task;

  bool get busy => _task != PdfTask.none;

  /// The last document built, reused by print and share so all three actions
  /// send the same bytes.
  WorksheetPdf? _pdf;
  WorksheetPdf? get pdf => _pdf;

  SavedFile? _savedFile;

  /// Where the PDF was written, once it has been.
  SavedFile? get savedFile => _savedFile;

  bool get isSaved => _savedFile != null;

  String? _message;

  /// A note for the teacher. Never an exception.
  String? get message => _message;

  bool _failed = false;

  /// True when the last action failed, so the button can offer another go.
  bool get lastActionFailed => _failed;

  void dismissMessage() {
    if (_message == null) return;
    _message = null;
    notifyListeners();
  }

  bool get isOffline => _connectivity.status == ConnectionStatus.offline;

  /// How many pages the PDF will have. Known before it is built.
  int get pageCount {
    final Worksheet? value = _worksheet;
    return value == null ? 1 : _pdfService.pageCountFor(value);
  }

  /// What the header status may claim, from the worksheet's own metadata.
  ({String title, String subtitle, bool ai}) get status {
    final Worksheet? value = _worksheet;
    final bool ai = value?.isAiGenerated ?? false;
    return (
      title: ai ? 'AI-Generated' : 'Generated Offline',
      subtitle: 'Curriculum aligned',
      ai: ai,
    );
  }

  // --- Loading -------------------------------------------------------------

  Future<void> load() async {
    _loadState = PreviewLoadState.loading;
    notifyListeners();

    try {
      _worksheet = _worksheet?.id == _worksheetId
          ? _worksheet
          : await _worksheets.byId(_worksheetId);

      final Worksheet? value = _worksheet;
      if (value == null) {
        _loadState = PreviewLoadState.error;
        notifyListeners();
        return;
      }

      _lesson = await _lessons.lessonById(value.lessonId);
      _capability = await _output.capability();
      _loadState = PreviewLoadState.loaded;
    } on Object catch (error) {
      AppLogger.error('worksheet could not be loaded', error: error);
      _loadState = PreviewLoadState.error;
    }
    notifyListeners();
  }

  /// Problems with the worksheet itself, checked before it is shown.
  List<WorksheetProblem> get problems {
    final Worksheet? value = _worksheet;
    if (value == null) return const <WorksheetProblem>[];
    return WorksheetValidator.validate(value, _requestFor(value));
  }

  bool get isValid => problems.isEmpty;

  // --- PDF -----------------------------------------------------------------

  /// Builds the document once and keeps it, so print and share do not rebuild
  /// what save already produced.
  Future<WorksheetPdf?> _buildPdf() async {
    final Worksheet? value = _worksheet;
    if (value == null) return null;

    final WorksheetPdf? held = _pdf;
    if (held != null) return held;

    final WorksheetPdf built = await _pdfService.build(value);
    if (built.isEmpty) {
      // An empty document is never saved, printed or shared.
      throw StateError('the generated PDF was empty');
    }
    return _pdf = built;
  }

  /// Builds the PDF and writes it to the device.
  Future<SavedFile?> savePdf() async {
    if (busy) return null;
    final Worksheet? value = _worksheet;
    if (value == null) return null;

    _begin(PdfTask.saving);
    try {
      final WorksheetPdf? built = await _buildPdf();
      if (built == null) return _fail('Couldn’t create the PDF.');

      final SavedFile? file = await writeDocument(built.bytes, built.fileName);
      if (file == null) {
        // The web cannot write to a folder. The share sheet is the browser's
        // download there, so the teacher is pointed at it rather than told a
        // save happened.
        _end(
          _capability.canShare
              ? 'This device can’t keep the file in a folder. Use Share to '
                  'download it.'
              : 'This device can’t save the file.',
          failed: true,
        );
        return null;
      }

      _savedFile = file;
      _end('Worksheet saved as ${file.fileName}.');
      return file;
    } on Object catch (error) {
      AppLogger.error('worksheet pdf could not be saved', error: error);
      return _fail('Couldn’t save the worksheet.');
    }
  }

  Future<bool> printPdf() async {
    if (busy) return false;
    if (!_capability.canPrint) {
      _message = 'Printing isn’t available on this device.';
      _failed = true;
      notifyListeners();
      return false;
    }

    _begin(PdfTask.printing);
    try {
      final WorksheetPdf? built = await _buildPdf();
      if (built == null) {
        _fail('Couldn’t create the PDF.');
        return false;
      }
      final bool sent = await _output.printPdf(built);
      _end(sent ? null : 'Printing was cancelled.');
      return sent;
    } on Object catch (error) {
      AppLogger.error('worksheet could not be printed', error: error);
      _fail('Printing isn’t available on this device.');
      return false;
    }
  }

  Future<bool> sharePdf() async {
    if (busy) return false;
    if (!_capability.canShare) {
      _message = 'Sharing isn’t available on this device.';
      _failed = true;
      notifyListeners();
      return false;
    }

    _begin(PdfTask.sharing);
    try {
      final WorksheetPdf? built = await _buildPdf();
      if (built == null) {
        _fail('Couldn’t create the PDF.');
        return false;
      }
      final bool shared = await _output.sharePdf(built);
      _end(null);
      return shared;
    } on Object catch (error) {
      AppLogger.error('worksheet could not be shared', error: error);
      _fail('Couldn’t share the worksheet.');
      return false;
    }
  }

  // --- Regenerate ----------------------------------------------------------

  /// True when a new worksheet can be produced from here.
  bool get canRegenerate => _generator != null && _worksheet != null;

  /// Builds a fresh worksheet from the same choices.
  ///
  /// Everything the teacher picked is carried over — lesson, class, both
  /// languages, difficulty, question types, count, visual examples, the
  /// culturally-familiar setting — and only the variant advances, so the sheet
  /// is genuinely different rather than the same one again.
  Future<Worksheet?> regenerate() async {
    final WorksheetGenerationService? generator = _generator;
    final Worksheet? current = _worksheet;
    if (generator == null || current == null || busy) return null;

    _begin(PdfTask.regenerating);
    try {
      final WorksheetGenerationRequest request = _requestFor(
        current,
        variant: current.variant + 1,
      );
      final Worksheet next = await generator.generate(request);

      final List<WorksheetProblem> issues =
          WorksheetValidator.validate(next, request);
      if (issues.isNotEmpty) {
        AppLogger.error(
          'regenerated worksheet failed validation: '
          '${issues.map((WorksheetProblem p) => p.toString()).join('; ')}',
        );
        _fail('Couldn’t generate a new worksheet.');
        return null;
      }

      await _worksheets.save(next);

      _worksheet = next;
      _worksheetId = next.id;
      // The old document belongs to the old worksheet; it must not be printed
      // for the new one.
      _pdf = null;
      _savedFile = null;
      _end('A new worksheet is ready.');
      return next;
    } on WorksheetGenerationFailure catch (failure) {
      _fail(failure.message);
      return null;
    } on Object catch (error) {
      AppLogger.error('worksheet could not be regenerated', error: error);
      _fail('Couldn’t generate a new worksheet.');
      return null;
    }
  }

  /// Rebuilds the request that produced [worksheet].
  ///
  /// Read back off the worksheet itself — its difficulty, its question types,
  /// its count, its objects — so a regeneration keeps the teacher's choices
  /// without the screen having to carry them separately.
  WorksheetGenerationRequest _requestFor(Worksheet worksheet, {int? variant}) =>
      WorksheetGenerationRequest(
        lessonId: worksheet.lessonId,
        lessonTitle: _lesson?.title ??
            worksheet.title.replaceAll(RegExp(r'\s*—\s*Worksheet\s*$'), ''),
        learningOutcome: worksheet.learningOutcome,
        classNumber: worksheet.classNumber,
        subject: worksheet.subject,
        teachingLanguage: worksheet.teachingLanguage,
        targetLanguage: worksheet.targetLanguage,
        difficulty: worksheet.difficulty,
        questionTypes: worksheet.questionTypes,
        numberOfQuestions: worksheet.requestedQuestionCount,
        concepts: _lesson?.concepts ?? const <String>[],
        visualExamples: worksheet.visualExamples,
        culturallyFamiliarExamples: worksheet.culturallyFamiliarExamples,
        variant: variant ?? worksheet.variant,
      );

  // --- Plumbing ------------------------------------------------------------

  void _begin(PdfTask task) {
    _task = task;
    _message = null;
    _failed = false;
    notifyListeners();
  }

  void _end(String? message, {bool failed = false}) {
    _task = PdfTask.none;
    _message = message;
    _failed = failed;
    notifyListeners();
  }

  Null _fail(String message) {
    _end(message, failed: true);
    return null;
  }
}
