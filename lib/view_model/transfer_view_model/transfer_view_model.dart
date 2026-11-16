import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:laantech_pos_task/data/app_exceptions.dart';
import 'package:laantech_pos_task/model/server_file/server_file_model.dart';
import 'package:laantech_pos_task/model/transfer/transfer_command.dart';
import 'package:laantech_pos_task/model/transfer/transfer_task.dart';
import 'package:laantech_pos_task/repository/transfer_repository/transfer_repository.dart';

/// App-wide mirror of the background transfer queue. Transfers execute in the
/// foreground service; this view model only reflects and controls them.
class TransferViewModel with ChangeNotifier, WidgetsBindingObserver {
  TransferViewModel({TransferRepository? repository}) : _repository = repository ?? TransferRepository() {
    _repository.attach();
    _updatesSubscription = _repository.updates.listen(_setTasks);
    WidgetsBinding.instance.addObserver(this);
    refresh();
  }

  final TransferRepository _repository;
  late final StreamSubscription<List<TransferTask>> _updatesSubscription;

  List<TransferTask> _tasks = const [];
  bool _picking = false;

  List<TransferTask> get tasks => _tasks;
  List<TransferTask> get uploads => _tasks.where((t) => t.isUpload).toList();
  List<TransferTask> get activeTasks => _tasks.where((t) => t.status.isActive).toList();
  bool get picking => _picking;
  Stream<void> get openRequests => _repository.openRequests;

  int count(TransferStatus status) => _tasks.where((task) => task.status == status).length;

  int get activeCount => activeTasks.length;

  double get activeProgress {
    final active = activeTasks.where((task) => task.totalBytes > 0);
    final total = active.fold<int>(0, (sum, task) => sum + task.totalBytes);
    final done = active.fold<int>(0, (sum, task) => sum + task.transferredBytes);
    return total > 0 ? done / total : 0;
  }

  TransferTask? byId(String id) => _tasks.where((task) => task.id == id).firstOrNull;

  TransferTask? latestDownloadOf(String serverFileName) => _tasks.where((t) => !t.isUpload && t.serverFileName == serverFileName).firstOrNull;

  Future<void> refresh() async => _setTasks(await _repository.loadTasks());

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) refresh();
  }

  /// Returns a user-facing message about skipped files or errors, if any.
  Future<String?> pickAndUpload() async {
    if (_picking) return null;
    _picking = true;
    notifyListeners();
    try {
      final selection = await _repository.pickUploads();
      if (selection.accepted.isNotEmpty) {
        await _repository.dispatch(TransferCommand(TransferAction.enqueue, tasks: selection.accepted));
      }
      return selection.rejected.isEmpty ? null : 'Skipped unsupported or empty files: ${selection.rejected.join(', ')}';
    } catch (error) {
      return _message(error);
    } finally {
      _picking = false;
      notifyListeners();
    }
  }

  Future<String?> download(ServerFileModel file) async {
    try {
      final task = await _repository.createDownload(file);
      await _repository.dispatch(TransferCommand(TransferAction.enqueue, tasks: [task]));
      return null;
    } catch (error) {
      return _message(error);
    }
  }

  Future<String?> pause(String id) => _send(TransferAction.pause, id);
  Future<String?> resume(String id) => _send(TransferAction.resume, id);
  Future<String?> retry(String id) => _send(TransferAction.retry, id);
  Future<String?> cancel(String id) => _send(TransferAction.cancel, id);
  Future<String?> remove(String id) => _send(TransferAction.remove, id);
  Future<String?> clearFinished() => _send(TransferAction.clearFinished);

  /// Cancels everything and clears history, e.g. on logout.
  Future<String?> reset() => _send(TransferAction.reset);

  Future<String?> _send(TransferAction action, [String? id]) async {
    try {
      await _repository.dispatch(TransferCommand(action, id: id));
      return null;
    } catch (error) {
      return _message(error);
    }
  }

  void _setTasks(List<TransferTask> tasks) {
    _tasks = tasks;
    notifyListeners();
  }

  String _message(Object error) => error is AppException ? error.message : 'Something went wrong. Please try again.';

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _updatesSubscription.cancel();
    _repository.detach();
    super.dispose();
  }
}
