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
  ///
  /// [expectedEtag] is the `ETag` the partial file was downloaded with. New
  /// bytes are appended only when the `206` response starts exactly at the
  /// partial length and the `ETag` is unchanged; otherwise the partial file is
  /// discarded. [onEtag] reports the `ETag` of the response being written.
  Future<void> downloadFileApi(
    String url, {
    required String savePath,
    required TransferProgress onProgress,
    required CancelToken cancelToken,
    String? expectedEtag,
    void Function(String etag)? onEtag,
  });

  /// Whether the API server answers at all (any HTTP status counts). Used
  /// after the network returns, because a connected Wi-Fi or mobile network
  /// does not prove the server can be reached.
  Future<bool> isServerReachable();
}
