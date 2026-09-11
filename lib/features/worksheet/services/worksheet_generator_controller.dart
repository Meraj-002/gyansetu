// ignore_for_file: prefer_initializing_formals
// Private fields cannot be initialising formals: a named parameter may not
// start with an underscore.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../../core/utils/app_logger.dart';
import '../../../models/lesson.dart';
import '../../../models/question.dart';
import '../../../models/worksheet.dart';
import '../../../services/connectivity/connectivity_service.dart';
import '../../../services/storage/secure_storage_service.dart';
import '../../lessons/services/lesson_repository.dart';
import '../../setup/models/classroom_setup.dart';
import '../../setup/services/classroom_setup_repository.dart';
import 'worksheet_generation_service.dart';
import 'worksheet_repository.dart';
import 'worksheet_validator.dart';

/// Where the screen is in its own lifecycle.
enum GeneratorLoadState { loading, ready, error }

/// What the Generate button is doing.
enum GenerationState { idle, generating, success, failed }

/// The stages the progress panel names while a worksheet is built.
///
/// These describe what this app is doing, in order, and each one is set when
/// that step actually begins. They are not a timed animation standing in for
/// a service that reports nothing.
enum GenerationStage {
  preparingLesson(label: 'Preparing lesson…'),
  writingQuestions(label: 'Generating questions…'),
  buildingBilingual(label: 'Creating bilingual content…'),
  preparingVisuals(label: 'Preparing visual examples…'),
  finalising(label: 'Finalising worksheet…');

  const GenerationStage({required this.label});

  final String label;
}

/// Drives the worksheet generator.
///
/// Holds the teacher's choices, the lesson and the classroom, and hands a
/// request to whichever [WorksheetGenerationService] is wired in. It knows
/// nothing about where questions come from.
class WorksheetGeneratorController extends ChangeNotifier {
  WorksheetGeneratorController({
    required String lessonId,
    required LessonRepository lessons,
    required ClassroomSetupRepository classrooms,
    required WorksheetGenerationService generator,
    required WorksheetRepository worksheets,
    required ConnectivityService connectivity,
    required SecureStorageService storage,
    required String teacherId,
  })  : _lessonId = lessonId,
        _lessons = lessons,
        _classrooms = classrooms,
        _generator = generator,
        _worksheets = worksheets,
        _connectivity = connectivity,
        _storage = storage,
        _teacherId = teacherId {
    _connectionStatus = _connectivity.status;
    _connectivitySubscription =
        _connectivity.onStatusChanged.listen((ConnectionStatus status) {
      _connectionStatus = status;
      notifyListeners();
    });
    unawaited(load());
  }

  static const String _preferencesKey = 'worksheets.preferences';

  final String _lessonId;
  final LessonRepository _lessons;
  final ClassroomSetupRepository _classrooms;
  final WorksheetGenerationService _generator;
  final WorksheetRepository _worksheets;
  final ConnectivityService _connectivity;
  final SecureStorageService _storage;
  final String _teacherId;

  StreamSubscription<ConnectionStatus>? _connectivitySubscription;

  // --- Loaded context ------------------------------------------------------

  GeneratorLoadState _loadState = GeneratorLoadState.loading;
  GeneratorLoadState get loadState => _loadState;

  Lesson? _lesson;
  Lesson? get lesson => _lesson;

  ClassroomSetup? _classroom;
  ClassroomSetup? get classroom => _classroom;

  bool _generatorReady = false;

  /// Whether a worksheet can actually be produced right now.
  bool get generatorReady => _generatorReady;

  ConnectionStatus _connectionStatus = ConnectionStatus.unknown;

  /// What the header pill may claim. Never "Offline AI Active" unless the
  /// generator really is available with no connection.
  String get offlineStatusLabel {
    if (!_generatorReady) return 'Offline generation unavailable';
    return switch (_connectionStatus) {
      ConnectionStatus.offline => 'Offline Ready',
      ConnectionStatus.online => 'Online Ready',
      ConnectionStatus.unknown => 'Checking…',
    };
  }

  bool get offlineCapable => _generatorReady;

  /// The mother tongue this classroom teaches into.
  TargetLanguage get targetLanguage =>
      _classroom?.targetLanguage ?? TargetLanguage.santali;

  TeachingMedium get teachingMedium =>
      _classroom?.teachingMedium ?? TeachingMedium.hindi;

  String get languagePair =>
      '${teachingMedium.label}  +  ${targetLanguage.label}';

  int get classNumber => _classroom?.classLevel ?? _lesson?.classNumber ?? 1;

  // --- The teacher's choices ----------------------------------------------

  WorksheetDifficulty _difficulty = WorksheetDifficulty.easy;
  WorksheetDifficulty get difficulty => _difficulty;

  final Set<QuestionType> _questionTypes = <QuestionType>{
    QuestionType.countingObjects,
  };
  Set<QuestionType> get questionTypes =>
      Set<QuestionType>.unmodifiable(_questionTypes);

  int _numberOfQuestions = 10;
  int get numberOfQuestions => _numberOfQuestions;

