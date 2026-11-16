import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:laantech_pos_task/data/app_exceptions.dart';
import 'package:laantech_pos_task/data/response/api_response.dart';
import 'package:laantech_pos_task/model/video/video_player_args.dart';
import 'package:laantech_pos_task/model/video/video_source.dart';
import 'package:laantech_pos_task/repository/video_repository/video_repository.dart';
import 'package:video_player/video_player.dart';

typedef VideoControllerFactory = VideoPlayerController Function(VideoSource source);

/// Opens a server video: authenticated Range streaming first, then a
/// download-first fallback when the server cannot stream or the stream fails.
class VideoPlayerViewModel with ChangeNotifier {
  VideoPlayerViewModel({required this.video, VideoRepository? repository, VideoControllerFactory? controllerFactory})
    : _repository = repository ?? VideoRepository(),
      _createController = controllerFactory ?? _defaultController;

  final VideoPlayerArgs video;
  final VideoRepository _repository;
  final VideoControllerFactory _createController;

  static const unsupportedMessage = 'This video cannot be played on this device. Its format or codec may not be supported.';

  ApiResponse<VideoPlayerController> player = const ApiResponse.loading();

  /// True while the download-first fallback is fetching the file.
  bool downloading = false;

  /// Fallback download progress (0-1), or null when the size is unknown.
  double? downloadProgress;

  CancelToken? _cancelToken;
  bool _loading = false;
  bool _disposed = false;

  VideoPlayerController? get controller => player.data;

  Future<void> load() async {
    if (_loading || _disposed) return;
    _loading = true;
    await _releaseController();
    player = const ApiResponse.loading();
    _notify();
    try {
      final stream = await _repository.streamSource(video.serverFileName);
      if (stream != null && await _open(stream)) return;
      if (_disposed) return;

      downloading = true;
      downloadProgress = null;
      _notify();
      _cancelToken = CancelToken();
      final file = await _repository.download(video.serverFileName, cancelToken: _cancelToken!, onProgress: _onDownloadProgress);
      downloading = false;
      if (!await _open(file)) player = const ApiResponse.error(unsupportedMessage);
    } on CancelledException {
      return;
    } catch (error) {
      player = ApiResponse.error(error is AppException ? error.message : 'The video could not be loaded. Please try again.');
    } finally {
      downloading = false;
      _loading = false;
      _notify();
    }
  }

  /// Returns false if the platform player rejects the source.
  Future<bool> _open(VideoSource source) async {
    final controller = _createController(source);
    try {
      await controller.initialize();
    } catch (_) {
      await controller.dispose();
      return false;
    }
    if (_disposed) {
      await controller.dispose();
      return true;
    }
    player = ApiResponse.completed(controller);
    unawaited(controller.play());
    return true;
  }

  void _onDownloadProgress(double? progress) {
    final changed = progress == null || downloadProgress == null || (progress * 100).floor() != (downloadProgress! * 100).floor();
    downloadProgress = progress;
    if (changed) _notify();
  }

  Future<void> _releaseController() async {
    final current = controller;
    player = const ApiResponse.loading();
    await current?.dispose();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  static VideoPlayerController _defaultController(VideoSource source) => switch (source) {
    NetworkVideoSource(:final uri, :final headers) => VideoPlayerController.networkUrl(uri, httpHeaders: headers),
    FileVideoSource(:final file) => VideoPlayerController.file(file),
  };

  @override
  void dispose() {
    _disposed = true;
    _cancelToken?.cancel();
    controller?.dispose();
    unawaited(_repository.discardDownload(video.serverFileName));
    super.dispose();
  }
}
