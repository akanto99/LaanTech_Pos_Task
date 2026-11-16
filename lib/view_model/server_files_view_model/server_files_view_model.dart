import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:laantech_pos_task/configs/res/app_config.dart';
import 'package:laantech_pos_task/configs/services/connectivity_services/connectivity_service.dart';
import 'package:laantech_pos_task/data/app_exceptions.dart';
import 'package:laantech_pos_task/data/response/api_response.dart';
import 'package:laantech_pos_task/data/response/status.dart';
import 'package:laantech_pos_task/model/server_file/server_file_model.dart';
import 'package:laantech_pos_task/repository/file_repository/file_repository.dart';

/// Server file listing. Recovers on its own from network failures: it reloads
/// when connectivity returns or the app resumes, and retries a reload that
/// still fails (connected is not the same as reachable) with a short backoff.
class ServerFilesViewModel with ChangeNotifier, WidgetsBindingObserver {
  ServerFilesViewModel({FileRepository? repository, ConnectivityService? connectivity, List<Duration> retryDelays = AppConfig.reconnectRetryDelays})
    : _repository = repository ?? FileRepository(),
      _connectivity = connectivity ?? ConnectivityService(),
      _retryDelays = retryDelays {
    _connectivitySubscription = _connectivity.onlineChanges.listen(_onConnectivityChanged);
    WidgetsBinding.instance.addObserver(this);
  }

  final FileRepository _repository;
  final ConnectivityService _connectivity;
  final List<Duration> _retryDelays;
  late final StreamSubscription<bool> _connectivitySubscription;

  ApiResponse<List<ServerFileModel>> files = const ApiResponse.loading();
  final Set<String> _deleting = {};

  Future<void>? _inFlight;
  Timer? _retryTimer;
  int _retryAttempt = 0;
  bool? _online;
  bool _errorIsTransient = false;
  bool _disposed = false;

  bool isDeleting(String name) => _deleting.contains(name);

  /// The current error is a network-type failure that will be retried
  /// automatically once the connection is back.
  bool get recoversAutomatically => files.status == Status.error && _errorIsTransient;

  /// Concurrent calls (manual refresh, reconnect, retry timer) share one request.
  Future<void> fetchFiles({bool silent = false}) => _inFlight ??= _load(silent: silent).whenComplete(() => _inFlight = null);

  Future<void> _load({required bool silent, bool keepDataOnError = false}) async {
    _cancelRetry();
    if (!silent) {
      files = const ApiResponse.loading();
      _notify();
    }
    try {
      files = ApiResponse.completed(await _repository.fetchFiles());
      _errorIsTransient = false;
      _retryAttempt = 0;
    } catch (error) {
      if (keepDataOnError && files.status == Status.completed) return;
      _errorIsTransient = error is AppException && error.retryable;
      files = ApiResponse.error(_message(error));
      _scheduleRetry();
    }
    _notify();
  }

  void _onConnectivityChanged(bool online) {
    final wasOffline = _online == false;
    _online = online;
    if (!online) {
      _cancelRetry();
      return;
    }
    if (recoversAutomatically) {
      _retryAttempt = 0;
      fetchFiles();
    } else if (wasOffline && files.status == Status.completed && _inFlight == null) {
      // Refresh a list loaded before the outage, without hiding it.
      _inFlight = _load(silent: true, keepDataOnError: true).whenComplete(() => _inFlight = null);
    }
  }

  /// Connectivity events can be missed while the app is in the background.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed || !recoversAutomatically || _inFlight != null) return;
    _connectivity.isOnline.then((online) {
      if (online && !_disposed) {
        _retryAttempt = 0;
        fetchFiles();
      }
    });
  }

  void _scheduleRetry() {
    // Offline: wait for the connectivity event instead of polling.
    if (!_errorIsTransient || _online == false || _retryAttempt >= _retryDelays.length || _disposed) return;
    _retryTimer = Timer(_retryDelays[_retryAttempt++], () {
      _retryTimer = null;
      if (_online != false) fetchFiles();
    });
  }

  void _cancelRetry() {
    _retryTimer?.cancel();
    _retryTimer = null;
  }

  /// Returns a user-facing error message, or `null` on success.
  Future<String?> deleteFile(ServerFileModel file) async {
    _deleting.add(file.name);
    _notify();
    try {
      await _repository.deleteFile(file.name);
      files = ApiResponse.completed(files.data!.where((item) => item.name != file.name).toList());
      return null;
    } catch (error) {
      return _message(error);
    } finally {
      _deleting.remove(file.name);
      _notify();
    }
  }

  String _message(Object error) => error is AppException ? error.message : 'Something went wrong. Please try again.';

  /// Requests can finish after the screen was closed; never notify then.
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _cancelRetry();
    _connectivitySubscription.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}
