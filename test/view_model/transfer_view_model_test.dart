import 'package:flutter_test/flutter_test.dart';
import 'package:laantech_pos_task/model/server_file/server_file_model.dart';
import 'package:laantech_pos_task/model/transfer/transfer_command.dart';
import 'package:laantech_pos_task/model/transfer/transfer_task.dart';
import 'package:laantech_pos_task/view_model/transfer_view_model/transfer_view_model.dart';

import '../helpers/fake_transfer_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeTransferRepository repository;
  late TransferViewModel viewModel;

  setUp(() async {
    repository = FakeTransferRepository();
    viewModel = TransferViewModel(repository: repository);
    await Future<void>.delayed(Duration.zero);
  });

  tearDown(() => viewModel.dispose());

  test('mirrors snapshots pushed by the background service', () async {
    repository.controller.add([
      buildTask('a', transferred: 500),
      buildTask('b', status: TransferStatus.pending, transferred: 0),
      buildTask('c', status: TransferStatus.completed, transferred: 1000),
      buildTask(
        'd',
        status: TransferStatus.failed,
        type: TransferType.download,
      ),
    ]);
    await Future<void>.delayed(Duration.zero);

    expect(viewModel.activeCount, 2);
    expect(viewModel.count(TransferStatus.completed), 1);
    expect(viewModel.count(TransferStatus.failed), 1);
    expect(viewModel.uploads.length, 3);
    expect(viewModel.activeProgress, closeTo(0.25, 0.001));
  });

  test('queues accepted uploads and reports skipped files', () async {
    repository.selection = (
      accepted: [buildTask('a', status: TransferStatus.pending)],
      rejected: ['virus.exe'],
    );

    final message = await viewModel.pickAndUpload();

    expect(repository.commands.single.action, TransferAction.enqueue);
    expect(repository.commands.single.tasks.single.id, 'a');
    expect(message, contains('virus.exe'));
    expect(viewModel.picking, isFalse);
  });

  test('download enqueues a task referencing the server file', () async {
    const file = ServerFileModel(
      id: 7,
      name: 'report_ab12.pdf',
      originalName: 'report.pdf',
      size: 2048,
      type: 'application/pdf',
      uploadedAt: null,
      url: 'http://host/get?file=report_ab12.pdf',
    );

    expect(await viewModel.download(file), isNull);
    final task = repository.commands.single.tasks.single;
    expect(task.type, TransferType.download);
    expect(task.serverFileName, 'report_ab12.pdf');
  });

  test('controls dispatch the matching command', () async {
    await viewModel.pause('x');
    await viewModel.resume('x');
    await viewModel.retry('x');
    await viewModel.cancel('x');
    await viewModel.reset();

    expect(repository.commands.map((c) => c.action), [
      TransferAction.pause,
      TransferAction.resume,
      TransferAction.retry,
      TransferAction.cancel,
      TransferAction.reset,
    ]);
  });

  test('finds the latest download of a server file', () async {
    repository.controller.add([
      buildTask('new', type: TransferType.download, serverFileName: 'f.zip'),
      buildTask('old', type: TransferType.download, serverFileName: 'f.zip'),
    ]);
    await Future<void>.delayed(Duration.zero);

    expect(viewModel.latestDownloadOf('f.zip')?.id, 'new');
    expect(viewModel.latestDownloadOf('other.zip'), isNull);
  });
}
