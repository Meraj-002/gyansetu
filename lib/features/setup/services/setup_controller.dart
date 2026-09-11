// ignore_for_file: prefer_initializing_formals
// Private fields cannot be initialising formals: a named parameter may not
// start with an underscore, so `this._repository` is not expressible.
import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../core/utils/app_logger.dart';
import '../../../services/connectivity/connectivity_service.dart';
import '../data/location_data_source.dart';
import '../models/classroom_setup.dart';
import '../models/location.dart';
import '../models/offline_resource_status.dart';
import '../services/classroom_setup_repository.dart';
import '../../../services/audio/language_audio_service.dart';
import '../services/offline_resource_manager.dart';

/// Which field a validation message belongs to.
enum SetupField { schoolName, district, block, targetLanguage, classLevel, subjects }

/// How a save attempt ended.
enum SetupSaveOutcome {
  /// Nothing was attempted: the form is invalid.
  invalid,

  /// Saved, and every offline resource is present.
  savedAndReady,

  /// Saved, but resources still need to arrive over the network. The teacher
  /// may continue — the classroom itself is configured.
  savedResourcesPending,

  /// Saved, but the resource check itself failed.
  savedResourcesFailed,

  /// Nothing was written. The teacher's work is still on screen.
  saveFailed,
}

/// Audio preview state for one of the two Preview & Listen buttons.
enum PreviewState { idle, loading, playing, unavailable }

/// Drives the classroom setup form.
///
/// Holds the working copy of the form, validates it, and orchestrates save →
/// resource preparation → completion. The screen renders this and does not
/// decide anything itself.
class SetupController extends ChangeNotifier {
  SetupController({
    required ClassroomSetupRepository repository,
    required LocationDataSource locations,
    required OfflineResourceManager resources,
    required LanguageAudioService audio,
    required ConnectivityService connectivity,
    required String teacherId,
  })  : _repository = repository,
        _locations = locations,
        _resources = resources,
        _audio = audio,
        _teacherId = teacherId {
    _connectionStatus = connectivity.status;
    _connectivitySubscription =
        connectivity.onStatusChanged.listen((ConnectionStatus status) {
      _connectionStatus = status;
      notifyListeners();
    });
    _bootstrap();
  }

  final ClassroomSetupRepository _repository;
  final LocationDataSource _locations;
  final OfflineResourceManager _resources;
  final LanguageAudioService _audio;
  final String _teacherId;

  StreamSubscription<ConnectionStatus>? _connectivitySubscription;

  // --- form state ------------------------------------------------------------

  String _schoolName = '';
  String get schoolName => _schoolName;

  District? _district;
  District? get district => _district;

  Block? _block;
  Block? get block => _block;

  TeachingMedium _teachingMedium = TeachingMedium.hindi;
  TeachingMedium get teachingMedium => _teachingMedium;

  /// Santali is pre-selected because it is the only language this build ships
  /// prototype content for.
  TargetLanguage _targetLanguage = TargetLanguage.santali;
  TargetLanguage get targetLanguage => _targetLanguage;

  int _classLevel = 1;
  int get classLevel => _classLevel;

  final Set<ClassroomSubject> _subjects = <ClassroomSubject>{
    ClassroomSubject.foundationalLiteracy,
    ClassroomSubject.numeracy,
  };
  Set<ClassroomSubject> get subjects => Set<ClassroomSubject>.unmodifiable(_subjects);

  // --- loaded data -----------------------------------------------------------

  List<District> _districts = const <District>[];
  List<District> get districts => _districts;

  /// Blocks for the chosen district only. Empty until a district is chosen,
  /// which is what makes it impossible to pick a block from elsewhere.
  List<Block> get availableBlocks => _district?.blocks ?? const <Block>[];

  bool _loading = true;
  bool get loading => _loading;

  bool _saving = false;
  bool get saving => _saving;

  /// True when a saved setup was loaded, so this is an edit rather than a
  /// first run.
  bool _isEditing = false;
  bool get isEditing => _isEditing;

  bool _dirty = false;

  /// Whether the teacher has changed anything since the form was loaded.
  bool get hasUnsavedChanges => _dirty;

  ConnectionStatus _connectionStatus = ConnectionStatus.unknown;
  ConnectionStatus get connectionStatus => _connectionStatus;

  OfflineResourceStatus _offlineStatus = const OfflineResourceStatus.unknown();
  OfflineResourceStatus get offlineStatus => _offlineStatus;

  // --- errors ----------------------------------------------------------------

  final Map<SetupField, String> _errors = <SetupField, String>{};
  String? errorFor(SetupField field) => _errors[field];

  /// The first field that failed, so the screen can scroll to it.
  SetupField? _firstInvalidField;
  SetupField? get firstInvalidField => _firstInvalidField;

  String? _saveError;
  String? get saveError => _saveError;

  // --- audio -----------------------------------------------------------------

  PreviewState _targetPreview = PreviewState.idle;
  PreviewState get targetPreview => _targetPreview;

  PreviewState _mediumPreview = PreviewState.idle;
  PreviewState get mediumPreview => _mediumPreview;

