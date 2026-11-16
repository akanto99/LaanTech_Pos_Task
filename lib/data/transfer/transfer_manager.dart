import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:laantech_pos_task/configs/res/app_config.dart';
import 'package:laantech_pos_task/configs/res/app_url.dart';
import 'package:laantech_pos_task/configs/utils/file_names.dart';
import 'package:laantech_pos_task/data/app_exceptions.dart';
import 'package:laantech_pos_task/data/network/base_api_services.dart';
import 'package:laantech_pos_task/data/storage/base_download_storage.dart';
import 'package:laantech_pos_task/data/transfer/throughput_tracker.dart';
import 'package:laantech_pos_task/data/transfer/transfer_network_monitor.dart';
import 'package:laantech_pos_task/data/transfer/transfer_store.dart';
import 'package:laantech_pos_task/model/server_file/server_file_model.dart';
import 'package:laantech_pos_task/model/transfer/network_health.dart';
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
///
/// Network health: each running attempt is measured by a [ThroughputTracker]
/// (good / poor / stalled) and the shared [TransferNetworkMonitor] reports
/// connectivity. When the network is lost nothing is sent until it returns;
/// then the transfer is retried at once (the retry is the reachability
/// check). Only consecutive failures that move no data back off
/// exponentially, and any connectivity change cuts that backoff short.
/// Downloads resume with HTTP Range; uploads restart from zero because the
/// server only accepts a single multipart request.
class TransferManager {
  TransferManager({
    required TransferStore store,
    BaseApiServices? apiServices,
    BaseDownloadStorage? downloadStorage,
    TransferNetworkMonitor? networkMonitor,
    TransferNotifier? notifier,
    void Function()? onChanged,
    this.retryBaseDelay = AppConfig.retryBaseDelay,
    this.healthTick = AppConfig.networkHealthTick,
    this.offlineAbortAfter = AppConfig.offlineAbortAfter,
    this.reconnectStallAfter = AppConfig.reconnectStallAfter,
    this.networkWaitLimit = AppConfig.networkWaitLimit,
    DateTime Function()? clock,
  }) : _store = store,
       _api = apiServices,
       _downloadStorage = downloadStorage,
       _network = networkMonitor,
       _notifier = notifier,
       _onChanged = onChanged,
       _clock = clock ?? DateTime.now;

  final TransferStore _store;
  final BaseApiServices? _api;
  final BaseDownloadStorage? _downloadStorage;
  final TransferNetworkMonitor? _network;
  final TransferNotifier? _notifier;
  final void Function()? _onChanged;
  final DateTime Function() _clock;
  final Duration retryBaseDelay;
  final Duration healthTick;
  final Duration offlineAbortAfter;
  final Duration reconnectStallAfter;
  final Duration networkWaitLimit;

  final _tasks = <String, TransferTask>{};
  final _cancelTokens = <String, CancelToken>{};
  final _stopRequests = <String, TransferStatus>{};

  /// Identifies the one run loop allowed to drive each task. A loop that was
  /// superseded (e.g. paused and resumed while it waited) exits instead of
  /// sending a second request for the same transfer.
  final _runs = <String, Object>{};

  /// Wakes a run loop that is waiting (backoff or network) when the task is
  /// paused, cancelled or removed.
  final _wakers = <String, Completer<void>>{};
  final _trackers = <String, ThroughputTracker>{};

  /// Requests aborted because the device went offline and data stopped.
  final _networkAborts = <String>{};

  /// In-flight requests that were running when connectivity was lost.
  final _crossedLoss = <String>{};
  Timer? _healthTimer;
  bool _shutDown = false;
  StreamSubscription<bool>? _networkSubscription;

  bool get _online => _network?.isOnline ?? true;

  bool get _executes => _api != null;

  List<TransferTask> get tasks => _tasks.values.toList()..sort((a, b) => b.createdAt.compareTo(a.createdAt));

  bool get hasActiveWork => _tasks.values.any((task) => task.status.isActive);

  Future<void> restore() async {
    for (final task in await _store.load()) {
      _tasks[task.id] = task.status == TransferStatus.running ? _interrupted(task) : task;
    }
  }

  Future<void> start() async {
    final network = _network;
    if (network != null) {
      await network.start();
      _networkSubscription ??= network.changes.listen(_onConnectivityChanged);
    }
    _pump();
  }

  Future<void> persist() => _store.save(tasks);