  static const List<int> questionCountOptions = <int>[5, 10, 15];

  final Set<VisualExample> _visualExamples = <VisualExample>{
    VisualExample.apples,
  };
  Set<VisualExample> get visualExamples =>
      Set<VisualExample>.unmodifiable(_visualExamples);

  bool _culturallyFamiliar = true;
  bool get culturallyFamiliar => _culturallyFamiliar;

  // --- Generation ----------------------------------------------------------

  GenerationState _generationState = GenerationState.idle;
  GenerationState get generationState => _generationState;

  GenerationStage? _stage;

  /// The step being worked on, or null when nothing is running.
  GenerationStage? get stage => _stage;

  Worksheet? _worksheet;

  /// The worksheet just produced, which the preview is opened with.
  Worksheet? get worksheet => _worksheet;

  String? _message;

  /// A note for the teacher — a validation refusal, a failure. Never an
  /// exception.
  String? get message => _message;

  void dismissMessage() {
    if (_message == null) return;
    _message = null;
    notifyListeners();
  }

  bool get isGenerating => _generationState == GenerationState.generating;

  /// Where the questions came from. Read by the preview's labelling.
  GenerationSource get generationSource => _generator.source;

  // --- Loading -------------------------------------------------------------

  Future<void> load() async {
    _loadState = GeneratorLoadState.loading;
    notifyListeners();

    try {
      _lesson = await _lessons.lessonById(_lessonId);
      _classroom = await _classrooms.load(_teacherId);
      _generatorReady = await _generator.isAvailable;
      await _restorePreferences();

      _loadState = _lesson == null
          ? GeneratorLoadState.error
          : GeneratorLoadState.ready;
    } on Object catch (error) {
      AppLogger.error('worksheet generator could not load', error: error);
      _loadState = GeneratorLoadState.error;
    }
    notifyListeners();
  }

  // --- Choices -------------------------------------------------------------

  void setDifficulty(WorksheetDifficulty value) {
    if (_difficulty == value) return;
    _difficulty = value;
    _message = null;
    notifyListeners();
    unawaited(_savePreferences());
  }

  /// Multi-select. The last remaining type cannot be removed, because a
  /// worksheet with no question types is not a worksheet.
  void toggleQuestionType(QuestionType type) {
    if (_questionTypes.contains(type)) {
      if (_questionTypes.length == 1) {
        _message = 'Keep at least one question type.';
        notifyListeners();
        return;
      }
      _questionTypes.remove(type);
    } else {
      _questionTypes.add(type);
    }
    _message = null;
    notifyListeners();
    unawaited(_savePreferences());
  }

  void setQuestionCount(int value) {
    if (_numberOfQuestions == value) return;
    _numberOfQuestions = value;
    notifyListeners();
    unawaited(_savePreferences());
  }

  void toggleVisualExample(VisualExample example) {
    if (_visualExamples.contains(example)) {
      if (_visualExamples.length == 1) {
        _message = 'Keep at least one visual example.';
        notifyListeners();
        return;
      }
      _visualExamples.remove(example);
    } else {
      _visualExamples.add(example);
    }
    _message = null;
    notifyListeners();
    unawaited(_savePreferences());
  }

  void setCulturallyFamiliar(bool value) {
    if (_culturallyFamiliar == value) return;
    _culturallyFamiliar = value;
    notifyListeners();
    unawaited(_savePreferences());
  }

  // --- Validation ----------------------------------------------------------

  /// Why the worksheet cannot be generated, or null when it can.
  String? get validationMessage {
    final Lesson? lesson = _lesson;
    if (lesson == null) return "Couldn't load this lesson.";
    if (lesson.learningOutcome.trim().isEmpty) {
      return 'This lesson has no learning outcome, so a worksheet cannot be '
          'aligned to it.';
    }
    if (_classroom == null) {
      return 'Finish classroom setup so the worksheet knows the class and the '
          'languages.';
    }
    if (_questionTypes.isEmpty) return 'Choose at least one question type.';
    if (_numberOfQuestions <= 0) {
      return 'Choose how many questions the worksheet should have.';
    }
    if (_visualExamples.isEmpty) {
      return 'Choose at least one visual example.';
    }
    if (!_generatorReady) {
      return 'Worksheet generation is not available on this device yet.';
    }
    return null;
  }

  bool get canGenerate => validationMessage == null && !isGenerating;

  /// The request as it stands. Built from the lesson and the classroom, never
  /// from what the screen is displaying.
  WorksheetGenerationRequest? buildRequest({int variant = 0}) {
    final Lesson? lesson = _lesson;
    final ClassroomSetup? classroom = _classroom;
    if (lesson == null || classroom == null) return null;

    // Python lesson uses English as its target language instead of Santali.
    final TargetLanguage targetLang = lesson.id == 'python-intro'
        ? TargetLanguage.english
        : classroom.targetLanguage;

    return WorksheetGenerationRequest(
      lessonId: lesson.id,
      lessonTitle: lesson.title,
      learningOutcome: lesson.learningOutcome,
      classNumber: classroom.classLevel,
      subject: lesson.subject,
      teachingLanguage: classroom.teachingMedium,
      targetLanguage: targetLang,
      difficulty: _difficulty,
      questionTypes: Set<QuestionType>.from(_questionTypes),
      numberOfQuestions: _numberOfQuestions,
      concepts: lesson.concepts,
      visualExamples: _visualExamples.toList(),
      culturallyFamiliarExamples: _culturallyFamiliar,
      variant: variant,
    );
  }

