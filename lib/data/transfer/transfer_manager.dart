import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:laantech_pos_task/configs/res/app_config.dart';
import 'package:laantech_pos_task/configs/res/app_url.dart';
import 'package:laantech_pos_task/data/app_exceptions.dart';
import 'package:laantech_pos_task/data/network/base_api_services.dart';
import 'package:laantech_pos_task/data/transfer/transfer_store.dart';
import 'package:laantech_pos_task/model/transfer/transfer_command.dart';
import 'package:laantech_pos_task/model/transfer/transfer_task.dart';

abstract class TransferNotifier {
  void onTaskChanged(TransferTask task);
}

/// Owns the transfer queue: scheduling, execution, retries and persistence.
///
/// Runs inside the Android foreground-service isolate. The UI isolate creates
/// a non-executing instance only to apply commands to the persisted queue
/// while the service is stopped, so both sides share one set of rules.
class TransferManager {
  TransferManager({required TransferStore store, BaseApiServices? apiServices, TransferNotifier? notifier, void Function()? onChanged, this.retryBaseDelay = AppConfig.retryBaseDelay})
    : _store = store,
      _api = apiServices,
      _notifier = notifier,
      _onChanged = onChanged;

  final TransferStore _store;
  final BaseApiServices? _api;
  final TransferNotifier? _notifier;
  final void Function()? _onChanged;
  final Duration retryBaseDelay;

  final _tasks = <String, TransferTask>{};
  final _cancelTokens = <String, CancelToken>{};
  final _stopRequests = <String, TransferStatus>{};

  bool get _executes => _api != null;

  List<TransferTask> get tasks => _tasks.values.toList()..sort((a, b) => b.createdAt.compareTo(a.createdAt));

  bool get hasActiveWork => _tasks.values.any((task) => task.status.isActive);

  Future<void> restore() async {
    for (final task in await _store.load()) {
      _tasks[task.id] = task.status == TransferStatus.running ? _interrupted(task) : task;
    }
  }

  void start() => _pump();

  Future<void> persist() => _store.save(tasks);

  Future<void> apply(TransferCommand command) async {
    final id = command.id;
    switch (command.action) {
      case TransferAction.enqueue:
        for (final task in command.tasks) {
          _tasks[task.id] = task.isUpload ? task : task.copyWith(localPath: _availablePath(task.localPath, task.id));
        }
      case TransferAction.pause:
        if (_tasks[id]?.canPause ?? false) {
          await _stop(id!, TransferStatus.paused);
        }
      case TransferAction.cancel:
        await _stop(id!, TransferStatus.cancelled);
      case TransferAction.resume:
      case TransferAction.retry:
        _requeue(id!);
      case TransferAction.remove:
        final task = _tasks[id];
        await _stop(id!, TransferStatus.cancelled);
        _tasks.remove(id);
        if (task != null) await _discardFiles(task);
      case TransferAction.clearFinished:
        for (final task in tasks.where((task) => task.status.isFinished)) {
          await _discardFiles(task);
          _tasks.remove(task.id);
        }
      case TransferAction.reset:
        for (final task in _tasks.values.toList()) {
          await _stop(task.id, TransferStatus.cancelled);
          await _discardFiles(task);
        }
        _tasks.clear();
      case TransferAction.sync:
        break;
    }
    _trimHistory();
    _onChanged?.call();
    _pump();
  }

  /// Called when the service is destroyed (user stop, OS timeout, crash
  /// recovery). Work is marked so it can be resumed or retried later.
  Future<void> shutdown() async {
    for (final id in _cancelTokens.keys.toList()) {
      final task = _tasks[id]!;
      _tasks[id] = _interrupted(task);
      _cancelTokens.remove(id)?.cancel();
    }
    await persist();
  }

  TransferTask _interrupted(TransferTask task) => task.isUpload
      ? task.copyWith(status: TransferStatus.failed, transferredBytes: 0, error: 'Upload was interrupted. Retry to upload it again.')
      : task.copyWith(status: TransferStatus.pending, clearError: true);

  void _requeue(String id) {
    final task = _tasks[id];
    if (task == null || task.status.isActive || task.status == TransferStatus.completed) {
      return;
    }
    _update(task.copyWith(status: TransferStatus.pending, transferredBytes: task.isUpload ? 0 : null, clearError: true));
  }

  Future<void> _stop(String id, TransferStatus status) async {
    final task = _tasks[id];
    if (task == null || task.status.isFinished) return;
    final token = _cancelTokens[id];
    if (token != null) {
      _stopRequests[id] = status;
      token.cancel();
    } else {
      await _applyStop(task, status);
    }
  }

  Future<void> _applyStop(TransferTask task, TransferStatus status) async {
    if (status == TransferStatus.cancelled) await _deletePartial(task);
    _update(task.copyWith(status: status, transferredBytes: status == TransferStatus.cancelled || task.isUpload ? 0 : null, clearError: true));
  }

  void _pump() {
    if (!_executes) return;
    final pending = _tasks.values.where((task) => task.status == TransferStatus.pending).toList()..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    for (final task in pending) {
      if (_runningCount >= AppConfig.maxConcurrentTransfers) break;
      unawaited(_run(task.id));
    }
  }

