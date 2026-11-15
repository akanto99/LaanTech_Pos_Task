import 'dart:async';
import 'dart:math';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:laantech_pos_task/configs/res/app_config.dart';
import 'package:laantech_pos_task/data/app_exceptions.dart';
import 'package:laantech_pos_task/data/transfer/transfer_manager.dart';
import 'package:laantech_pos_task/data/transfer/transfer_store.dart';
import 'package:laantech_pos_task/data/transfer/transfer_task_handler.dart';
import 'package:laantech_pos_task/model/server_file/server_file_model.dart';
import 'package:laantech_pos_task/model/transfer/transfer_command.dart';
import 'package:laantech_pos_task/model/transfer/transfer_task.dart';

typedef UploadSelection = ({
  List<TransferTask> accepted,
  List<String> rejected,
});

/// UI-isolate gateway to the background transfer service.
class TransferRepository {
  TransferRepository({TransferStore? store})
    : _store = store ?? TransferStore();

  final TransferStore _store;
  final _updates = StreamController<List<TransferTask>>.broadcast();
  final _openRequests = StreamController<void>.broadcast();
  final _random = Random();

  static const _serviceId = 1000;

  Stream<List<TransferTask>> get updates => _updates.stream;
  Stream<void> get openRequests => _openRequests.stream;

  static void initialize() {
    FlutterForegroundTask.initCommunicationPort();
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'transfer_service',
        channelName: 'Background transfers',
        channelDescription: 'Keeps uploads and downloads running',
        onlyAlertOnce: true,
      ),
      iosNotificationOptions: const IOSNotificationOptions(),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.nothing(),
        allowWakeLock: true,
        allowWifiLock: true,
      ),
    );
  }

  void attach() => FlutterForegroundTask.addTaskDataCallback(_onServiceData);

  void detach() => FlutterForegroundTask.removeTaskDataCallback(_onServiceData);

  Future<List<TransferTask>> loadTasks() async {
    if (await FlutterForegroundTask.isRunningService) {
      FlutterForegroundTask.sendDataToTask(
        const TransferCommand(TransferAction.sync).toJson(),
      );
    }
    final manager = TransferManager(store: _store);
    await manager.restore();
    return manager.tasks;
  }

  /// Sends [command] to the running service. When the service is stopped the
  /// command is applied to the persisted queue, and the service is started if
  /// that leaves work to do; it then picks the queue up on start.
  Future<void> dispatch(TransferCommand command) async {
    if (await FlutterForegroundTask.isRunningService) {
      FlutterForegroundTask.sendDataToTask(command.toJson());
      return;
    }
    final manager = TransferManager(store: _store);
    await manager.restore();
    await manager.apply(command);
    await manager.persist();
    _updates.add(manager.tasks);
    if (manager.hasActiveWork) await _startService();
  }

  Future<UploadSelection> pickUploads() async {
    final files = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: AppConfig.uploadExtensions,
    );
    final accepted = <TransferTask>[];
    final rejected = <String>[];
    for (final file in files) {
      final path = file.path;
      final size = await file.length() ?? 0;
      final extension = file.extension?.toLowerCase();
      if (path == null ||
          size == 0 ||
          !AppConfig.uploadExtensions.contains(extension)) {
        rejected.add(file.name);
        continue;
      }
      accepted.add(
        _newTask(
          TransferType.upload,
          fileName: file.name,
          localPath: path,
          totalBytes: size,
        ),
      );
    }
    return (accepted: accepted, rejected: rejected);
  }

  Future<TransferTask> createDownload(ServerFileModel file) async {
    final directory = await _store.downloadsDirectory();
    final fileName = _safeFileName(file.originalName);
    return _newTask(
      TransferType.download,
      fileName: fileName,
      localPath: '${directory.path}/$fileName',
      totalBytes: file.size,
      serverFileName: file.name,
      remoteUrl: file.url,
    );
  }

  Future<void> _startService() async {
    if (await FlutterForegroundTask.checkNotificationPermission() !=
        NotificationPermission.granted) {
      await FlutterForegroundTask.requestNotificationPermission();
    }
    final result = await FlutterForegroundTask.startService(
      serviceId: _serviceId,
      serviceTypes: [ForegroundServiceTypes.dataSync],
      notificationTitle: 'Transferring files',
      notificationText: 'Preparing…',
      callback: startTransferTaskHandler,
    );
    if (result is ServiceRequestFailure) {
      throw AppException(
        'Could not start background transfers: ${result.error}',
      );
    }
  }

  void _onServiceData(Object data) {
    if (data is! Map) return;
    switch (data['event']) {
      case TransferEvent.snapshot:
        _updates.add(
          (data['tasks'] as List<dynamic>)
              .map(
                (task) => TransferTask.fromJson(
                  Map<String, dynamic>.from(task as Map),
                ),
              )
              .toList(),
        );
      case TransferEvent.openTransfers:
        _openRequests.add(null);
    }
  }

  TransferTask _newTask(
    TransferType type, {
    required String fileName,
    required String localPath,
    required int totalBytes,
    String? serverFileName,
    String? remoteUrl,
  }) {
    final now = DateTime.now();
    return TransferTask(
      id: '${now.microsecondsSinceEpoch}-${_random.nextInt(1 << 32)}',
      type: type,
      fileName: fileName,
      localPath: localPath,
      totalBytes: totalBytes,
      transferredBytes: 0,
      status: TransferStatus.pending,
      createdAt: now,
      updatedAt: now,
      serverFileName: serverFileName,
      remoteUrl: remoteUrl,
    );
  }

  String _safeFileName(String name) {
    final cleaned = name
        .replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1F]'), '_')
        .trim();
    return cleaned.isEmpty || cleaned.startsWith('.')
        ? 'file_$cleaned'
        : cleaned;
  }
}
