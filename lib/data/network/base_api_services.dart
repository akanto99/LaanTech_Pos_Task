import 'package:dio/dio.dart';

typedef TransferProgress = void Function(int transferred, int total);

abstract class BaseApiServices {
  Future<dynamic> getGetApiResponse(String url);

  Future<dynamic> getPostApiResponse(String url, Map<String, dynamic> data);

  Future<dynamic> getDeleteApiResponse(String url);

  /// Streams [filePath] from disk as multipart field `file`.
  Future<dynamic> uploadFileApi(
    String url, {
    required String filePath,
    required String fileName,
    required TransferProgress onProgress,
    required CancelToken cancelToken,
  });

  /// Whether [url] answers a `Range` request with `206 Partial Content`, which
  /// is what lets a media player stream and seek without the whole file.
  Future<bool> supportsRangeRequests(String url);

  /// Downloads into [savePath], resuming from its current length with an
  /// HTTP Range request when the file already exists.
  Future<void> downloadFileApi(
    String url, {
    required String savePath,
    required TransferProgress onProgress,
    required CancelToken cancelToken,
  });
}