  int get _runningCount => _tasks.values.where((task) => task.status == TransferStatus.running).length;

  Future<void> _run(String id) async {
    for (var attempt = 0; ;) {
      final task = _tasks[id];
      if (task == null) return;
      final token = CancelToken();
      _cancelTokens[id] = token;
      _update(task.copyWith(status: TransferStatus.running, clearError: true));

      try {
        await (task.isUpload ? _upload(id, token) : _download(id, token));
        _cancelTokens.remove(id);
        break;
      } catch (error) {
        _cancelTokens.remove(id);
        final stop = _stopRequests.remove(id);
        final current = _tasks[id];
        if (current == null) {
          await _discardFiles(task);
          break;
        }
        if (stop != null) {
          await _applyStop(current, stop);
          break;
        }

        final exception = error is AppException ? error : const AppException('An unexpected error occurred.');
        // Downloads resume from their partial file, so an attempt that made
        // progress resets the budget; only consecutive dead attempts count.
        if (!current.isUpload && current.transferredBytes > task.transferredBytes) {
          attempt = 0;
        }
        if (exception.retryable && attempt < AppConfig.maxAutoRetries) {
          final delay = retryBaseDelay * (1 << attempt);
          _update(
            current.copyWith(
              error:
                  '${exception.message} Retrying in ${delay.inSeconds}s '
                  '(${attempt + 1}/${AppConfig.maxAutoRetries})',
            ),
          );
          await Future<void>.delayed(delay);
          if (_tasks[id]?.status != TransferStatus.running) break;
          attempt++;
          continue;
        }
        _update(current.copyWith(status: TransferStatus.failed, transferredBytes: current.isUpload ? 0 : null, error: exception.message));
        break;
      }
    }
    _pump();
  }

  Future<void> _upload(String id, CancelToken token) async {
    final task = _tasks[id]!;
    final response = await _api!.uploadFileApi(
      AppUrl.upload,
      filePath: task.localPath,
      fileName: task.fileName,
      cancelToken: token,
      // Multipart framing adds a few bytes, so progress is scaled to the file size.
      onProgress: (sent, total) => _progress(id, total > 0 ? (sent * task.totalBytes / total).round() : sent),
    );
    final file = (response as Map<String, dynamic>)['file'] as Map<String, dynamic>;
    _update(_tasks[id]!.copyWith(status: TransferStatus.completed, transferredBytes: task.totalBytes, serverFileName: file['name'] as String?, remoteUrl: file['url'] as String?));
    await _store.deleteIfTemporary(task.localPath);
  }

  Future<void> _download(String id, CancelToken token) async {
    final task = _tasks[id]!;
    await _api!.downloadFileApi(
      AppUrl.fileUrl(task.serverFileName!),
      savePath: task.partialPath,
      cancelToken: token,
      onProgress: (received, total) => _progress(id, received, total: total > 0 ? total : null),
    );
    final current = _tasks[id]!;
    final destination = _availablePath(current.localPath, id);
    await File(current.partialPath).rename(destination);
    final size = await File(destination).length();
    _update(current.copyWith(status: TransferStatus.completed, localPath: destination, totalBytes: size, transferredBytes: size));
  }

  void _progress(String id, int transferred, {int? total}) {
    final task = _tasks[id];
    if (task == null || task.status != TransferStatus.running) return;
    _update(task.copyWith(transferredBytes: transferred, totalBytes: total));
  }

  void _update(TransferTask task) {
    if (!_tasks.containsKey(task.id)) return;
    _tasks[task.id] = task;
    _notifier?.onTaskChanged(task);
    _onChanged?.call();
  }

  /// Removes app-owned data for a task leaving the queue: a download's
  /// partial file or an upload's temporary picker copy.
  Future<void> _discardFiles(TransferTask task) => task.isUpload ? _store.deleteIfTemporary(task.localPath) : _deletePartial(task);

  Future<void> _deletePartial(TransferTask task) async {
    if (task.isUpload) return;
    final partial = File(task.partialPath);
    if (await partial.exists()) await partial.delete();
  }

  /// Returns [desired], or "name (n).ext", so neither an existing file nor
  /// another queued download is ever overwritten.
  String _availablePath(String desired, String ownerId) {
    final dot = desired.lastIndexOf('.');
    final slash = desired.lastIndexOf(Platform.pathSeparator);
    final hasExtension = dot > slash + 1;
    final base = hasExtension ? desired.substring(0, dot) : desired;
    final extension = hasExtension ? desired.substring(dot) : '';

    bool taken(String path) => File(path).existsSync() || _tasks.values.any((task) => task.id != ownerId && !task.isUpload && task.status != TransferStatus.cancelled && task.localPath == path);

    var candidate = desired;
    for (var copy = 1; taken(candidate); copy++) {
      candidate = '$base ($copy)$extension';
    }
    return candidate;
  }

  void _trimHistory() {
    final finished = tasks.where((task) => task.status.isFinished).toList();
    for (final task in finished.skip(AppConfig.maxHistory)) {
      _tasks.remove(task.id);
    }
  }
}
