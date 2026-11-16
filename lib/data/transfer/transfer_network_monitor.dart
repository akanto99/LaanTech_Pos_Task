import 'dart:async';

import 'package:laantech_pos_task/configs/services/connectivity_services/connectivity_service.dart';

/// Shared network state for every transfer in the service isolate.
///
/// Holds the isolate's single connectivity subscription, so transfers never
/// add listeners of their own. Connectivity only says an interface is up; it
/// does not prove the internet or the API works, so [checkServer] confirms the
/// server answers before a transfer is retried.
class TransferNetworkMonitor {
  TransferNetworkMonitor({required ConnectivityService connectivity, required Future<bool> Function() serverReachable}) : _connectivity = connectivity, _serverReachable = serverReachable;

  final ConnectivityService _connectivity;
  final Future<bool> Function() _serverReachable;
  final _changes = StreamController<bool>.broadcast();

  StreamSubscription<bool>? _subscription;
  Future<bool>? _probe;
  bool _online = true;

  bool get isOnline => _online;

  /// Emits when the device goes online or offline.
  Stream<bool> get changes => _changes.stream;

  Future<void> start() async {
    if (_subscription != null) return;
    try {
      _online = await _connectivity.isOnline;
      _subscription = _connectivity.onlineChanges.listen(_set, onError: (Object _) {});
    } catch (_) {
      // Connectivity is unavailable on this platform or engine. Assume online
      // and let request failures and reachability checks decide.
      _online = true;
    }
  }

  /// Completes immediately when online, otherwise on the next online event
  /// (or when the monitor is disposed, so waiters are never left hanging).
  Future<void> whenOnline() => _online ? Future.value() : changes.firstWhere((online) => online, orElse: () => true);

  /// Whether the API server answers right now. Concurrent callers share one
  /// in-flight check instead of each sending a request.
  Future<bool> checkServer() => _probe ??= _runProbe().whenComplete(() => _probe = null);

  Future<bool> _runProbe() async {
    try {
      return await _serverReachable();
    } catch (_) {
      return false;
    }
  }

  void _set(bool online) {
    if (online == _online) return;
    _online = online;
    _changes.add(online);
  }

  Future<void> dispose() async {
    await _subscription?.cancel();
    _subscription = null;
    await _changes.close();
  }
}