  String? _previewMessage;

  /// Set when a preview could not play, explaining why.
  String? get previewMessage => _previewMessage;

  // --- lifecycle -------------------------------------------------------------

  Future<void> _bootstrap() async {
    try {
      _districts = await _locations.districts();
      final ClassroomSetup? existing = await _repository.load(_teacherId);
      if (existing != null) _applyExisting(existing);
    } on Object catch (error, stackTrace) {
      AppLogger.error(
        'setup bootstrap failed',
        error: error,
        stackTrace: stackTrace,
      );
    }
    _loading = false;
    // Loading a saved setup is not a teacher edit.
    _dirty = false;
    notifyListeners();
    await refreshOfflineStatus();
  }

  void _applyExisting(ClassroomSetup s) {
    _isEditing = true;
    _schoolName = s.schoolName;
    _district = _districtById(s.districtId);
    _block = _district?.blockById(s.blockId);
    _teachingMedium = s.teachingMedium;
    _targetLanguage = s.targetLanguage;
    _classLevel = s.classLevel;
    _subjects
      ..clear()
      ..addAll(s.subjects);
  }

  District? _districtById(String id) {
    for (final District d in _districts) {
      if (d.id == id) return d;
    }
    return null;
  }

  /// The parts of the form that decide which content packs are needed.
  ResourceProfile get resourceProfile => ResourceProfile(
        targetLanguage: _targetLanguage,
        classLevel: _classLevel,
        subjects: Set<ClassroomSubject>.from(_subjects),
      );

  /// Re-reads what is on the device for the current selections.
  ///
  /// Works from the opening frame: readiness depends on language, class and
  /// subjects, none of which wait on the school details.
  Future<void> refreshOfflineStatus() async {
    try {
      _offlineStatus = await _resources.check(resourceProfile);
    } on Object catch (error) {
      AppLogger.error('offline resource check failed', error: error);
      _offlineStatus = const OfflineResourceStatus(
        readiness: OfflineReadiness.failed,
        message: 'Could not check offline resources on this device.',
      );
    }
    notifyListeners();
  }

  // --- edits -----------------------------------------------------------------

  void _touch() {
    _dirty = true;
    _saveError = null;
  }

  void setSchoolName(String value) {
    _schoolName = value;
    _touch();
    _errors.remove(SetupField.schoolName);
    notifyListeners();
  }

  void selectDistrict(District? value) {
    if (_district == value) return;
    _district = value;
    // A block belongs to exactly one district, so changing the district must
    // drop the old block rather than leave a mismatched pair.
    _block = null;
    _touch();
    _errors..remove(SetupField.district)..remove(SetupField.block);
    notifyListeners();
  }

  void selectBlock(Block? value) {
    if (value != null && value.districtId != _district?.id) return;
    _block = value;
    _touch();
    _errors.remove(SetupField.block);
    notifyListeners();
  }

  void selectTeachingMedium(TeachingMedium value) {
    if (_teachingMedium == value) return;
    _teachingMedium = value;
    _touch();
    notifyListeners();
    unawaited(refreshOfflineStatus());
  }

  /// Single-select: choosing one target language replaces the previous one.
  void selectTargetLanguage(TargetLanguage value) {
    if (_targetLanguage == value) return;
    _targetLanguage = value;
    _targetPreview = PreviewState.idle;
    _previewMessage = null;
    _touch();
    _errors.remove(SetupField.targetLanguage);
    notifyListeners();
    // A different language means a different resource pack.
    unawaited(refreshOfflineStatus());
  }

  void selectClass(int value) {
    if (_classLevel == value) return;
    _classLevel = value;
    _touch();
    _errors.remove(SetupField.classLevel);
    notifyListeners();
    unawaited(refreshOfflineStatus());
  }

  /// Multi-select: both subjects may be on, or either, or neither. Validation
  /// requires at least one before setup can finish.
  void toggleSubject(ClassroomSubject subject) {
    if (!_subjects.remove(subject)) _subjects.add(subject);
    _touch();
    _errors.remove(SetupField.subjects);
    notifyListeners();
    unawaited(refreshOfflineStatus());
  }

  // --- validation ------------------------------------------------------------

  /// True when every required field is filled, used to enable Finish Setup.
  bool get isComplete =>
      _schoolName.trim().length >= 3 &&
      _district != null &&
      _block != null &&
      _subjects.isNotEmpty &&
      kSupportedClasses.contains(_classLevel);

  bool validate() {
    _errors.clear();

    if (_schoolName.trim().isEmpty) {
      _errors[SetupField.schoolName] = 'School name is required.';
    } else if (_schoolName.trim().length < 3) {
      _errors[SetupField.schoolName] = 'School name looks too short.';
    }
    if (_district == null) _errors[SetupField.district] = 'Select a district.';
    if (_block == null) _errors[SetupField.block] = 'Select a block.';
    if (_subjects.isEmpty) {
      _errors[SetupField.subjects] = 'Select at least one subject.';
    }
    if (!kSupportedClasses.contains(_classLevel)) {
      _errors[SetupField.classLevel] = 'Select a class.';
    }

    _firstInvalidField = _errors.isEmpty
        ? null
        : SetupField.values.firstWhere(_errors.containsKey);

    notifyListeners();
    return _errors.isEmpty;
  }

