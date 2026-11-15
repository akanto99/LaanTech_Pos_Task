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

  /// Downloads into [savePath], resuming from its current length with an
  /// HTTP Range request when the file already exists.
  Future<void> downloadFileApi(
    String url, {
    required String savePath,
    required TransferProgress onProgress,
    required CancelToken cancelToken,
  });
}
