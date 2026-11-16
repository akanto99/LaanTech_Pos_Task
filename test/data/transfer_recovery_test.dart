import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:laantech_pos_task/data/app_exceptions.dart';
import 'package:laantech_pos_task/data/network/base_api_services.dart';
import 'package:laantech_pos_task/data/storage/base_download_storage.dart';
import 'package:laantech_pos_task/data/transfer/transfer_manager.dart';
import 'package:laantech_pos_task/data/transfer/transfer_network_monitor.dart';
import 'package:laantech_pos_task/data/transfer/transfer_store.dart';
import 'package:laantech_pos_task/model/transfer/network_health.dart';
import 'package:laantech_pos_task/model/transfer/transfer_command.dart';
import 'package:laantech_pos_task/model/transfer/transfer_task.dart';

import '../helpers/fake_connectivity_service.dart';

typedef _Attempt = Future<Object?> Function(TransferProgress onProgress, CancelToken token, String? savePath);

/// Each upload/download call runs the next scripted attempt.
class _ScriptedApi implements BaseApiServices {
  final uploads = <_Attempt>[];
  final downloads = <_Attempt>[];
  List<Map<String, Object?>> serverFiles = [];
  int uploadCalls = 0;
  int downloadCalls = 0;
  int listCalls = 0;

  @override
  Future<dynamic> uploadFileApi(String url, {required String filePath, required String fileName, required TransferProgress onProgress, required CancelToken cancelToken}) {
    uploadCalls++;
    return uploads.removeAt(0)(onProgress, cancelToken, null);
  }

  @override
  Future<void> downloadFileApi(
    String url, {
    required String savePath,
    required TransferProgress onProgress,
    required CancelToken cancelToken,
    String? expectedEtag,
    void Function(String etag)? onEtag,
  }) async {
    downloadCalls++;
    await downloads.removeAt(0)(onProgress, cancelToken, savePath);
  }

