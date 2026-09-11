// ignore_for_file: prefer_initializing_formals
// Private fields cannot be initialising formals: a named parameter may not
// start with an underscore, so `this._lessons` is not expressible.
import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../core/utils/app_logger.dart';
import '../../../models/lesson.dart';
import '../../../services/connectivity/connectivity_service.dart';
import '../../setup/models/classroom_setup.dart';
import '../../setup/models/offline_resource_status.dart';
import '../../setup/services/classroom_setup_repository.dart';
import '../../setup/services/offline_resource_manager.dart';
import 'lesson_download_service.dart';
import 'lesson_query.dart';
import 'lesson_repository.dart';
import 'recommendation_repository.dart';

/// What the header status pill may say.
enum LibraryOfflineState {
  online,
  offlineReady,
  syncRequired,
  resourcesMissing,
  unknown;

  String get label => switch (this) {
        LibraryOfflineState.online => 'Online',
        LibraryOfflineState.offlineReady => 'Offline Ready',
        LibraryOfflineState.syncRequired => 'Sync Required',
        LibraryOfflineState.resourcesMissing =>
          'Offline — Some lessons unavailable',
        LibraryOfflineState.unknown => 'Checking…',
      };
}

/// Drives the lesson library: loads the catalogue, applies the query, ranks
/// recommendations and owns downloads.
class LessonLibraryController extends ChangeNotifier {
  LessonLibraryController({
    required LessonRepository lessons,
    required LessonProgressRepository progress,
    required LessonDownloadRepository downloads,
    required LessonDownloadService downloader,
    required RecommendationRepository recommendations,
    required ClassroomSetupRepository classrooms,
    required OfflineResourceManager resources,
    required ConnectivityService connectivity,
    required String teacherId,
  })  : _lessons = lessons,
        _progress = progress,
        _downloads = downloads,
        _downloader = downloader,
        _recommendations = recommendations,
        _classrooms = classrooms,
        _resources = resources,
        _teacherId = teacherId {
    _connectionStatus = connectivity.status;
    _connectivitySubscription =
        connectivity.onStatusChanged.listen((ConnectionStatus status) {
      _connectionStatus = status;
      notifyListeners();
    });
    unawaited(load());
  }

  final LessonRepository _lessons;
  final LessonProgressRepository _progress;
  final LessonDownloadRepository _downloads;
  final LessonDownloadService _downloader;
  final RecommendationRepository _recommendations;
  final ClassroomSetupRepository _classrooms;
  final OfflineResourceManager _resources;
  final String _teacherId;

  StreamSubscription<ConnectionStatus>? _connectivitySubscription;

  List<LessonCard> _catalogue = const <LessonCard>[];
  List<LessonCard> _recommended = const <LessonCard>[];

  /// Every lesson with its per-device state, before the query is applied.
  List<LessonCard> get catalogue => _catalogue;

  List<LessonCard> get recommended => _recommended;

  ClassroomSetup? _classroom;
  ClassroomSetup? get classroom => _classroom;

  LessonQuery _query = const LessonQuery();
  LessonQuery get query => _query;

  /// The catalogue narrowed and ordered by the current query.
  List<LessonCard> get results => _query.apply(_catalogue);

  bool _loading = true;
  bool get loading => _loading;

  bool _failed = false;

  /// True only when there is nothing at all to show.
  bool get failed => _failed;

  ConnectionStatus _connectionStatus = ConnectionStatus.unknown;
  ConnectionStatus get connectionStatus => _connectionStatus;

  OfflineResourceStatus _resourceStatus = const OfflineResourceStatus.unknown();

  String? _message;

  /// Transient note — a download refusal or an offline explanation. Never an
  /// exception.
  String? get message => _message;

  /// Lessons whose download is in flight, so a second tap cannot start a
  /// second transfer.
  final Set<String> _downloading = <String>{};
  bool isDownloading(String lessonId) => _downloading.contains(lessonId);

  /// What the header pill may claim.
  LibraryOfflineState get offlineState {
    if (_connectionStatus == ConnectionStatus.online) {
      return LibraryOfflineState.online;
    }
    if (_connectionStatus == ConnectionStatus.unknown) {
      return LibraryOfflineState.unknown;
    }
    if (_catalogue.isEmpty) return LibraryOfflineState.unknown;

    final bool allDownloaded = _catalogue.every((LessonCard c) => c.downloaded);
    if (allDownloaded && _resourceStatus.readiness == OfflineReadiness.ready) {
      return LibraryOfflineState.offlineReady;
    }
    if (allDownloaded) return LibraryOfflineState.syncRequired;
    return LibraryOfflineState.resourcesMissing;
  }

  /// Heading over the list, naming the class when one is selected.
  String get listHeading => _query.classNumber == null
      ? 'All Lessons'
      : 'All Lessons (Class ${_query.classNumber})';

