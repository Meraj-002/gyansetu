import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';

/// Coarse connectivity state the UI can react to.
enum ConnectionStatus {
  /// A network interface is up.
  online,

  /// No interface is up. Only locally provisioned work can proceed.
  offline,

  /// Not determined yet. The UI must not claim either state.
  unknown,
}

/// Contract for observing whether the device can reach the backend.
abstract interface class ConnectivityService {
  ConnectionStatus get status;

  /// Emits on every transition. Does not re-emit the same status twice.
  Stream<ConnectionStatus> get onStatusChanged;

  /// Re-reads the current state rather than trusting the cached value.
  Future<ConnectionStatus> check();

  Future<void> dispose();
}

/// Reads the platform's network interface state.
///
/// IMPORTANT: this reports whether an interface is up, not whether the server
/// is reachable. A classroom hotspot with no uplink still reads as
/// [ConnectionStatus.online]. Anything that must know the server answered has
/// to attempt the call and handle [AuthFailureReason.network]; the UI here only
/// uses it to choose which path to try first.
class PlatformConnectivityService implements ConnectivityService {
  PlatformConnectivityService([Connectivity? connectivity])
      : _connectivity = connectivity ?? Connectivity() {
    try {
      _subscription = _connectivity.onConnectivityChanged.listen(
        (List<ConnectivityResult> results) => _emit(_map(results)),
        onError: (Object _) => _emit(ConnectionStatus.unknown),
      );
    } on Object {
      // No platform channel (widget test, unsupported host): stay unknown
      // rather than claiming either state.
    }
    unawaited(check());
  }

  final Connectivity _connectivity;
  final StreamController<ConnectionStatus> _controller =
      StreamController<ConnectionStatus>.broadcast();
  StreamSubscription<List<ConnectivityResult>>? _subscription;

  ConnectionStatus _status = ConnectionStatus.unknown;

  @override
  ConnectionStatus get status => _status;

  @override
  Stream<ConnectionStatus> get onStatusChanged => _controller.stream;

  @override
  Future<ConnectionStatus> check() async {
    try {
      _emit(_map(await _connectivity.checkConnectivity()));
    } on Object {
      // A platform channel failure is not evidence of being offline.
      _emit(ConnectionStatus.unknown);
    }
    return _status;
  }

  static ConnectionStatus _map(List<ConnectivityResult> results) {
    if (results.isEmpty) return ConnectionStatus.unknown;
    final bool anyUp = results.any(
      (ConnectivityResult r) => r != ConnectivityResult.none,
    );
    return anyUp ? ConnectionStatus.online : ConnectionStatus.offline;
  }

  void _emit(ConnectionStatus next) {
    if (next == _status) return;
    _status = next;
    if (!_controller.isClosed) _controller.add(next);
  }

  @override
  Future<void> dispose() async {
    await _subscription?.cancel();
    _subscription = null;
    await _controller.close();
  }
}

/// Fixed-state service for tests and previews.
class StaticConnectivityService implements ConnectivityService {
  StaticConnectivityService(this._status);

  ConnectionStatus _status;
  final StreamController<ConnectionStatus> _controller =
      StreamController<ConnectionStatus>.broadcast();

  @override
  ConnectionStatus get status => _status;

  @override
  Stream<ConnectionStatus> get onStatusChanged => _controller.stream;

  @override
  Future<ConnectionStatus> check() async => _status;

  /// Test hook for driving a transition.
  void set(ConnectionStatus next) {
    if (next == _status) return;
    _status = next;
    if (!_controller.isClosed) _controller.add(next);
  }

  @override
  Future<void> dispose() async => _controller.close();
}