  @override
  Future<dynamic> getGetApiResponse(String url) async {
    listCalls++;
    return {'files': serverFiles};
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class _Storage implements BaseDownloadStorage {
  _Storage(this.directory);
  final Directory directory;

  @override
  Future<PublishedDownload> publish({required String sourcePath, required String fileName}) async {
    directory.createSync(recursive: true);
    final file = File(sourcePath).renameSync('${directory.path}/$fileName');
    return (path: file.path, size: file.lengthSync());
  }

  @override
  Future<bool> ensureWriteAccess() async => true;
}

/// Appends [bytes] to the partial file and reports progress out of 10.
Future<void> _write(String path, List<int> bytes, TransferProgress onProgress) async {
  final file = File(path)..writeAsBytesSync(bytes, mode: FileMode.append);
  onProgress(file.lengthSync(), 10);
}

/// Keeps the request open until it is cancelled (a dead connection).
Future<Never> _hangUntilCancelled(CancelToken token) async {
  await token.whenCancel;
  throw const CancelledException();
}

void main() {
  late Directory root;
  late _ScriptedApi api;
  late FakeConnectivityService connectivity;
  late TransferNetworkMonitor monitor;
  late TransferManager manager;
  late List<TransferTask> history;

  TransferManager create({
    Duration networkWaitLimit = const Duration(minutes: 1),
    Duration retryBaseDelay = const Duration(milliseconds: 1),
    Duration offlineAbortAfter = const Duration(milliseconds: 30),
    Duration reconnectStallAfter = const Duration(milliseconds: 30),
  }) => TransferManager(
    store: TransferStore(dataDirectory: () async => root, temporaryDirectory: () async => Directory('${root.path}/cache')),
    apiServices: api,
    downloadStorage: _Storage(Directory('${root.path}/public')),
    networkMonitor: monitor,
    retryBaseDelay: retryBaseDelay,
    healthTick: const Duration(milliseconds: 5),
    offlineAbortAfter: offlineAbortAfter,
    reconnectStallAfter: reconnectStallAfter,
    networkWaitLimit: networkWaitLimit,
  );

  /// Replaces the manager with one using slow timings, to prove recovery
  /// does not wait for them.
  Future<void> recreate({Duration retryBaseDelay = const Duration(minutes: 10), Duration offlineAbortAfter = const Duration(minutes: 10)}) async {
    await manager.shutdown();
    manager = create(retryBaseDelay: retryBaseDelay, offlineAbortAfter: offlineAbortAfter);
    await manager.start();
  }

  TransferTask task(String id) => manager.tasks.firstWhere((t) => t.id == id);

  TransferTask upload(String id) => TransferTask(
    id: id,
    type: TransferType.upload,
    fileName: 'promo.mp4',
    localPath: '${root.path}/promo.mp4',
    totalBytes: 1000,
    transferredBytes: 0,
    status: TransferStatus.pending,
    createdAt: DateTime.now(),
    updatedAt: DateTime.now(),
  );

  TransferTask download(String id) => TransferTask(
    id: id,
    type: TransferType.download,
    fileName: 'catalog.csv',
    localPath: '${root.path}/catalog.csv',
    totalBytes: 10,
    transferredBytes: 0,
    status: TransferStatus.pending,
    createdAt: DateTime.now(),
    updatedAt: DateTime.now(),
    serverFileName: 'catalog_ab12.csv',
  );

  Future<void> until(bool Function() condition, {String reason = 'condition'}) async {
    for (var i = 0; i < 400; i++) {
      if (condition()) return;
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    fail('timed out waiting for $reason');
  }

  Future<void> enqueue(TransferTask t) => manager.apply(TransferCommand(TransferAction.enqueue, tasks: [t]));

  setUp(() async {
    root = await Directory.systemTemp.createTemp('recovery');
    api = _ScriptedApi();
    connectivity = FakeConnectivityService();
    monitor = TransferNetworkMonitor(connectivity: connectivity);
    history = [];
    manager = create();
    await manager.start();
  });

  tearDown(() async {
    await manager.shutdown();
    await monitor.dispose();
    await root.delete(recursive: true);
  });

  void recordHistory() {
    manager = TransferManager(
      store: TransferStore(dataDirectory: () async => root, temporaryDirectory: () async => Directory('${root.path}/cache')),
      apiServices: api,
      downloadStorage: _Storage(Directory('${root.path}/public')),
      networkMonitor: monitor,
      retryBaseDelay: const Duration(milliseconds: 1),
      healthTick: const Duration(milliseconds: 5),
      offlineAbortAfter: const Duration(milliseconds: 30),
      onChanged: () => history.addAll(manager.tasks),
    );
  }

  test('offline: nothing is sent; the request goes out as soon as the network returns', () async {
    await recreate();
    connectivity.emit(false);
    await pumpEventQueue();
    api.downloads.add((onProgress, _, path) => _write(path!, List.filled(10, 1), onProgress));

    await enqueue(download('d1'));
    await until(() => task('d1').networkHealth == NetworkHealth.offline, reason: 'offline');
    expect(task('d1').status, TransferStatus.running, reason: 'stays visible as an active transfer');
    expect(task('d1').error, isNull, reason: 'the status indicator is the only message');
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(api.downloadCalls, 0, reason: 'no requests while there is no network');

    // No probe and no backoff (10 minutes here) before the retry.
    connectivity.emit(true);
    await until(() => task('d1').status == TransferStatus.completed, reason: 'completion');
    expect(api.downloadCalls, 1);
    expect(File(task('d1').localPath).lengthSync(), 10);
  });

  test('online but unreachable: retries back off, and a network change cuts the backoff short', () async {
    await recreate(); // 10-minute base backoff
    for (var i = 0; i < 2; i++) {
      api.downloads.add((_, _, _) async => throw const NetworkException('Connection refused.'));
    }
    api.downloads.add((onProgress, _, path) => _write(path!, List.filled(10, 1), onProgress));

    await enqueue(download('d1'));
    // The first failure retries at once; the second waits for the backoff.
    await until(() => api.downloadCalls == 2 && task('d1').networkHealth == NetworkHealth.reconnecting, reason: 'backing off');
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(api.downloadCalls, 2, reason: 'consecutive failures that move no data back off');

    // Switching networks (e.g. Wi-Fi to mobile and back) retries immediately.
    connectivity.emit(false);
    await pumpEventQueue();
    connectivity.emit(true);
    await until(() => task('d1').status == TransferStatus.completed, reason: 'completion');
    expect(api.downloadCalls, 3);
  });

  test('short outage: a dead request is aborted on reconnection and resumes at once from its byte offset', () async {
    // Idle timeout, offline abort and backoff are all 10 minutes here: the
    // resume must not wait for any of them.
    await recreate();
    final drained = Completer<void>();
    api.downloads
      ..add((onProgress, token, path) async {
        await _write(path!, List.filled(3, 1), onProgress);
        // Bytes already buffered are still read after the loss is reported…
        await drained.future;
        await _write(path, List.filled(1, 1), onProgress);
        return _hangUntilCancelled(token); // …then the old connection never delivers again
      })
      ..add((onProgress, _, path) async {
        expect(File(path!).lengthSync(), 4, reason: 'Range resume from the kept partial file');
        await _write(path, List.filled(6, 2), onProgress);
        return null;
      });

    await enqueue(download('d1'));
    await until(() => task('d1').transferredBytes == 3, reason: 'first bytes');
    connectivity.emit(false);
    await until(() => task('d1').networkHealth == NetworkHealth.offline, reason: 'offline shown');
    drained.complete();
    await until(() => task('d1').transferredBytes == 4, reason: 'buffered bytes');
    connectivity.emit(true);
    await until(() => task('d1').status == TransferStatus.completed, reason: 'prompt resume');
    expect(api.downloadCalls, 2);
    expect(File(task('d1').localPath).readAsBytesSync(), [...List.filled(4, 1), ...List.filled(6, 2)]);
  });

  test('a blip that does not stop the data leaves the request alone', () async {
    await recreate();
    final finish = Completer<void>();
    api.downloads.add((onProgress, token, path) async {
      await _write(path!, List.filled(4, 1), onProgress);
      await finish.future;
      await _write(path, List.filled(6, 1), onProgress);
      return null;
    });

    await enqueue(download('d1'));
    await until(() => task('d1').transferredBytes == 4, reason: 'first bytes');
    connectivity.emit(false);
    await pumpEventQueue();
    // Data keeps arriving during the blip, so the connection survived.
    finish.complete();
    await until(() => task('d1').transferredBytes == 10, reason: 'data during blip');
    connectivity.emit(true);
    await until(() => task('d1').status == TransferStatus.completed, reason: 'completion');
    expect(api.downloadCalls, 1);
  });

  test('connection lost mid-download: progress is kept and the Range resume continues it', () async {
    recordHistory();
    await manager.start();
    String? partial;
    api.downloads
      ..add((onProgress, token, path) async {
        partial = path;
        await _write(path!, List.filled(4, 1), onProgress);
        return _hangUntilCancelled(token); // the socket dies silently
      })
      ..add((onProgress, _, path) async {
        // The real API sends Range: bytes=<partial length>-.
        expect(File(path!).lengthSync(), 4);
        await _write(path, List.filled(6, 2), onProgress);
        return null;
      });

    await enqueue(download('d1'));
    await until(() => task('d1').transferredBytes == 4, reason: 'first bytes');

    connectivity.emit(false);
    await until(() => task('d1').networkHealth == NetworkHealth.offline, reason: 'offline shown');
    await Future<void>.delayed(const Duration(milliseconds: 80)); // past offlineAbortAfter
    expect(task('d1').transferredBytes, 4, reason: 'last confirmed progress is preserved');
    expect(task('d1').status, TransferStatus.running);
    expect(api.downloadCalls, 1);

    connectivity.emit(true);
    await until(() => task('d1').status == TransferStatus.completed, reason: 'completion');
    expect(api.downloadCalls, 2);
    expect(File(task('d1').localPath).readAsBytesSync(), [...List.filled(4, 1), ...List.filled(6, 2)]);
    expect(File(partial!).existsSync(), isFalse);

    final progress = history.where((t) => t.id == 'd1').map((t) => t.transferredBytes).toList();
    for (var i = 1; i < progress.length; i++) {
      expect(progress[i], greaterThanOrEqualTo(progress[i - 1]), reason: 'download progress never goes backwards');
    }
    expect(history.where((t) => t.id == 'd1').map((t) => t.networkHealth), containsAllInOrder([NetworkHealth.offline, NetworkHealth.reconnecting]));
    expect(history.where((t) => t.id == 'd1').map((t) => t.error), everyElement(isNull), reason: 'no explanatory messages');
  });

  test('connection lost mid-upload: progress is kept while waiting, then the upload honestly restarts from zero', () async {
    recordHistory();
    await manager.start();
    api.uploads
      ..add((onProgress, token, _) async {
        onProgress(600, 1000);
        return _hangUntilCancelled(token);
      })
      ..add((onProgress, _, _) async {
        onProgress(1000, 1000);
        return {
          'file': {'name': 'promo_x1.mp4', 'url': 'u'},
        };
      });

    await enqueue(upload('u1'));
    await until(() => task('u1').transferredBytes == 600, reason: 'upload progress');
    connectivity.emit(false);
    await until(() => task('u1').networkHealth == NetworkHealth.offline, reason: 'offline');
    await Future<void>.delayed(const Duration(milliseconds: 80)); // past offlineAbortAfter
    expect(task('u1').transferredBytes, 600, reason: 'progress is not reset while waiting');
    expect(api.uploadCalls, 1);

    connectivity.emit(true);
    await until(() => task('u1').status == TransferStatus.completed, reason: 'completion');
    expect(api.uploadCalls, 2);
    expect(task('u1').serverFileName, 'promo_x1.mp4');
    final progress = history.where((t) => t.id == 'u1').map((t) => t.transferredBytes).toList();
    expect(progress, containsAllInOrder([600, 0, 1000]), reason: 'the restart is shown as starting again from 0');
  });

  test('a lost upload response does not create a duplicate server file', () async {
    final sentAt = DateTime.now();
    api.uploads.add((onProgress, _, _) async {
      onProgress(1000, 1000); // the server received everything…
      throw const NetworkException('The connection was interrupted.'); // …but the response was lost
    });
    api.serverFiles = [
      {'id': 1, 'name': 'promo_old.mp4', 'original_name': 'promo.mp4', 'size': 1000, 'uploaded_at': sentAt.subtract(const Duration(days: 1)).toUtc().toIso8601String(), 'url': 'old'},
      {'id': 2, 'name': 'promo_new.mp4', 'original_name': 'promo.mp4', 'size': 1000, 'uploaded_at': sentAt.toUtc().toIso8601String(), 'url': 'new'},
    ];

    await enqueue(upload('u1'));
    await until(() => task('u1').status == TransferStatus.completed, reason: 'completion');
    expect(api.uploadCalls, 1, reason: 'the file is not uploaded twice');
    expect(api.listCalls, 1);
    expect(task('u1').serverFileName, 'promo_new.mp4');
    expect(task('u1').bodySentAt, isNull);
  });

  test('upload progress stops at 99% until the server confirms the upload', () async {
    recordHistory();
    await manager.start();
    final respond = Completer<Object?>();
    api.uploads.add((onProgress, _, _) async {
      onProgress(1000, 1000); // every byte written to the socket
      return respond.future;
    });

    await enqueue(upload('u1'));
    await until(() => task('u1').bodySentAt != null, reason: 'body sent');
    expect(task('u1').transferredBytes, 999);
    expect(task('u1').percent, 99, reason: 'written is not accepted');
    respond.complete({
      'file': {'name': 'promo_x3.mp4', 'url': 'u'},
    });
    await until(() => task('u1').status == TransferStatus.completed, reason: 'completion');
    expect(task('u1').percent, 100);
  });

  test('a lost upload with no matching server file is uploaded again', () async {
    api.uploads
      ..add((onProgress, _, _) async {
        onProgress(1000, 1000);
        throw const NetworkException('The connection was interrupted.');
      })
      ..add((onProgress, _, _) async {
        onProgress(1000, 1000);
        return {
          'file': {'name': 'promo_x2.mp4', 'url': 'u'},
        };
      });

    await enqueue(upload('u1'));
    await until(() => task('u1').status == TransferStatus.completed, reason: 'completion');
    expect(api.uploadCalls, 2);
    expect(task('u1').serverFileName, 'promo_x2.mp4');
  });

  test('pausing and resuming while waiting for the network never sends two requests', () async {
    connectivity.emit(false);
    await pumpEventQueue();
    final release = Completer<void>();
    api.downloads.add((onProgress, _, path) async {
      await release.future;
      await _write(path!, List.filled(10, 1), onProgress);
      return null;
    });

    await enqueue(download('d1'));
    await until(() => task('d1').networkHealth == NetworkHealth.offline, reason: 'waiting');
    await manager.apply(const TransferCommand(TransferAction.pause, id: 'd1'));
    expect(task('d1').status, TransferStatus.paused);
    await manager.apply(const TransferCommand(TransferAction.resume, id: 'd1'));
    expect(task('d1').status, TransferStatus.running);

    connectivity.emit(true);
    await until(() => api.downloadCalls == 1, reason: 'request');
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(api.downloadCalls, 1, reason: 'the superseded wait must not start its own request');
    release.complete();
    await until(() => task('d1').status == TransferStatus.completed, reason: 'completion');
  });

  test('network failures while offline do not use up the retry budget', () async {
    var attempts = 0;
    for (var i = 0; i < 8; i++) {
      api.downloads.add((onProgress, token, path) async {
        attempts++;
        connectivity.emit(false);
        throw const NetworkException('No internet connection.');
      });
    }
    api.downloads.add((onProgress, _, path) => _write(path!, List.filled(10, 1), onProgress));

    await enqueue(download('d1'));
    while (task('d1').status == TransferStatus.running && attempts < 8) {
      final before = attempts;
      await until(() => task('d1').networkHealth == NetworkHealth.offline || task('d1').status != TransferStatus.running, reason: 'offline');
      connectivity.emit(true);
      await until(() => attempts > before || task('d1').status != TransferStatus.running, reason: 'next attempt');
    }
    expect(task('d1').status, TransferStatus.running, reason: 'eight drops, more than the retry limit, and it is still waiting');
    await until(() => task('d1').networkHealth == NetworkHealth.offline, reason: 'offline');
    connectivity.emit(true);
    await until(() => task('d1').status == TransferStatus.completed, reason: 'completion');
    expect(attempts, 8);
  });

  test('a download waiting too long is paused due to connection loss; an upload fails', () async {
    await manager.shutdown();
    manager = create(networkWaitLimit: const Duration(milliseconds: 60));
    await manager.start();
    connectivity.emit(false);
    await pumpEventQueue();

    await enqueue(download('d1'));
    await enqueue(upload('u1'));
    await until(() => !task('d1').status.isActive && !task('u1').status.isActive, reason: 'give up');

    expect(task('d1').status, TransferStatus.paused);
    expect(task('d1').networkHealth, NetworkHealth.offline);
    expect(task('d1').error, contains('connection lost'));
    expect(task('u1').status, TransferStatus.failed);
    expect(task('u1').error, contains('Connection lost'));
    expect(api.downloadCalls + api.uploadCalls, 0);
  });

  test('the same server file cannot be queued for download twice', () async {
    connectivity.emit(false);
    await pumpEventQueue();
    await enqueue(download('d1'));
    await enqueue(download('d2'));
    expect(manager.tasks.map((t) => t.id), ['d1']);
  });
}