  /// The current form as a record, or null when required parts are missing.
  ClassroomSetup? _draft({required bool completed}) {
    final District? d = _district;
    final Block? b = _block;
    if (d == null || b == null) return null;

    return ClassroomSetup(
      teacherId: _teacherId,
      schoolName: _schoolName.trim(),
      districtId: d.id,
      districtName: d.name,
      blockId: b.id,
      blockName: b.name,
      teachingMedium: _teachingMedium,
      targetLanguage: _targetLanguage,
      classLevel: _classLevel,
      subjects: Set<ClassroomSubject>.from(_subjects),
      setupCompleted: completed,
      setupCompletedAt: completed ? DateTime.now() : null,
    );
  }

  /// A preview of the summary line, valid even before a district is chosen.
  String get summaryLine {
    final String subjectText = _subjects.isEmpty
        ? 'No subjects'
        : (<String>[
            for (final ClassroomSubject s in ClassroomSubject.values)
              if (_subjects.contains(s)) s.shortLabel,
          ]).join(' + ');
    return 'Class $_classLevel  •  ${_teachingMedium.label} → '
        '${_targetLanguage.label}  •  $subjectText';
  }

  /// Second line of the summary card, describing what has been captured.
  String get summaryDetail {
    if (_district == null || _block == null) {
      return 'Add school, district and block to finish';
    }
    return '${_schoolName.trim().isEmpty ? 'School' : _schoolName.trim()}, '
        '${_district!.name} • ${_block!.name}';
  }

  // --- save ------------------------------------------------------------------

  /// Validates, saves locally, then prepares offline resources.
  ///
  /// The resource step never undoes the save: a classroom that is configured
  /// but not yet stocked is still a usable classroom.
  Future<SetupSaveOutcome> finishSetup() async {
    if (_saving) return SetupSaveOutcome.invalid;
    if (!validate()) return SetupSaveOutcome.invalid;

    final ClassroomSetup? setup = _draft(completed: true);
    if (setup == null) return SetupSaveOutcome.invalid;

    _saving = true;
    _saveError = null;
    notifyListeners();

    try {
      if (!await _repository.save(setup)) {
        _saveError =
            'Your classroom setup could not be saved. Please try again.';
        return SetupSaveOutcome.saveFailed;
      }

      try {
        _offlineStatus = await _resources.prepare(setup.resourceProfile);
      } on Object catch (error, stackTrace) {
        AppLogger.error(
          'offline resource preparation failed',
          error: error,
          stackTrace: stackTrace,
        );
        _offlineStatus = const OfflineResourceStatus(
          readiness: OfflineReadiness.failed,
          message: 'Some offline resources still need to be prepared.',
        );
        _dirty = false;
        return SetupSaveOutcome.savedResourcesFailed;
      }

      _dirty = false;
      _isEditing = true;
      return _offlineStatus.isReady
          ? SetupSaveOutcome.savedAndReady
          : SetupSaveOutcome.savedResourcesPending;
    } on Object catch (error, stackTrace) {
      AppLogger.error(
        'finish setup failed',
        error: error,
        stackTrace: stackTrace,
      );
      _saveError = 'Your classroom setup could not be saved. Please try again.';
      return SetupSaveOutcome.saveFailed;
    } finally {
      _saving = false;
      notifyListeners();
    }
  }

  // --- audio preview ---------------------------------------------------------

  Future<void> previewTargetLanguage() =>
      _preview(target: _targetLanguage, isTarget: true);

  Future<void> previewTeachingMedium() =>
      _preview(medium: _teachingMedium, isTarget: false);

  Future<void> _preview({
    TargetLanguage? target,
    TeachingMedium? medium,
    required bool isTarget,
  }) async {
    void set(PreviewState state) {
      if (isTarget) {
        _targetPreview = state;
      } else {
        _mediumPreview = state;
      }
      notifyListeners();
    }

    if ((isTarget ? _targetPreview : _mediumPreview) == PreviewState.playing) {
      await _audio.stop();
      set(PreviewState.idle);
      return;
    }

    _previewMessage = null;
    set(PreviewState.loading);

    try {
      final AudioPlaybackResult result =
          await _audio.play(target: target, medium: medium);
      switch (result) {
        case AudioPlaying():
          set(PreviewState.playing);
        case AudioUnavailable(:final String message):
          _previewMessage = message;
          set(PreviewState.unavailable);
      }
    } on Object catch (error) {
      AppLogger.error('audio preview failed', error: error);
      _previewMessage = 'Audio could not be played on this device.';
      set(PreviewState.unavailable);
    }
  }

  @override
  void dispose() {
    unawaited(_connectivitySubscription?.cancel());
    _connectivitySubscription = null;
    unawaited(_audio.stop());
    super.dispose();
  }
}