  Future<void> apply(TransferCommand command) async {
    final id = command.id;
    switch (command.action) {
      case TransferAction.enqueue:
        for (final task in command.tasks) {
          if (!task.isUpload && _hasOpenDownloadOf(task.serverFileName)) continue;
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
    _shutDown = true;
    _healthTimer?.cancel();
    await _networkSubscription?.cancel();
    for (final task in _tasks.values.toList()) {
      if (task.status != TransferStatus.running) continue;
      _runs.remove(task.id);
      _tasks[task.id] = _interrupted(task);
      _cancelTokens.remove(task.id)?.cancel();
      _wake(task.id);
    }
    await persist();
  }

  TransferTask _interrupted(TransferTask task) => task.isUpload
      ? task.copyWith(status: TransferStatus.failed, transferredBytes: 0, error: 'Upload was interrupted. Retry to upload it again.', networkHealth: NetworkHealth.good, bytesPerSecond: 0)
      : task.copyWith(status: TransferStatus.pending, clearError: true, networkHealth: NetworkHealth.good, bytesPerSecond: 0);

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
    final cancelled = status == TransferStatus.cancelled;
    if (cancelled) await _deletePartial(task);
    _update(task.copyWith(status: status, transferredBytes: cancelled || task.isUpload ? 0 : null, clearError: true, networkHealth: NetworkHealth.good, bytesPerSecond: 0, clearEtag: cancelled));
    _wake(task.id);
  }

  void _pump() {
    if (!_executes || _shutDown) return;
    final pending = _tasks.values.where((task) => task.status == TransferStatus.pending).toList()..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    for (final task in pending) {
      if (_runningCount >= AppConfig.maxConcurrentTransfers) break;
      unawaited(_run(task.id));
    }
  }

  int get _runningCount => _tasks.values.where((task) => task.status == TransferStatus.running).length;

  Future<void> _run(String id) async {
    final run = _runs[id] = Object();
    // Budget for server errors (and for uploads that keep dropping while
    // online, since each retry re-sends the whole file).
    var attempt = 0;
    // Consecutive network failures that moved no data; drives the backoff.
    var networkFailures = 0;
    // When the current network trouble began; reset whenever data moves.
    DateTime? troubleSince;
    var resumed = false;
    _update(_tasks[id]!.copyWith(status: TransferStatus.running, clearError: true, networkHealth: NetworkHealth.good, bytesPerSecond: 0));

    while (_isCurrent(id, run)) {
      // Never send a request while there is no usable network.
      if (!_online) {
        if (await _recover(id, run, deadline: _clock().add(networkWaitLimit)) == null) break;
        resumed = true;
      }
      final task = _tasks[id]!;
      final token = CancelToken();
      _cancelTokens[id] = token;
      _trackers[id] = ThroughputTracker(startBytes: task.isUpload ? 0 : task.transferredBytes, clock: _clock, resumed: resumed);
      _update(
        task.copyWith(
          // An upload restarts from zero; it is never shown as resuming mid-file.
          transferredBytes: task.isUpload ? 0 : null,
          // A retry shows "reconnecting" until its first bytes arrive.
          networkHealth: resumed ? NetworkHealth.reconnecting : NetworkHealth.good,
          bytesPerSecond: 0,
          clearError: true,
        ),
      );
      _startHealthTimer();

      try {
        await (task.isUpload ? _upload(id, token) : _download(id, token));
        _endAttempt(id);
        break;
      } catch (error) {
        final moved = _trackers[id]?.moved ?? false;
        _endAttempt(id);
        final networkAbort = _networkAborts.remove(id);
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
        if (!identical(_runs[id], run)) break;

        final exception = networkAbort
            ? const NetworkException('The connection was lost.')
            : error is AppException
            ? error
            : const AppException('An unexpected error occurred.');
        if (exception is NetworkException) {
          // A connection that was delivering data is retried at once
          // (downloads resume with Range). Only consecutive failures that
          // moved nothing back off, so an unreachable server is not hammered.
          if (moved) {
            networkFailures = 0;
            troubleSince = null;
          }
          troubleSince ??= _clock();
          // Uploads restart from zero, so a link that keeps dropping
          // mid-upload while online uses the retry budget.
          final charged = current.isUpload && moved && _online;
          if (charged) {
            if (attempt >= AppConfig.maxAutoRetries) {
              _fail(current, exception.message);
              break;
            }
            attempt++;
          }
          final delay = _online && networkFailures > 0 ? _backoff(networkFailures - 1) : Duration.zero;
          networkFailures++;
          final wasOffline = await _recover(id, run, delay: delay, deadline: troubleSince.add(networkWaitLimit));
          if (wasOffline == null) break;
          if (wasOffline) {
            // The network came back: try at once. The socket error can arrive
            // before the offline event, so a charged attempt is refunded.
            networkFailures = 0;
            if (charged) attempt--;
          }
          resumed = true;
          continue;
        }

        // Downloads resume from their partial file, so an attempt that made
        // progress resets the budget; only consecutive dead attempts count.
        if (!current.isUpload && current.transferredBytes > task.transferredBytes) {
          attempt = 0;
        }
        if (!exception.retryable || attempt >= AppConfig.maxAutoRetries) {
          _fail(current, exception.message);
          break;
        }
        final delay = _backoff(attempt);
        attempt++;
        _update(
          current.copyWith(
            bytesPerSecond: 0,
            error:
                '${exception.message} Retrying in ${delay.inSeconds}s '
                '($attempt/${AppConfig.maxAutoRetries})',
          ),
        );
        if (!await _sleep(id, run, delay)) break;
      }
    }
    if (identical(_runs[id], run)) _runs.remove(id);
    _pump();
  }

  bool _isCurrent(String id, Object run) => identical(_runs[id], run) && _tasks[id]?.status == TransferStatus.running;

  void _endAttempt(String id) {
    _cancelTokens.remove(id);
    _trackers.remove(id);
    _crossedLoss.remove(id);
  }

  void _fail(TransferTask task, String message) =>
      _update(task.copyWith(status: TransferStatus.failed, transferredBytes: task.isUpload ? 0 : null, error: message, networkHealth: NetworkHealth.good, bytesPerSecond: 0));

  Duration _backoff(int attempt) {
    final delay = retryBaseDelay * (1 << attempt.clamp(0, 16));
    return delay > AppConfig.maxRetryDelay ? AppConfig.maxRetryDelay : delay;
  }

  /// Decides when a transfer that lost its connection is retried, keeping
  /// the last confirmed progress on screen. Offline, it waits for the
  /// network (event driven, no requests). Online, it waits [delay], which
  /// any connectivity change cuts short, so a reconnection is never slept
  /// through. The retried request itself then checks the server. Returns
  /// null when the run should stop (paused, cancelled, superseded or the
  /// network stayed unusable past [deadline]); otherwise whether the device
  /// had to wait for the network.
  Future<bool?> _recover(String id, Object run, {Duration delay = Duration.zero, required DateTime deadline}) async {
    var wasOffline = false;
    if (delay > Duration.zero && _online) {
      _setWaiting(id, NetworkHealth.reconnecting);
      await _wait(id, delay, until: _network?.nextChange());
    }
    while (_isCurrent(id, run) && !_online) {
      final remaining = deadline.difference(_clock());
      if (remaining <= Duration.zero) break;
      wasOffline = true;
      _setWaiting(id, NetworkHealth.offline);
      await _wait(id, remaining, until: _network!.whenOnline());
    }
    if (!_isCurrent(id, run)) return null;
    if (!_online || (!wasOffline && !_clock().isBefore(deadline))) {
      _giveUp(id);
      return null;
    }
    _setWaiting(id, NetworkHealth.reconnecting);
    return wasOffline;
  }

  /// Shows a waiting state. The network status is the health indicator
  /// itself, so no explanatory message is stored.
  void _setWaiting(String id, NetworkHealth health) {
    final task = _tasks[id];
    if (task == null || (task.networkHealth == health && task.error == null && task.bytesPerSecond == 0)) return;
    _update(task.copyWith(networkHealth: health, bytesPerSecond: 0, clearError: true));
  }

  /// The network stayed unusable for [networkWaitLimit]. A download is
  /// paused, keeping its partial file; an upload fails and can be retried.
  void _giveUp(String id) {
    final task = _tasks[id];
    if (task == null) return;
    _runs.remove(id);
    if (task.isUpload) {
      _fail(task, 'Connection lost. Retry to upload again.');
    } else {
      _update(task.copyWith(status: TransferStatus.paused, networkHealth: NetworkHealth.offline, bytesPerSecond: 0, error: 'Paused: connection lost.'));
    }
  }

  /// Sleeps for [delay] unless the task is stopped first. Returns whether
  /// this run should continue.
  Future<bool> _sleep(String id, Object run, Duration delay) async {
    await _wait(id, delay);
    return _isCurrent(id, run);
  }

  /// Completes after [timeout], when the task is woken, or when [until]
  /// completes, whichever is first. The timer is cancelled on early exit.
  Future<void> _wait(String id, Duration timeout, {Future<void>? until}) {
    final done = Completer<void>();
    void finish([Object? _]) {
      if (!done.isCompleted) done.complete();
    }

    final timer = Timer(timeout, finish);
    _wakeSignal(id).then(finish);
    until?.then(finish, onError: finish);
    return done.future.whenComplete(timer.cancel);
  }

  Future<void> _wakeSignal(String id) => (_wakers[id] ??= Completer<void>()).future;

  void _wake(String id) => _wakers.remove(id)?.complete();

  void _onConnectivityChanged(bool online) {
    // Waiting run loops are woken by whenOnline() / nextChange().
    if (!online) {
      // Show the loss immediately; the request itself is aborted by the
      // health check only if data also stops, so brief blips do not kill it.
      for (final id in _cancelTokens.keys) {
        _crossedLoss.add(id);
        final task = _tasks[id];
        if (task != null) _update(task.copyWith(networkHealth: NetworkHealth.offline, bytesPerSecond: 0));
      }
      return;
    }
    for (final id in _cancelTokens.keys.toList()) {
      _abortIfDeadAfterLoss(id);
    }
  }

  /// A request that was in flight when the network was lost is usually tied
  /// to a connection that never delivers again (a few buffered bytes may
  /// still trickle in). Left alone it would hang until the idle timeout, so
  /// once the device is online and the request has been idle for
  /// [reconnectStallAfter] it is aborted and retried on the new connection
  /// (downloads resume with Range). A request whose data keeps flowing
  /// survived the blip and is left alone.
  void _abortIfDeadAfterLoss(String id) {
    final tracker = _trackers[id];
    final token = _cancelTokens[id];
    if (!_online || tracker == null || token == null || !_crossedLoss.contains(id)) return;
    if (tracker.idle < reconnectStallAfter) return;
    _networkAborts.add(id);
    token.cancel('dead after reconnection');
  }

  void _startHealthTimer() => _healthTimer ??= Timer.periodic(healthTick, (_) => _checkHealth());

  /// Re-evaluates every in-flight request once per [healthTick]. Tasks are
  /// only updated when their health or speed actually changes.
  void _checkHealth() {
    if (_cancelTokens.isEmpty) {
      _healthTimer?.cancel();
      _healthTimer = null;
      return;
    }
    for (final entry in _cancelTokens.entries.toList()) {
      final id = entry.key;
      final task = _tasks[id];
      final tracker = _trackers[id];
      if (task == null || tracker == null || task.status != TransferStatus.running) continue;

      final NetworkHealth health;
      final int speed;
      if (!_online) {
        health = NetworkHealth.offline;
        speed = 0;
        if (tracker.idle >= offlineAbortAfter) {
          _networkAborts.add(id);
          entry.value.cancel('offline');
        }
      } else {
        _abortIfDeadAfterLoss(id);
        final finished = task.isUpload && task.totalBytes > 0 && task.transferredBytes >= task.totalBytes;
        health = tracker.classify(task.networkHealth, finished: finished);
        speed = health == NetworkHealth.stalled ? 0 : tracker.bytesPerSecond;
      }
      if (health != task.networkHealth || _speedChanged(task.bytesPerSecond, speed)) {
        _update(task.copyWith(networkHealth: health, bytesPerSecond: speed));
      }
    }
  }

  /// Ignores jitter under 10% so the UI is not rebuilt for noise.
  static bool _speedChanged(int previous, int next) => (next - previous).abs() > (previous ~/ 10) || (previous == 0) != (next == 0);

  Future<void> _upload(String id, CancelToken token) async {
    var task = _tasks[id]!;
    // The previous attempt sent the whole file but its response was lost.
    // Adopt the copy the server already stored instead of uploading again.
    if (task.bodySentAt != null) {
      ServerFileModel? delivered;
      try {
        delivered = await _findDeliveredUpload(task);
      } on AppException catch (e) {
        // Network trouble is retried as usual; anything else (e.g. an
        // unexpected listing error) must not block the upload itself.
        if (e.retryable) rethrow;
      }
      if (delivered != null) {
        _completeUpload(id, name: delivered.name, url: delivered.url);
        return;
      }
      task = _tasks[id]!.copyWith(clearBodySentAt: true);
      _update(task);
    }
    final response = await _api!.uploadFileApi(
      AppUrl.upload,
      filePath: task.localPath,
      fileName: task.fileName,
      cancelToken: token,
      // Multipart framing adds a few bytes, so progress is scaled to the file size.
      onProgress: (sent, total) {
        _progress(id, total > 0 ? (sent * task.totalBytes / total).round() : sent);
        if (total > 0 && sent >= total && _tasks[id]?.bodySentAt == null) {
          _update(_tasks[id]!.copyWith(bodySentAt: _clock()));
        }
      },
    );
    final file = (response as Map<String, dynamic>)['file'] as Map<String, dynamic>;
    _completeUpload(id, name: file['name'] as String?, url: file['url'] as String?);
  }

  void _completeUpload(String id, {String? name, String? url}) {
    final task = _tasks[id]!;
    _update(
      task.copyWith(
        status: TransferStatus.completed,
        transferredBytes: task.totalBytes,
        serverFileName: name,
        remoteUrl: url,
        clearBodySentAt: true,
        networkHealth: NetworkHealth.good,
        bytesPerSecond: 0,
        clearError: true,
      ),
    );
    unawaited(_store.deleteIfTemporary(task.localPath));
  }

  /// The newest server file with the same original name and size, uploaded
  /// after this task last sent its whole body, that no other transfer here
  /// already refers to.
  Future<ServerFileModel?> _findDeliveredUpload(TransferTask task) async {
    final since = task.bodySentAt!.subtract(AppConfig.uploadMatchClockSkew);
    final claimed = _tasks.values.where((other) => other.id != task.id).map((other) => other.serverFileName).whereType<String>().toSet();
    final files = ServerFileModel.listFromJson(await _api!.getGetApiResponse(AppUrl.files));
    final matches = files.where(
      (file) => file.originalName == task.fileName && file.size == task.totalBytes && !claimed.contains(file.name) && file.uploadedAt != null && !file.uploadedAt!.isBefore(since),
    );
    return matches.fold<ServerFileModel?>(null, (best, file) => best == null || file.uploadedAt!.isAfter(best.uploadedAt!) ? file : best);
  }

  Future<void> _download(String id, CancelToken token) async {
    final task = _tasks[id]!;
    await _api!.downloadFileApi(
      AppUrl.fileUrl(task.serverFileName!),
      savePath: task.partialPath,
      cancelToken: token,
      expectedEtag: task.etag,
      onEtag: (etag) {
        final current = _tasks[id];
        if (current != null && current.etag != etag) _update(current.copyWith(etag: etag));
      },
      onProgress: (received, total) => _progress(id, received, total: total > 0 ? total : null),
    );
    // Only a complete file leaves private staging. If publishing fails the
    // full partial file is kept, and a retry publishes it without
    // re-downloading (the Range request answers 416 for a complete file).
    final current = _tasks[id]!;
    final published = await _downloadStorage!.publish(sourcePath: current.partialPath, fileName: current.fileName);
    _update(
      current.copyWith(
        status: TransferStatus.completed,
        localPath: published.path,
        totalBytes: published.size,
        transferredBytes: published.size,
        networkHealth: NetworkHealth.good,
        bytesPerSecond: 0,
        clearEtag: true,
        clearError: true,
      ),
    );
  }

  void _progress(String id, int transferred, {int? total}) {
    final task = _tasks[id];
    if (task == null || task.status != TransferStatus.running) return;
    final tracker = _trackers[id]?..record(transferred);
    // The first bytes after a reconnection end "reconnecting" at once rather
    // than on the next health tick.
    final health = task.networkHealth == NetworkHealth.reconnecting && (tracker?.moved ?? false) ? tracker!.classify(task.networkHealth) : null;
    _update(task.copyWith(transferredBytes: transferred, totalBytes: total, networkHealth: health));
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

  /// Gives each queued download its own staging path, so two downloads of the
  /// same name never share (and corrupt) one partial file.
  String _availablePath(String desired, String ownerId) => FileNames.available(
    desired,
    (path) => File(path).existsSync() || _tasks.values.any((task) => task.id != ownerId && !task.isUpload && task.status != TransferStatus.cancelled && task.localPath == path),
  );

  /// A server file is never downloaded twice at once (queued, running or paused).
  bool _hasOpenDownloadOf(String? serverFileName) => serverFileName != null && _tasks.values.any((task) => !task.isUpload && task.serverFileName == serverFileName && !task.status.isFinished);

  void _trimHistory() {
    final finished = tasks.where((task) => task.status.isFinished).toList();
    for (final task in finished.skip(AppConfig.maxHistory)) {
      _tasks.remove(task.id);
    }
  }
}
