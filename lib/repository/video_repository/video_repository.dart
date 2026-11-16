import 'dart:io';

import 'package:dio/dio.dart';
import 'package:laantech_pos_task/configs/res/app_url.dart';
import 'package:laantech_pos_task/data/app_exceptions.dart';
import 'package:laantech_pos_task/data/network/base_api_services.dart';
import 'package:laantech_pos_task/data/network/network_api_service.dart';
import 'package:laantech_pos_task/data/network/token_manager.dart';
import 'package:laantech_pos_task/model/video/video_source.dart';
import 'package:path_provider/path_provider.dart';

class VideoRepository {
  VideoRepository({BaseApiServices? apiServices, TokenManager? tokenManager, Future<Directory> Function()? cacheDirectory})
    : _api = apiServices ?? NetworkApiService(),
      _tokenManager = tokenManager ?? TokenManager(),
      _cacheDirectory = cacheDirectory ?? getTemporaryDirectory;

  final BaseApiServices _api;
  final TokenManager _tokenManager;
  final Future<Directory> Function() _cacheDirectory;

  /// An authenticated, seekable stream of the server file, or `null` when the
  /// server does not honour Range requests (the caller then downloads first).
  /// The probe goes through the shared API client, so a rejected token
  /// triggers the usual session-expired flow.
  Future<NetworkVideoSource?> streamSource(String serverFileName) async {
    final url = AppUrl.fileUrl(serverFileName);
    if (!await _api.supportsRangeRequests(url)) return null;
    final authorization = await _tokenManager.authorizationHeader;
    if (authorization == null) throw const UnauthorisedException();
    return NetworkVideoSource(Uri.parse(url), headers: {HttpHeaders.authorizationHeader: authorization});
  }

  /// Download-first fallback into the app cache. Uses the same resumable
  /// download as the transfer engine; a cached copy is reused.
  Future<FileVideoSource> download(String serverFileName, {required CancelToken cancelToken, required void Function(double? progress) onProgress}) async {
    final file = await _cacheFile(serverFileName);
    if (await file.exists()) return FileVideoSource(file);
    final partial = '${file.path}.part';
    await _api.downloadFileApi(
      AppUrl.fileUrl(serverFileName),
      savePath: partial,
      cancelToken: cancelToken,
      onProgress: (received, total) => onProgress(total > 0 ? received / total : null),
    );
    return FileVideoSource(await File(partial).rename(file.path));
  }

  /// Deletes the fallback copy (and any partial data) once playback ends.
  Future<void> discardDownload(String serverFileName) async {
    final file = await _cacheFile(serverFileName);
    for (final path in [file.path, '${file.path}.part']) {
      try {
        await File(path).delete();
      } on FileSystemException {
        // Not there or already gone.
      }
    }
  }

  Future<File> _cacheFile(String serverFileName) async {
    final directory = await Directory('${(await _cacheDirectory()).path}/video_playback').create(recursive: true);
    return File('${directory.path}/${serverFileName.replaceAll(RegExp(r'[\\/]'), '_')}');
  }
}