  Future<void> load() async {
    _loading = true;
    _failed = false;
    notifyListeners();

    try {
      _classroom = await _classrooms.load(_teacherId);
      _catalogue = await _buildCatalogue();

      // The teacher's own class is the sensible default, but it is only a
      // default: the filter stays theirs to change.
      if (_query.classNumber == null &&
          !_query.hasAnyFilter &&
          _classroom != null) {
        _query = _query.copyWith(classNumber: _classroom!.classLevel);
      }

      if (_classroom != null) {
        _resourceStatus = await _resources.check(_classroom!.resourceProfile);
      }
      _recommended = await _recommendations.recommend(
        catalogue: _catalogue,
        classroom: _classroom,
      );
    } on Object catch (error, stackTrace) {
      AppLogger.error(
        'lesson library load failed',
        error: error,
        stackTrace: stackTrace,
      );
      _failed = _catalogue.isEmpty;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<List<LessonCard>> _buildCatalogue() async {
    final List<Lesson> lessons = await _lessons.lessons();
    final Map<String, int> progress = await _progress.all();
    final Set<String> downloaded = await _downloads.downloadedIds();

    return <LessonCard>[
      for (final Lesson lesson in lessons)
        LessonCard(
          lesson: lesson,
          completionPercentage: progress[lesson.id] ?? 0,
          download: _downloading.contains(lesson.id)
              ? DownloadState.downloading
              : downloaded.contains(lesson.id)
                  ? DownloadState.downloaded
                  : DownloadState.notDownloaded,
        ),
    ];
  }

  /// Pull-to-refresh. Local only; it never waits on the network.
  Future<void> refresh() async {
    await load();
    if (_connectionStatus == ConnectionStatus.offline) {
      _message = 'You are offline. Showing lessons saved on this device.';
      notifyListeners();
    }
  }

  // --- query ---------------------------------------------------------------

  void search(String value) {
    if (_query.search == value) return;
    _query = _query.copyWith(search: value);
    notifyListeners();
  }

  void setClass(int? value) {
    _query = value == null
        ? _query.copyWith(clearClass: true)
        : _query.copyWith(classNumber: value);
    notifyListeners();
  }

  void setSubject(ClassroomSubject? value) {
    _query = value == null
        ? _query.copyWith(clearSubject: true)
        : _query.copyWith(subject: value);
    notifyListeners();
  }

  void setCompletion(CompletionFilter value) {
    _query = _query.copyWith(completion: value);
    notifyListeners();
  }

  void setDownload(DownloadFilter value) {
    _query = _query.copyWith(download: value);
    notifyListeners();
  }

  void setSort(LessonSort value) {
    _query = _query.copyWith(sort: value);
    notifyListeners();
  }

  /// Clears the filters. Search is left alone; the teacher did not ask for it.
  void clearFilters() {
    _query = _query.cleared();
    notifyListeners();
  }

  void clearSearch() {
    _query = _query.copyWith(search: '');
    notifyListeners();
  }

  void dismissMessage() {
    if (_message == null) return;
    _message = null;
    notifyListeners();
  }

  // --- progress ------------------------------------------------------------

  /// Records progress and refreshes the list, so the library never keeps its
  /// own copy of a percentage.
  Future<void> recordProgress(String lessonId, int percent) async {
    await _progress.setPercent(lessonId, percent);
    _catalogue = await _buildCatalogue();
    notifyListeners();
  }

  // --- downloads -----------------------------------------------------------

  /// Whether the lesson can be opened right now.
  Future<bool> canOpen(LessonCard card) async {
    if (card.downloaded) return true;
    return _lessons.isAvailableOffline(card.lesson.id);
  }

  static const String unavailableMessage =
      "This lesson isn't available offline yet.";

  /// Fetches a lesson's content. Refusals are reported, never worked around.
  Future<DownloadOutcome> download(LessonCard card) async {
    final String id = card.lesson.id;
    if (_downloading.contains(id)) {
      return const DownloadRefused(
        DownloadRefusal.failed,
        'This lesson is already downloading.',
      );
    }

    _downloading.add(id);
    _message = null;
    _catalogue = await _buildCatalogue();
    notifyListeners();

    DownloadOutcome outcome;
    try {
      outcome = await _downloader.download(card.lesson);
    } on Object catch (error, stackTrace) {
      AppLogger.error(
        'lesson download threw',
        error: error,
        stackTrace: stackTrace,
      );
      outcome = const DownloadRefused(
        DownloadRefusal.failed,
        'Download failed. Try again.',
      );
    } finally {
      _downloading.remove(id);
    }

    if (outcome is DownloadRefused) _message = outcome.message;
    _catalogue = await _buildCatalogue();
    _recommended = await _recommendations.recommend(
      catalogue: _catalogue,
      classroom: _classroom,
    );
    notifyListeners();
    return outcome;
  }

  @override
  void dispose() {
    unawaited(_connectivitySubscription?.cancel());
    _connectivitySubscription = null;
    super.dispose();
  }
}