  // --- Generating ----------------------------------------------------------

  /// Builds the worksheet and saves it. Returns it, or null on failure.
  ///
  /// A second call while one is running is ignored, so a double tap cannot
  /// produce two worksheets.
  Future<Worksheet?> generate() async {
    if (isGenerating) return null;

    final String? invalid = validationMessage;
    if (invalid != null) {
      _message = invalid;
      _generationState = GenerationState.failed;
      notifyListeners();
      return null;
    }

    final WorksheetGenerationRequest? request = buildRequest();
    if (request == null) {
      _message = "Couldn't generate the worksheet.";
      _generationState = GenerationState.failed;
      notifyListeners();
      return null;
    }

    _generationState = GenerationState.generating;
    _message = null;
    _setStage(GenerationStage.preparingLesson);

    try {
      _setStage(GenerationStage.writingQuestions);
      final Worksheet worksheet = await _generator.generate(request);

      _setStage(GenerationStage.buildingBilingual);
      final List<WorksheetProblem> problems =
          WorksheetValidator.validate(worksheet, request);
      if (problems.isNotEmpty) {
        // A generator that miscounted or left a question blank does not get to
        // put its output in front of a class.
        AppLogger.error(
          'generated worksheet failed validation: '
          '${problems.map((WorksheetProblem p) => p.toString()).join('; ')}',
        );
        _fail("Couldn't generate the worksheet.");
        return null;
      }

      _setStage(GenerationStage.preparingVisuals);
      _setStage(GenerationStage.finalising);
      await _worksheets.save(worksheet);

      _worksheet = worksheet;
      _generationState = GenerationState.success;
      _stage = null;
      notifyListeners();
      return worksheet;
    } on WorksheetGenerationFailure catch (failure) {
      _fail(failure.message);
      return null;
    } on Object catch (error) {
      AppLogger.error('worksheet generation failed', error: error);
      _fail("Couldn't generate the worksheet.");
      return null;
    }
  }

  /// Runs the same request again after a failure.
  Future<Worksheet?> retry() {
    _generationState = GenerationState.idle;
    _message = null;
    notifyListeners();
    return generate();
  }

  void _setStage(GenerationStage stage) {
    _stage = stage;
    notifyListeners();
  }

  void _fail(String message) {
    _generationState = GenerationState.failed;
    _stage = null;
    _message = message;
    notifyListeners();
  }

  // --- Remembered choices --------------------------------------------------

  Future<void> _restorePreferences() async {
    try {
      final String? raw = await _storage.read(_preferencesKey);
      if (raw == null || raw.isEmpty) return;
      final Map<String, dynamic> json =
          jsonDecode(raw) as Map<String, dynamic>;

      _difficulty = WorksheetDifficulty.byName(json['difficulty'] as String?);
      _numberOfQuestions = json['numberOfQuestions'] as int? ?? 10;
      _culturallyFamiliar = json['culturallyFamiliar'] as bool? ?? true;

      final Set<QuestionType> types = <QuestionType>{
        for (final dynamic t
            in json['questionTypes'] as List<dynamic>? ?? const <dynamic>[])
          if (QuestionType.byName(t as String?) case final QuestionType v) v,
      };
      if (types.isNotEmpty) {
        _questionTypes
          ..clear()
          ..addAll(types);
      }

      final Set<VisualExample> examples = <VisualExample>{
        for (final dynamic v
            in json['visualExamples'] as List<dynamic>? ?? const <dynamic>[])
          if (VisualExample.byName(v as String?) case final VisualExample e) e,
      };
      if (examples.isNotEmpty) {
        _visualExamples
          ..clear()
          ..addAll(examples);
      }
    } on Object catch (error) {
      // Remembered choices are a convenience; a bad record is dropped rather
      // than allowed to stop the screen opening.
      AppLogger.error('worksheet preferences could not be read', error: error);
    }
  }

  Future<void> _savePreferences() async {
    try {
      await _storage.write(
        _preferencesKey,
        jsonEncode(<String, dynamic>{
          'difficulty': _difficulty.name,
          'numberOfQuestions': _numberOfQuestions,
          'culturallyFamiliar': _culturallyFamiliar,
          'questionTypes': <String>[
            for (final QuestionType t in _questionTypes) t.name,
          ],
          'visualExamples': <String>[
            for (final VisualExample v in _visualExamples) v.name,
          ],
        }),
      );
    } on Object catch (error) {
      AppLogger.error('worksheet preferences could not be saved', error: error);
    }
  }

  @override
  void dispose() {
    unawaited(_connectivitySubscription?.cancel());
    super.dispose();
  }
}
