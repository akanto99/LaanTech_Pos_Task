import 'dart:async';

import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:laantech_pos_task/configs/services/connectivity_services/connectivity_service.dart';
import 'package:laantech_pos_task/configs/services/notification_services/notification_service.dart';
import 'package:laantech_pos_task/data/network/network_api_service.dart';
import 'package:laantech_pos_task/data/storage/public_download_storage.dart';
import 'package:laantech_pos_task/data/transfer/transfer_manager.dart';
import 'package:laantech_pos_task/data/transfer/transfer_network_monitor.dart';
import 'package:laantech_pos_task/data/transfer/transfer_store.dart';
import 'package:laantech_pos_task/model/transfer/network_health.dart';
import 'package:laantech_pos_task/model/transfer/transfer_command.dart';
import 'package:laantech_pos_task/model/transfer/transfer_task.dart';

/// Messages sent from the service isolate to the UI isolate.
abstract final class TransferEvent {
  static const snapshot = 'snapshot';
  static const openTransfers = 'openTransfers';
}

@pragma('vm:entry-point')
void startTransferTaskHandler() {
  FlutterForegroundTask.setTaskHandler(TransferTaskHandler());
}

/// Runs inside the Android foreground service's own Flutter engine, so
/// transfers keep going when the activity is minimised or swiped away.
class TransferTaskHandler extends TaskHandler {
  static const _syncInterval = Duration(milliseconds: 500);
  static const _idleGracePeriod = Duration(seconds: 3);

  final _ready = Completer<void>();
  late final TransferManager _manager;
  late final TransferNetworkMonitor _network;
  Timer? _syncTimer;
  Timer? _idleTimer;
  String? _serviceText;

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    await NotificationService.instance.initialize();
    final api = NetworkApiService();
    // The isolate's only connectivity listener, shared by every transfer.
    _network = TransferNetworkMonitor(connectivity: ConnectivityService());
    _manager = TransferManager(
      store: TransferStore(),
      apiServices: api,
      downloadStorage: PublicDownloadStorage(),
      networkMonitor: _network,
      notifier: NotificationService.instance,
      onChanged: _scheduleSync,
    );
    await _manager.restore();
    _ready.complete();
    await _manager.start();
    await _sync();
  }

  @override
  void onReceiveData(Object data) {
    if (data is! Map) return;
    final command = TransferCommand.fromJson(Map<String, dynamic>.from(data));
    _ready.future.then((_) => _manager.apply(command));
  }

  @override
  void onRepeatEvent(DateTime timestamp) {}

  @override
  void onNotificationPressed() {
    FlutterForegroundTask.sendDataToMain({'event': TransferEvent.openTransfers});
  }

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {
    _syncTimer?.cancel();
    _idleTimer?.cancel();
    if (_ready.isCompleted) {
      await _manager.shutdown();
      await _network.dispose();
    }
  }

  void _scheduleSync() => _syncTimer ??= Timer(_syncInterval, _sync);

  Future<void> _sync() async {
    _syncTimer = null;
    final tasks = _manager.tasks;
    FlutterForegroundTask.sendDataToMain({'event': TransferEvent.snapshot, 'tasks': tasks.map((task) => task.toJson()).toList()});
    await _manager.persist();
    _updateServiceNotification(tasks);
    _stopWhenIdle();
  }

  void _updateServiceNotification(List<TransferTask> tasks) {
    final running = tasks.where((task) => task.status == TransferStatus.running);
    final queued = tasks.where((task) => task.status == TransferStatus.pending).length;
    final total = running.fold<int>(0, (sum, task) => sum + task.totalBytes);
    final done = running.fold<int>(0, (sum, task) => sum + task.transferredBytes);
    final percent = total > 0 ? (done * 100 / total).floor() : 0;
    final text = ['${running.length} active · $percent%', ?_healthNote(running), if (queued > 0) '$queued queued'].join(' · ');
    if (text == _serviceText) return;
    _serviceText = text;
    FlutterForegroundTask.updateService(notificationTitle: 'Transferring files', notificationText: text);
  }

  static String? _healthNote(Iterable<TransferTask> running) => switch (NetworkHealth.worstOf(running.map((task) => task.networkHealth))) {
    NetworkHealth.offline => 'Waiting for network',
    NetworkHealth.reconnecting => 'Reconnecting…',
    NetworkHealth.stalled => 'Network stalled',
    NetworkHealth.poor => 'Poor network connection',
    NetworkHealth.resumed || NetworkHealth.good => null,
  };

  void _stopWhenIdle() {
    if (_manager.hasActiveWork) {
      _idleTimer?.cancel();
      _idleTimer = null;
      return;
    }
    _idleTimer ??= Timer(_idleGracePeriod, () {
      _idleTimer = null;
      if (!_manager.hasActiveWork) FlutterForegroundTask.stopService();
    });
  }
}
