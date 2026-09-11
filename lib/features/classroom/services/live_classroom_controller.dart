// ignore_for_file: prefer_initializing_formals
// Private fields cannot be initialising formals: a named parameter may not
// start with an underscore.
import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../core/utils/app_logger.dart';
import '../../../services/ai/ai_runtime_status_service.dart';
import '../../../services/connectivity/connectivity_service.dart';
import '../models/classroom_session.dart';
import '../models/classroom_state.dart';
import '../models/conversation_turn.dart';
import '../models/voice_pipeline_metrics.dart';
import 'voice_conversation_service.dart';

/// What the live classroom screen reads.
///
/// A thin adapter: the pipeline itself lives in [VoiceConversationService], and
/// this class only turns its events into something a widget tree can rebuild
/// from. Keeping them apart is what lets the pipeline be tested with no widgets
/// at all.
class LiveClassroomController extends ChangeNotifier {
  LiveClassroomController({
    required VoiceConversationService conversation,
    required AiRuntimeStatusService runtime,
    required ConnectivityService connectivity,
    required ConversationContext context,
  })  : _conversation = conversation,
        _runtime = runtime,
        _connectivity = connectivity,
        _context = context {
    _eventSubscription = _conversation.events.listen(_onEvent);

    // The waveform rebuilds from its own notifier, so sixty amplitude updates a
    // second do not rebuild the whole screen on a 2 GB phone.
    _amplitudeSubscription = _conversation.amplitude.listen((double level) {
      amplitude.value = level;
    });

    _connectivitySubscription =
        _connectivity.onStatusChanged.listen((ConnectionStatus status) {
      _connection = status;
      // The pipeline is not restarted on a network change; only the status the
      // header reports is refreshed.
      unawaited(refreshRuntimeStatus());
    });

    _connection = _connectivity.status;
    unawaited(refreshRuntimeStatus());
  }

  final VoiceConversationService _conversation;
  final AiRuntimeStatusService _runtime;
  final ConnectivityService _connectivity;
  final ConversationContext _context;

  StreamSubscription<ConversationEvent>? _eventSubscription;
  StreamSubscription<double>? _amplitudeSubscription;
  StreamSubscription<ConnectionStatus>? _connectivitySubscription;

  /// Microphone level, 0..1. Listened to directly by the waveform.
  final ValueNotifier<double> amplitude = ValueNotifier<double>(0);

  ConversationContext get context => _context;

  ClassroomState get state => _conversation.state;

  ConversationDirection get direction => _conversation.direction;

  bool get muted => _conversation.muted;

  List<ConversationTurn> get turns => _conversation.turns;

  ClassroomSession get session => _conversation.session;

  ConnectionStatus _connection = ConnectionStatus.unknown;
  ConnectionStatus get connection => _connection;

  AiRuntimeStatus _runtimeStatus = const AiRuntimeStatus.connecting();

  /// What the header pill says, and why.
  AiRuntimeStatus get runtimeStatus => _runtimeStatus;

  ConversationFailure? _failure;

  /// The last failure, still on screen until it is retried or dismissed.
  ConversationFailure? get failure => _failure;

  /// The most recent measured turn. Null until one completes, which is why the
  /// badge can honestly read `Latency: --` at the start of a session.
  VoicePipelineMetrics? get latestMetrics {
    for (final ConversationTurn turn in turns.reversed) {
      final VoicePipelineMetrics? metrics = turn.metrics;
      if (metrics != null) return metrics;
    }
    return null;
  }

  /// True when any measurement so far came from a development adapter.
  bool get isDemoPipeline =>
      _runtimeStatus.usesDevelopmentAdapters ||
      (latestMetrics?.measuredWithMocks ?? false);

  /// The turn currently being built, if any.
  ConversationTurn? get activeTurn {
    for (final ConversationTurn turn in turns.reversed) {
      if (turn.status != TurnStatus.played &&
          turn.status != TurnStatus.failed) {
        return turn;
      }
    }
    return null;
  }

  /// The most recent teacher-side turn, which the teacher card shows.
  ConversationTurn? get latestTeacherTurn => _latestFor(TurnSpeaker.teacher);

  /// The most recent pupil-side turn, which the student card shows.
  ConversationTurn? get latestStudentTurn => _latestFor(TurnSpeaker.student);

  ConversationTurn? _latestFor(TurnSpeaker speaker) {
    for (final ConversationTurn turn in turns.reversed) {
      if (turn.speaker == speaker) return turn;
    }
    return null;
  }

  bool get hasPreviousAudio => _conversation.lastAudibleTurn != null;

  bool get busy => state.isBusy || state.isCapturing;

  // --- Actions -------------------------------------------------------------

  Future<void> refreshRuntimeStatus() async {
    _runtimeStatus = await _runtime.check(
      sourceLocaleId: _context.sourceLocaleFor(direction),
      targetLocaleId: _context.targetLocaleFor(direction),
      spokenScriptLocaleId: _context.teachingMedium.localeId,
    );
    notifyListeners();
  }

  /// The single microphone action: start a turn, or stop one already running.
  Future<void> tapMicrophone() async {
    AppLogger.debug('[LIVE] mic pressed');
    if (state.isCapturing) {
      await _conversation.stopListening();
      return;
    }
    _failure = null;
    notifyListeners();
    await _conversation.speak(ConversationDirection.teacherToStudent);
  }

  /// Opens the microphone for a pupil, in the mother tongue.
  Future<void> startStudentTurn() async {
    if (state.isCapturing) {
      await _conversation.stopListening();
      return;
    }
    _failure = null;
    notifyListeners();
    await _conversation.speak(ConversationDirection.studentToTeacher);
  }

  Future<void> cancel() => _conversation.cancel();

  Future<void> retry() async {
    _failure = null;
    notifyListeners();
    await _conversation.retry();
  }

  void dismissFailure() {
    if (_failure == null) return;
    _failure = null;
    notifyListeners();
  }

  /// Plays the current translation to the class.
  Future<void> playToStudents() async {
    final ConversationTurn? turn = latestTeacherTurn;
    if (turn == null) return;
    await _conversation.playTurn(turn.id);
  }

  Future<void> playTurn(String turnId) => _conversation.playTurn(turnId);

  Future<void> repeatLast() => _conversation.repeatLast();

  Future<void> toggleMute() async {
    await _conversation.setMuted(!muted);
    notifyListeners();
  }

  Future<void> clearTimeline() async {
    await _conversation.clearTimeline();
    notifyListeners();
  }

  /// Ends the session and returns it as it was saved.
  Future<ClassroomSession> endSession() => _conversation.end();

  /// Called when the app goes to the background. The microphone must not stay
  /// open behind a lock screen.
  Future<void> onPaused() async {
    if (state.isCapturing) await _conversation.cancel();
  }

  void _onEvent(ConversationEvent event) {
    switch (event) {
      case ConversationStateChanged():
        notifyListeners();
      case ConversationTurnChanged():
        notifyListeners();
      case ConversationFailureRaised(:final ConversationFailure failure):
        _failure = failure;
        notifyListeners();
    }
  }

  @override
  void dispose() {
    unawaited(_eventSubscription?.cancel());
    unawaited(_amplitudeSubscription?.cancel());
    unawaited(_connectivitySubscription?.cancel());
    amplitude.dispose();
    super.dispose();
  }
}
