import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:laantech_pos_task/configs/res/app_config.dart';
import 'package:laantech_pos_task/data/app_exceptions.dart';
import 'package:laantech_pos_task/data/network/base_api_services.dart';
import 'package:laantech_pos_task/data/transfer/transfer_manager.dart';
import 'package:laantech_pos_task/data/transfer/transfer_store.dart';
import 'package:laantech_pos_task/model/transfer/transfer_command.dart';
import 'package:laantech_pos_task/model/transfer/transfer_task.dart';

/// Scripted API: each call pops the next behaviour from the queue.
class FakeTransferApi implements BaseApiServices {
  final uploadResults = <Object>[];
  final downloadResults = <Object>[];
  int uploadCalls = 0;
  int downloadCalls = 0;
  Completer<void>? hold;
  void Function(String savePath)? onDownload;

  @override
  Future<dynamic> uploadFileApi(
    String url, {
    required String filePath,
    required String fileName,
    required TransferProgress onProgress,
    required CancelToken cancelToken,
  }) async {
    uploadCalls++;
    onProgress(50, 100);
    final result = uploadResults.removeAt(0);
    if (result is AppException) throw result;
    return result;
  }

  @override
  Future<void> downloadFileApi(
    String url, {
    required String savePath,
    required TransferProgress onProgress,
    required CancelToken cancelToken,
  }) async {
    downloadCalls++;
    final file = File(savePath);
    if (onDownload != null) {
      onDownload!(savePath);
      onProgress(file.lengthSync(), 10);
      final result = downloadResults.isEmpty
          ? null
          : downloadResults.removeAt(0);
      if (result is AppException) throw result;
      return;
    }
    final offset = file.existsSync() ? file.lengthSync() : 0;
    file.writeAsBytesSync(List.filled(5, 1), mode: FileMode.append);
    onProgress(offset + 5, 10);
    if (hold != null) {
      await Future.any([hold!.future, cancelToken.whenCancel]);
      if (cancelToken.isCancelled) throw const CancelledException();
    }
    final result = downloadResults.isEmpty ? null : downloadResults.removeAt(0);
    if (result is AppException) throw result;
    file.writeAsBytesSync(
      List.filled(10 - file.lengthSync(), 2),
      mode: FileMode.append,
    );
    onProgress(10, 10);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

void main() {
  late Directory root;
  late FakeTransferApi api;
  late TransferStore store;
  late TransferManager manager;

  TransferTask upload(String id) => TransferTask(
    id: id,
    type: TransferType.upload,
    fileName: 'catalog.csv',
    localPath: '${root.path}/catalog.csv',
    totalBytes: 1000,
    transferredBytes: 0,
    status: TransferStatus.pending,
    createdAt: DateTime.now(),
    updatedAt: DateTime.now(),
  );

  TransferTask download(String id, {String name = 'report.pdf'}) =>
      TransferTask(
        id: id,
        type: TransferType.download,
        fileName: name,
        localPath: '${root.path}/$name',
        totalBytes: 10,
        transferredBytes: 0,
        status: TransferStatus.pending,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        serverFileName: 'report_ab12.pdf',
      );

  TransferManager createManager() => TransferManager(
    store: store,
    apiServices: api,
    retryBaseDelay: const Duration(milliseconds: 1),
  );

  Future<TransferTask> settle(String id) async {
    for (var i = 0; i < 200; i++) {
      final task = manager.tasks.firstWhere((t) => t.id == id);
      if (!task.status.isActive) return task;
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    fail('transfer $id did not settle');
  }

  Future<void> enqueue(TransferTask task) =>
      manager.apply(TransferCommand(TransferAction.enqueue, tasks: [task]));

  setUp(() async {
    root = await Directory.systemTemp.createTemp('transfers');
    api = FakeTransferApi();
    store = TransferStore(
      dataDirectory: () async => root,
      temporaryDirectory: () async => Directory('${root.path}/cache'),
    );
    manager = createManager();
  });

  tearDown(() => root.delete(recursive: true));

  test('successful upload stores the server file reference', () async {
    api.uploadResults.add({
      'file': {
        'name': 'catalog_0b40.csv',
        'url': 'http://host/get?file=catalog_0b40.csv',
      },
    });
    await enqueue(upload('u1'));

    final task = await settle('u1');
    expect(task.status, TransferStatus.completed);
    expect(task.serverFileName, 'catalog_0b40.csv');
    expect(task.transferredBytes, 1000);
  });

  test(
    'temporary picker copies are deleted after upload, user files kept',
    () async {
      final cache = Directory('${root.path}/cache')..createSync();
      final picked = File('${cache.path}/catalog.csv')..writeAsStringSync('x');
      final userFile = File('${root.path}/catalog.csv')..writeAsStringSync('x');
      api.uploadResults.addAll([
        {
          'file': {'name': 'a.csv', 'url': 'u'},
        },
        {
          'file': {'name': 'b.csv', 'url': 'u'},
        },
      ]);

      await enqueue(upload('u1').copyWith(localPath: picked.path));
      await settle('u1');
      await enqueue(upload('u2'));
      await settle('u2');
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(picked.existsSync(), isFalse);
      expect(userFile.existsSync(), isTrue);
    },
  );

  test('transient upload failures are retried with backoff', () async {
    api.uploadResults.addAll([
      const FetchDataException('No internet connection.'),
      const FetchDataException('No internet connection.'),
      {
        'file': {'name': 'ok.csv', 'url': 'u'},
      },
    ]);
    await enqueue(upload('u1'));

    expect((await settle('u1')).status, TransferStatus.completed);
    expect(api.uploadCalls, 3);
  });

  test('retries stop after the configured limit', () async {
    api.uploadResults.addAll(
      List.filled(
        AppConfig.maxAutoRetries + 1,
        const FetchDataException('Timed out.'),
      ),
    );
    await enqueue(upload('u1'));

    final task = await settle('u1');
    expect(task.status, TransferStatus.failed);
    expect(task.error, 'Timed out.');
    expect(api.uploadCalls, AppConfig.maxAutoRetries + 1);
  });

  test('permanent errors are not retried', () async {
    api.uploadResults.add(const BadRequestException('File type not allowed'));
    await enqueue(upload('u1'));

    final task = await settle('u1');
    expect(task.status, TransferStatus.failed);
    expect(api.uploadCalls, 1);
  });

  test('manual retry restarts a failed upload from zero', () async {
    api.uploadResults.addAll([
      const BadRequestException('Server rejected'),
      {
        'file': {'name': 'ok.csv', 'url': 'u'},
      },
    ]);
    await enqueue(upload('u1'));
    await settle('u1');

    await manager.apply(const TransferCommand(TransferAction.retry, id: 'u1'));
    expect((await settle('u1')).status, TransferStatus.completed);
  });

  test('uploads cannot be paused', () async {
    api.uploadResults.add({
      'file': {'name': 'ok.csv', 'url': 'u'},
    });
    await enqueue(upload('u1'));
    await manager.apply(const TransferCommand(TransferAction.pause, id: 'u1'));

    expect((await settle('u1')).status, TransferStatus.completed);
  });

  test(
    'downloads that keep progressing are not abandoned by the retry limit',
    () async {
      var calls = 0;
      api.downloadResults.addAll(
        List.generate(
          AppConfig.maxAutoRetries + 3,
          (_) => const FetchDataException('Connection reset.'),
        ),
      );
      api.onDownload = (savePath) {
        calls++;
        File(savePath).writeAsBytesSync([1], mode: FileMode.append);
      };
      await enqueue(download('d1'));

      final task = await settle('d1');
      expect(task.status, TransferStatus.completed);
      expect(calls, AppConfig.maxAutoRetries + 4);
    },
  );

  test('download pauses and resumes from the partial file', () async {
    api.hold = Completer();
    await enqueue(download('d1'));
    await Future<void>.delayed(const Duration(milliseconds: 10));

    await manager.apply(const TransferCommand(TransferAction.pause, id: 'd1'));
    final paused = await settle('d1');
    expect(paused.status, TransferStatus.paused);
    expect(File(paused.partialPath).lengthSync(), 5);

    api.hold = null;
    await manager.apply(const TransferCommand(TransferAction.resume, id: 'd1'));
    final done = await settle('d1');
    expect(done.status, TransferStatus.completed);
    expect(File(done.localPath).lengthSync(), 10);
    expect(File(done.partialPath).existsSync(), isFalse);
  });

  test('cancelling a download deletes its partial file', () async {
    api.hold = Completer();
    await enqueue(download('d1'));
    await Future<void>.delayed(const Duration(milliseconds: 10));

    await manager.apply(const TransferCommand(TransferAction.cancel, id: 'd1'));
    final task = await settle('d1');
    expect(task.status, TransferStatus.cancelled);
    expect(File(task.partialPath).existsSync(), isFalse);
  });

  test('existing file names are never overwritten', () async {
    File('${root.path}/report.pdf').writeAsStringSync('existing');
    await enqueue(download('d1'));
    await enqueue(download('d2'));

    final first = await settle('d1');
    final second = await settle('d2');
    expect(first.localPath, '${root.path}/report (1).pdf');
    expect(second.localPath, '${root.path}/report (2).pdf');
    expect(File('${root.path}/report.pdf').readAsStringSync(), 'existing');
  });

  test(
    'restore resumes interrupted downloads and fails interrupted uploads',
    () async {
      await store.save([
        upload('u1').copyWith(status: TransferStatus.running),
        download('d1').copyWith(status: TransferStatus.running),
        download('d2', name: 'b.pdf').copyWith(status: TransferStatus.paused),
      ]);

      final offline = TransferManager(store: store);
      await offline.restore();
      final byId = {for (final task in offline.tasks) task.id: task};

      expect(byId['u1']!.status, TransferStatus.failed);
      expect(byId['d1']!.status, TransferStatus.pending);
      expect(byId['d2']!.status, TransferStatus.paused);
    },
  );

  test('a non-executing manager only records commands', () async {
    final offline = TransferManager(store: store);
    await offline.apply(
      TransferCommand(TransferAction.enqueue, tasks: [upload('u1')]),
    );
    await offline.persist();

    expect(offline.hasActiveWork, isTrue);
    expect(api.uploadCalls, 0);
    expect((await store.load()).single.status, TransferStatus.pending);
  });

  test('clear finished keeps active and paused transfers', () async {
    api.uploadResults.add(const BadRequestException('rejected'));
    await enqueue(upload('u1'));
    await settle('u1');
    api.hold = Completer();
    await enqueue(download('d1'));
    await Future<void>.delayed(const Duration(milliseconds: 10));

    await manager.apply(const TransferCommand(TransferAction.clearFinished));
    expect(manager.tasks.map((t) => t.id), ['d1']);
    api.hold!.complete();
    await settle('d1');
  });
}
