// ignore_for_file: prefer_initializing_formals
// Private fields cannot be initialising formals: a named parameter may not
// start with an underscore, so `this._repository` is not expressible.
import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../core/utils/app_logger.dart';
import '../../../models/lesson.dart';
import '../../lessons/services/lesson_repository.dart';
import '../../../services/audio/language_audio_service.dart';
import '../../../services/connectivity/connectivity_service.dart';
import '../models/home_dashboard.dart';
import 'home_repository.dart';

/// Which part of the day the greeting should use.
enum DayPart {
  morning('Good Morning'),
  afternoon('Good Afternoon'),
  evening('Good Evening');

  const DayPart(this.greeting);

  final String greeting;

  /// Derived from the device clock, never fixed.
  static DayPart at(DateTime time) {
    final int hour = time.hour;
    if (hour < 12) return DayPart.morning;
    if (hour < 17) return DayPart.afternoon;
    return DayPart.evening;
  }
}

/// Audio state for the `Listen in <language>` action.
enum ListenState { idle, loading, playing, unavailable }

/// Drives the dashboard: loads it, refreshes it, and owns the audio preview.
class HomeController extends ChangeNotifier {
  HomeController({
    required HomeRepository repository,
    required LessonRepository lessons,
    required LanguageAudioService audio,
    required ConnectivityService connectivity,
    DateTime Function()? clock,
  })  : _repository = repository,
        _lessons = lessons,
        _audio = audio,
        _clock = clock ?? DateTime.now {
    _connectionStatus = connectivity.status;
    _connectivitySubscription =
        connectivity.onStatusChanged.listen((ConnectionStatus status) {
      // Only the offline strip depends on this, so it is a cheap rebuild
      // rather than a reload of the whole dashboard.
      _connectionStatus = status;
      notifyListeners();
    });
    unawaited(load());
  }

  final HomeRepository _repository;
  final LessonRepository _lessons;
  final LanguageAudioService _audio;
  final DateTime Function() _clock;

  StreamSubscription<ConnectionStatus>? _connectivitySubscription;

  HomeDashboard? _dashboard;
  HomeDashboard? get dashboard => _dashboard;

  bool _loading = true;
  bool get loading => _loading;

  bool _failed = false;

  /// True when the dashboard could not be assembled at all.
  bool get failed => _failed;

  ConnectionStatus _connectionStatus = ConnectionStatus.unknown;
  ConnectionStatus get connectionStatus => _connectionStatus;

  ListenState _listenState = ListenState.idle;
  ListenState get listenState => _listenState;

  String? _message;

  /// Transient note shown under the hero card — an audio or resource
  /// explanation, never an exception.
  String? get message => _message;

  /// Greeting for the current moment and the signed-in teacher.
  String get greeting {
    final String name = _dashboard?.teacherName?.trim().isNotEmpty ?? false
        ? _dashboard!.teacherName!.trim()
        : 'Teacher';
    return '${DayPart.at(_clock()).greeting}, $name';
  }

  Future<void> load() async {
    _loading = true;
    _failed = false;
    notifyListeners();

    try {
      _dashboard = await _repository.load(now: _clock());
    } on Object catch (error, stackTrace) {
      AppLogger.error(
        'home dashboard load failed',
        error: error,
        stackTrace: stackTrace,
      );
      // Keep whatever was already on screen; only report failure when there is
      // nothing at all to show.
      _failed = _dashboard == null;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// Pull-to-refresh. Re-reads local data; it never blocks on the network.
  Future<void> refresh() async {
    await load();
    if (_connectionStatus == ConnectionStatus.offline) {
      _message = 'You are offline. Showing the latest saved classroom data.';
      notifyListeners();
    }
  }

  void dismissMessage() {
    if (_message == null) return;
    _message = null;
    notifyListeners();
  }

  /// Whether the lesson body is on the device, checked before opening it.
  Future<bool> canOpenLesson() async {
    final Lesson? lesson = _dashboard?.todayLesson;
    if (lesson == null) return false;
    try {
      return await _lessons.isAvailableOffline(lesson.id);
    } on Object catch (error) {
      AppLogger.error('lesson availability check failed', error: error);
      return false;
    }
  }

  /// Message shown when a lesson cannot be opened.
  static const String lessonUnavailableMessage =
      'This lesson is not on your device yet. Connect to the internet to '
      'download it.';

  /// Plays, or stops, the lesson sample in the target language.
  Future<void> toggleListen() async {
    final target = _dashboard?.classroom?.targetLanguage;
    if (target == null) return;

    if (_listenState == ListenState.playing) {
      await _audio.stop();
      _listenState = ListenState.idle;
      notifyListeners();
      return;
    }

    _message = null;
    _listenState = ListenState.loading;
    notifyListeners();

    try {
      final AudioPlaybackResult result = await _audio.play(target: target);
      switch (result) {
        case AudioPlaying():
          _listenState = ListenState.playing;
        case AudioUnavailable(:final String message):
          _listenState = ListenState.unavailable;
          _message = message;
      }
    } on Object catch (error) {
      AppLogger.error('lesson audio failed', error: error);
      _listenState = ListenState.unavailable;
      _message = 'Audio is not available offline.';
    }
    notifyListeners();
  }

  @override
  void dispose() {
    unawaited(_connectivitySubscription?.cancel());
    _connectivitySubscription = null;
    unawaited(_audio.stop());
    super.dispose();
  }
}
