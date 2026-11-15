import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:laantech_pos_task/data/transfer/transfer_manager.dart';
import 'package:laantech_pos_task/model/transfer/transfer_task.dart';

/// Per-transfer notifications. Used from the foreground-service isolate to
/// post updates and from the UI isolate to receive taps.
class NotificationService implements TransferNotifier {
  NotificationService._();

  static final NotificationService instance = NotificationService._();

  static const _icon = '@mipmap/ic_launcher';
  static const _progressInterval = Duration(seconds: 1);

  final _plugin = FlutterLocalNotificationsPlugin();
  final _lastStatus = <String, TransferStatus>{};
  final _lastProgress = <String, ({DateTime at, int percent})>{};

  Future<void> initialize({void Function(String? transferId)? onTap}) async {
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings(_icon),
      ),
      onDidReceiveNotificationResponse: onTap == null
          ? null
          : (response) => onTap(response.payload),
    );
  }

  /// Transfer id of the notification that cold-started the app, if any.
  Future<String?> launchTransferId() async {
    final details = await _plugin.getNotificationAppLaunchDetails();
    return details?.didNotificationLaunchApp ?? false
        ? details!.notificationResponse?.payload
        : null;
  }

  @override
  void onTaskChanged(TransferTask task) {
    final previous = _lastStatus[task.id];
    _lastStatus[task.id] = task.status;

    switch (task.status) {
      case TransferStatus.running:
        if (previous != TransferStatus.running || _progressDue(task)) {
          _showProgress(task);
        }
      case TransferStatus.paused:
        if (previous != task.status) _showProgress(task);
      case TransferStatus.completed:
      case TransferStatus.failed:
        if (previous != task.status) _showResult(task);
      case TransferStatus.pending:
      case TransferStatus.cancelled:
        if (previous != task.status) _plugin.cancel(id: _id(task));
    }
  }

  bool _progressDue(TransferTask task) {
    final last = _lastProgress[task.id];
    return last == null ||
        (last.percent != task.percent &&
            DateTime.now().difference(last.at) >= _progressInterval);
  }

  void _showProgress(TransferTask task) {
    _lastProgress[task.id] = (at: DateTime.now(), percent: task.percent);
    final paused = task.status == TransferStatus.paused;
    final verb = task.isUpload ? 'Uploading' : 'Downloading';
    _plugin.show(
      id: _id(task),
      title: paused ? 'Download paused' : '$verb ${task.fileName}',
      body: paused
          ? '${task.fileName} · ${task.percent}%'
          : task.totalBytes > 0
          ? '${task.percent}%'
          : 'Starting…',
      payload: task.id,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          'transfer_progress',
          'Transfer progress',
          channelDescription: 'Live progress of uploads and downloads',
          importance: Importance.low,
          priority: Priority.low,
          onlyAlertOnce: true,
          showWhen: false,
          playSound: false,
          ongoing: !paused,
          autoCancel: paused,
          showProgress: true,
          maxProgress: 100,
          progress: task.percent,
          indeterminate: task.totalBytes <= 0,
          category: AndroidNotificationCategory.progress,
        ),
      ),
    );
  }

  void _showResult(TransferTask task) {
    final success = task.status == TransferStatus.completed;
    final kind = task.isUpload ? 'Upload' : 'Download';
    _plugin.show(
      id: _id(task),
      title: success ? '$kind complete' : '$kind failed',
      body: success ? task.fileName : '${task.fileName}: ${task.error ?? ''}',
      payload: task.id,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'transfer_results',
          'Transfer results',
          channelDescription: 'Completed and failed uploads and downloads',
          importance: Importance.high,
          priority: Priority.high,
          autoCancel: true,
        ),
      ),
    );
  }

  int _id(TransferTask task) => task.id.hashCode & 0x7fffffff;
}
