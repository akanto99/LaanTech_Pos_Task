import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:laantech_pos_task/configs/services/connectivity_services/connectivity_service.dart';
import 'package:laantech_pos_task/data/app_exceptions.dart';
import 'package:laantech_pos_task/data/response/status.dart';
import 'package:laantech_pos_task/model/server_file/server_file_model.dart';
import 'package:laantech_pos_task/repository/file_repository/file_repository.dart';
import 'package:laantech_pos_task/view_model/server_files_view_model/server_files_view_model.dart';

const _offline = FetchDataException('No internet connection. Please check your network.');

ServerFileModel _file(String name) => ServerFileModel(id: name.hashCode, name: name, originalName: name, size: 1, type: 'text/csv', uploadedAt: null, url: '');

/// Each fetch pops the next scripted result; a [Completer] holds the request open.
class FakeFileRepository implements FileRepository {
  final results = <Object>[];
  int fetchCalls = 0;

  @override
  Future<List<ServerFileModel>> fetchFiles() async {
    fetchCalls++;
    final result = results.removeAt(0);
    if (result is Completer<List<ServerFileModel>>) return result.future;
    if (result is AppException) throw result;
    return result as List<ServerFileModel>;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class FakeConnectivityService implements ConnectivityService {
  final controller = StreamController<bool>.broadcast();
  bool online = true;
  bool get hasListener => controller.hasListener;

  void emit(bool value) {
    online = value;
    controller.add(value);
  }

  @override
  Stream<bool> get onlineChanges => controller.stream;

  @override
  Future<bool> get isOnline async => online;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeFileRepository repository;
  late FakeConnectivityService connectivity;
  late ServerFilesViewModel viewModel;

  ServerFilesViewModel create({List<Duration> retryDelays = const [Duration(milliseconds: 10), Duration(milliseconds: 10)]}) =>
      ServerFilesViewModel(repository: repository, connectivity: connectivity, retryDelays: retryDelays);

  Future<void> pump([int ms = 1]) => Future<void>.delayed(Duration(milliseconds: ms));

  setUp(() {
    repository = FakeFileRepository();
    connectivity = FakeConnectivityService();
  });

  test('reloads automatically when the connection returns', () async {
    repository.results.addAll([_offline, [_file('a.csv')]]);
    viewModel = create(retryDelays: const []);
    connectivity.emit(false);
    await viewModel.fetchFiles();

    expect(viewModel.files.status, Status.error);
    expect(viewModel.recoversAutomatically, isTrue);

    connectivity.emit(true);
    await pump();

    expect(viewModel.files.status, Status.completed);
    expect(viewModel.files.data!.single.name, 'a.csv');
    expect(repository.fetchCalls, 2);
    viewModel.dispose();
  });

  test('does not poll while offline', () async {
    repository.results.add(_offline);
    viewModel = create();
    connectivity.emit(false);
    await viewModel.fetchFiles();
    await pump(50);

    expect(repository.fetchCalls, 1);
    viewModel.dispose();
  });

  test('retries with backoff when connected but the API is unreachable', () async {
    repository.results.addAll([_offline, _offline, [_file('a.csv')]]);
    viewModel = create();
    connectivity.emit(true);
    await viewModel.fetchFiles();
    await pump(60);

    expect(repository.fetchCalls, 3);
    expect(viewModel.files.status, Status.completed);
    viewModel.dispose();
  });

  test('gives up after the retry budget and keeps a retry button', () async {
    repository.results.addAll([_offline, _offline, _offline]);
    viewModel = create();
    await viewModel.fetchFiles();
    await pump(60);

    expect(repository.fetchCalls, 3);
    expect(viewModel.files.status, Status.error);
    viewModel.dispose();
  });

  test('permanent errors are not retried automatically', () async {
    repository.results.add(const BadRequestException('Request failed (400).'));
    viewModel = create();
    await viewModel.fetchFiles();
    connectivity.emit(false);
    connectivity.emit(true);
    await pump(50);

    expect(repository.fetchCalls, 1);
    expect(viewModel.recoversAutomatically, isFalse);
    viewModel.dispose();
  });

  test('concurrent reloads share a single request', () async {
    final pending = Completer<List<ServerFileModel>>();
    repository.results.add(pending);
    viewModel = create();

    final first = viewModel.fetchFiles();
    final second = viewModel.fetchFiles(silent: true);
    connectivity.emit(true);
    pending.complete([_file('a.csv')]);
    await Future.wait([first, second]);

    expect(repository.fetchCalls, 1);
    viewModel.dispose();
  });

  test('refreshes a list loaded before an outage without hiding it on failure', () async {
    repository.results.addAll([
      [_file('a.csv')],
      _offline,
    ]);
    viewModel = create(retryDelays: const []);
    await viewModel.fetchFiles();
    connectivity.emit(false);
    connectivity.emit(true);
    await pump();

    expect(repository.fetchCalls, 2);
    expect(viewModel.files.status, Status.completed);
    expect(viewModel.files.data!.single.name, 'a.csv');
    viewModel.dispose();
  });

  test('dispose cancels the subscription and pending retries', () async {
    repository.results.addAll([_offline, [_file('a.csv')]]);
    viewModel = create(retryDelays: const [Duration(milliseconds: 20)]);
    await viewModel.fetchFiles();
    expect(connectivity.hasListener, isTrue);

    viewModel.dispose();
    await pump(50);

    expect(connectivity.hasListener, isFalse);
    expect(repository.fetchCalls, 1);
  });

  test('a request finishing after dispose does not throw', () async {
    final pending = Completer<List<ServerFileModel>>();
    repository.results.add(pending);
    viewModel = create();
    final request = viewModel.fetchFiles();
    viewModel.dispose();
    pending.complete([_file('a.csv')]);

    await expectLater(request, completes);
  });
}
