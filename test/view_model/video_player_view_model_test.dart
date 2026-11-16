import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:laantech_pos_task/data/app_exceptions.dart';
import 'package:laantech_pos_task/data/response/status.dart';
import 'package:laantech_pos_task/model/video/video_player_args.dart';
import 'package:laantech_pos_task/model/video/video_source.dart';
import 'package:laantech_pos_task/repository/video_repository/video_repository.dart';
import 'package:laantech_pos_task/view_model/video_player_view_model/video_player_view_model.dart';
import 'package:video_player/video_player.dart';

/// Never touches the platform player.
class FakeVideoController extends VideoPlayerController {
  FakeVideoController(this.source, {this.fails = false}) : super.networkUrl(Uri.parse('https://example.invalid/video.mp4'));

  final VideoSource source;
  final bool fails;
  bool played = false;
  bool disposed = false;

  @override
  Future<void> initialize() async {
    if (fails) throw PlatformException(code: 'VideoError', message: 'Source error');
    value = value.copyWith(isInitialized: true, duration: const Duration(minutes: 1));
  }

  @override
  Future<void> play() async => played = true;

  @override
  Future<void> dispose() async {
    disposed = true;
    await super.dispose();
  }
}

class FakeVideoRepository implements VideoRepository {
  NetworkVideoSource? stream = NetworkVideoSource(Uri.parse('http://host/get?file=clip.mp4'), headers: const {'authorization': 'Bearer jwt'});
  Object? streamError;
  Completer<FileVideoSource>? downloadResult;
  CancelToken? downloadToken;
  int downloads = 0;
  final discarded = <String>[];

  @override
  Future<NetworkVideoSource?> streamSource(String serverFileName) async {
    if (streamError != null) throw streamError!;
    return stream;
  }

  @override
  Future<FileVideoSource> download(String serverFileName, {required CancelToken cancelToken, required void Function(double? progress) onProgress}) {
    downloads++;
    downloadToken = cancelToken;
    onProgress(0.5);
    return (downloadResult ??= Completer()..complete(FileVideoSource(File('/cache/clip.mp4')))).future;
  }

  @override
  Future<void> discardDownload(String serverFileName) async => discarded.add(serverFileName);
}

void main() {
  late FakeVideoRepository repository;
  late List<FakeVideoController> controllers;
  late Set<Type> failingSources;

  VideoPlayerViewModel create() => VideoPlayerViewModel(
    video: const VideoPlayerArgs(serverFileName: 'clip.mp4', title: 'clip.mp4'),
    repository: repository,
    controllerFactory: (source) {
      final controller = FakeVideoController(source, fails: failingSources.contains(source.runtimeType));
      controllers.add(controller);
      return controller;
    },
  );

  setUp(() {
    repository = FakeVideoRepository();
    controllers = [];
    failingSources = {};
  });

  test('streams with Range and authenticated headers when supported', () async {
    final vm = create();
    await vm.load();

    expect(vm.player.status, Status.completed);
    final source = controllers.single.source as NetworkVideoSource;
    expect(source.headers['authorization'], 'Bearer jwt');
    expect(controllers.single.played, isTrue);
    expect(repository.downloads, 0);
    vm.dispose();
  });

  test('downloads first when the server cannot stream', () async {
    repository.stream = null;
    final vm = create();
    await vm.load();

    expect(vm.player.status, Status.completed);
    expect(controllers.single.source, isA<FileVideoSource>());
    expect(repository.downloads, 1);
    vm.dispose();
  });

  test('falls back to a download when streaming fails to start', () async {
    failingSources = {NetworkVideoSource};
    final vm = create();
    await vm.load();

    expect(vm.player.status, Status.completed);
    expect(controllers.map((c) => c.source.runtimeType), [NetworkVideoSource, FileVideoSource]);
    expect(controllers.first.disposed, isTrue);
    vm.dispose();
  });

  test('reports unsupported formats when no source can be played', () async {
    failingSources = {NetworkVideoSource, FileVideoSource};
    final vm = create();
    await vm.load();

    expect(vm.player.status, Status.error);
    expect(vm.player.message, VideoPlayerViewModel.unsupportedMessage);
    expect(controllers.every((c) => c.disposed), isTrue);
    vm.dispose();
  });

  test('surfaces API errors such as an expired session', () async {
    repository.streamError = const UnauthorisedException();
    final vm = create();
    await vm.load();

    expect(vm.player.status, Status.error);
    expect(vm.player.message, const UnauthorisedException().message);
    vm.dispose();
  });

  test('shows fallback download progress', () async {
    repository.stream = null;
    repository.downloadResult = Completer();
    final vm = create();
    unawaited(vm.load());
    await Future<void>.delayed(Duration.zero);

    expect(vm.downloading, isTrue);
    expect(vm.downloadProgress, 0.5);
    repository.downloadResult!.complete(FileVideoSource(File('/cache/clip.mp4')));
    await Future<void>.delayed(Duration.zero);
    vm.dispose();
  });

  test('dispose cancels the fallback download and releases resources', () async {
    final vm = create();
    await vm.load();
    vm.dispose();
    expect(controllers.single.disposed, isTrue);
    expect(repository.discarded, ['clip.mp4']);

    repository.stream = null;
    repository.downloadResult = Completer();
    final pending = create();
    unawaited(pending.load());
    await Future<void>.delayed(Duration.zero);
    pending.dispose();
    expect(repository.downloadToken!.isCancelled, isTrue);
  });
}
