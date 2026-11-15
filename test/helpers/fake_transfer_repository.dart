import 'dart:async';

import 'package:laantech_pos_task/model/server_file/server_file_model.dart';
import 'package:laantech_pos_task/model/transfer/transfer_command.dart';
import 'package:laantech_pos_task/model/transfer/transfer_task.dart';
import 'package:laantech_pos_task/repository/transfer_repository/transfer_repository.dart';

TransferTask buildTask(
  String id, {
  TransferType type = TransferType.upload,
  TransferStatus status = TransferStatus.running,
  int total = 1000,
  int transferred = 250,
  String? serverFileName,
  String? error,
}) => TransferTask(
  id: id,
  type: type,
  fileName: '$id.csv',
  localPath: '/tmp/$id.csv',
  totalBytes: total,
  transferredBytes: transferred,
  status: status,
  createdAt: DateTime(2026, 1, 1),
  updatedAt: DateTime(2026, 1, 1),
  serverFileName: serverFileName,
  error: error,
);

class FakeTransferRepository implements TransferRepository {
  final controller = StreamController<List<TransferTask>>.broadcast();
  final commands = <TransferCommand>[];
  List<TransferTask> stored = [];
  UploadSelection selection = (
    accepted: <TransferTask>[],
    rejected: <String>[],
  );

  @override
  Stream<List<TransferTask>> get updates => controller.stream;

  @override
  Stream<void> get openRequests => const Stream.empty();

  @override
  void attach() {}

  @override
  void detach() {}

  @override
  Future<List<TransferTask>> loadTasks() async => stored;

  @override
  Future<void> dispatch(TransferCommand command) async => commands.add(command);

  @override
  Future<UploadSelection> pickUploads() async => selection;

  @override
  Future<TransferTask> createDownload(ServerFileModel file) async => buildTask(
    'download-${file.id}',
    type: TransferType.download,
    status: TransferStatus.pending,
    serverFileName: file.name,
  );
}
