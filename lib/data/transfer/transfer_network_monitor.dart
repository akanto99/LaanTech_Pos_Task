import 'dart:async';

import 'package:laantech_pos_task/configs/services/connectivity_services/connectivity_service.dart';

/// Shared network state for every transfer in the service isolate.
///
/// Holds the isolate's single connectivity subscription, so transfers never
/// add listeners of their own. Connectivity only says an interface is up; it
/// does not prove the server can be reached, so after a reconnection the
/// retried transfer request itself is the reachability check.
class TransferNetworkMonitor {
  TransferNetworkMonitor({required ConnectivityService connectivity}) : _connectivity = connectivity;

  final ConnectivityService _connectivity;
  final _changes = StreamController<bool>.broadcast();

  StreamSubscription<bool>? _subscription;
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

  /// Completes on the next online/offline change (or on dispose). Lets a
  /// retry backoff end early when the network changes.
  Future<void> nextChange() => changes.first.then<void>((_) {}, onError: (Object _) {});

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
