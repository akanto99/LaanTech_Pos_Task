import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:laantech_pos_task/configs/res/app_config.dart';
import 'package:laantech_pos_task/configs/res/app_url.dart';
import 'package:laantech_pos_task/data/app_exceptions.dart';
import 'package:laantech_pos_task/data/network/base_api_services.dart';
import 'package:laantech_pos_task/data/network/token_manager.dart';

class NetworkApiService extends BaseApiServices {
  NetworkApiService({Dio? dio, TokenManager? tokenManager}) : _dio = dio ?? Dio(), _tokenManager = tokenManager ?? TokenManager() {
    _dio.options
      ..connectTimeout = AppConfig.connectTimeout
      ..receiveTimeout = AppConfig.apiTimeout;
    _dio.interceptors.add(InterceptorsWrapper(onRequest: _attachToken));
  }

  final Dio _dio;
  final TokenManager _tokenManager;

  /// Set by the UI isolate; fired when an authenticated request is rejected.
  static void Function()? onSessionExpired;

  static const _publicEndpoints = {AppUrl.token, AppUrl.register};
  static const _stalled = 'stalled';
  static const _stalledError = NetworkException('The transfer stalled because the network is too slow or unavailable.');

  Future<void> _attachToken(RequestOptions options, RequestInterceptorHandler handler) async {
    if (!_publicEndpoints.contains(options.uri.toString())) {
      final authorization = await _tokenManager.authorizationHeader;
      if (authorization != null) {
        options.headers[HttpHeaders.authorizationHeader] = authorization;
      }
    }
    handler.next(options);
  }

  @override
  Future<dynamic> getGetApiResponse(String url) => _send(() => _dio.get<dynamic>(url));

  @override
  Future<dynamic> getPostApiResponse(String url, Map<String, dynamic> data) => _send(
    () => _dio.post<dynamic>(
      url,
      data: data,
      options: Options(contentType: Headers.formUrlEncodedContentType),
    ),
  );

  @override
  Future<dynamic> getDeleteApiResponse(String url) => _send(() => _dio.delete<dynamic>(url));

  @override
  Future<dynamic> uploadFileApi(String url, {required String filePath, required String fileName, required TransferProgress onProgress, required CancelToken cancelToken}) async {
    if (!await File(filePath).exists()) {
      throw const InvalidInputException('The selected file is no longer available on this device.');
    }
    final watchdog = _StallWatchdog(cancelToken);
    try {
      final form = FormData.fromMap({'file': await MultipartFile.fromFile(filePath, filename: fileName)});
      return await _send(
        () => _dio.post<dynamic>(
          url,
          data: form,
          cancelToken: cancelToken,
          onSendProgress: (sent, total) {
            watchdog.touch();
            onProgress(sent, total);
          },
        ),
      );
    } finally {
      watchdog.stop();
    }
  }

  @override
  Future<void> downloadFileApi(
    String url, {
    required String savePath,
    required TransferProgress onProgress,
    required CancelToken cancelToken,
    String? expectedEtag,
    void Function(String etag)? onEtag,
  }) async {
    final file = File(savePath);
    var offset = await file.exists() ? await file.length() : 0;
    // If-Range needs a strong validator; a weak one would make it always fail.
    final ifRange = offset > 0 && expectedEtag != null && !expectedEtag.startsWith('W/') ? expectedEtag : null;
    try {
      final response = await _dio.get<ResponseBody>(
        url,
        cancelToken: cancelToken,
        options: Options(
          responseType: ResponseType.stream,
          headers: {
            if (offset > 0) HttpHeaders.rangeHeader: 'bytes=$offset-',
            // The server sends the whole file (200) if it changed since.
            HttpHeaders.ifRangeHeader: ?ifRange,
          },
          validateStatus: (code) => code == HttpStatus.ok || code == HttpStatus.partialContent || (code == HttpStatus.requestedRangeNotSatisfiable && offset > 0),
        ),
      );

      if (response.statusCode == HttpStatus.requestedRangeNotSatisfiable) {
        if (_totalFromContentRange(response) == offset) {
          _discardBody(response);
          onProgress(offset, offset);
          return;
        }
        await file.delete();
        throw const FetchDataException('The partial download was invalid and will restart.');
      }
      final etag = response.headers.value(HttpHeaders.etagHeader);
      if (response.statusCode == HttpStatus.partialContent) {
        // Never append unless the server confirms the exact byte range
        // requested, from the same version of the file.
        final range = _parseContentRange(response);
        final changed = expectedEtag != null && etag != null && etag != expectedEtag;
        if (range == null || range.start != offset || changed) {
          _discardBody(response);
          await file.delete();
          throw FetchDataException(changed ? 'The file changed on the server. The download will restart.' : 'The server returned an unexpected byte range. The download will restart.');
        }
      }
      if (response.statusCode == HttpStatus.ok) offset = 0;
      if (etag != null) onEtag?.call(etag);

      final total = _totalFromContentRange(response) ?? _contentLength(response, offset);
      final sink = file.openWrite(mode: offset == 0 ? FileMode.writeOnly : FileMode.writeOnlyAppend);
      var received = offset;
      try {
        await for (final chunk in response.data!.stream.timeout(AppConfig.transferIdleTimeout)) {
          sink.add(chunk);
          received += chunk.length;
          onProgress(received, total);
        }
        await sink.flush();
      } finally {
        await sink.close();
      }
      if (total > 0 && received < total) {
        throw const FetchDataException('The download ended early and will resume from where it stopped.');
      }
    } on DioException catch (e) {
      throw _mapDioException(e);
    } on TimeoutException {
      throw _stalledError;
    } on FileSystemException catch (e) {
      throw _mapFileSystemException(e);
    } on IOException {
      // A dropped connection mid-body surfaces as a raw socket/HTTP error
      // from the response stream rather than a DioException.
      throw const NetworkException('The connection was interrupted. The download will resume.');
    }
  }

  @override
  Future<bool> supportsRangeRequests(String url) async {
    final cancelToken = CancelToken();
    try {
      final response = await _dio.get<ResponseBody>(
        url,
        cancelToken: cancelToken,
        options: Options(responseType: ResponseType.stream, headers: {HttpHeaders.rangeHeader: 'bytes=0-1'}),
      );
      // Only the status and headers matter; drop the body (the whole file on a 200).
      unawaited(response.data?.stream.listen(null, onError: (_) {}).cancel());
      return response.statusCode == HttpStatus.partialContent && response.headers.value(HttpHeaders.contentRangeHeader) != null;
    } on DioException catch (e) {
      throw _mapDioException(e);
    } finally {
      cancelToken.cancel();
    }
  }

  Future<dynamic> _send(Future<Response<dynamic>> Function() request) async {
    try {
      return (await request()).data;
    } on DioException catch (e) {
      throw _mapDioException(e);
    }
  }

  /// `Content-Range: bytes <start>-<end>/<total|*>`.
  ({int start, int end})? _parseContentRange(Response<dynamic> response) {
    final match = RegExp(r'^bytes (\d+)-(\d+)/(\d+|\*)$').firstMatch(response.headers.value(HttpHeaders.contentRangeHeader)?.trim() ?? '');
    if (match == null) return null;
    return (start: int.parse(match[1]!), end: int.parse(match[2]!));
  }

  void _discardBody(Response<ResponseBody> response) => unawaited(response.data?.stream.listen(null, onError: (_) {}).cancel());

  int? _totalFromContentRange(Response<dynamic> response) {
    final range = response.headers.value(HttpHeaders.contentRangeHeader);
    return range == null ? null : int.tryParse(range.split('/').last);
  }

  int _contentLength(Response<dynamic> response, int offset) {
    final length = int.tryParse(response.headers.value(HttpHeaders.contentLengthHeader) ?? '');
    return length == null ? -1 : offset + length;
  }

  AppException _mapDioException(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.transformTimeout:
        return const NetworkException('The connection timed out. Please check your network and try again.');
      case DioExceptionType.connectionError:
        return const NetworkException('No internet connection. Please check your network.');
      case DioExceptionType.cancel:
        return e.error == _stalled ? _stalledError : const CancelledException();
      case DioExceptionType.badResponse:
        return _mapStatus(e.response!, e.requestOptions);
      case DioExceptionType.badCertificate:
        return const BadRequestException('The server certificate is not trusted.');
      case DioExceptionType.unknown:
        final error = e.error;
        if (error is AppException) return error;
        if (error is FileSystemException) return _mapFileSystemException(error);
        if (error is SocketException) {
          return const NetworkException('No internet connection. Please check your network.');
        }
        return const NetworkException('The connection was interrupted. Please try again.');
    }
  }

  AppException _mapStatus(Response<dynamic> response, RequestOptions request) {
    final code = response.statusCode ?? 0;
    final data = response.data;
    final serverMessage = data is Map ? data['error'] as String? : null;

    if (code == HttpStatus.unauthorized || code == HttpStatus.forbidden) {
      if (request.headers.containsKey(HttpHeaders.authorizationHeader)) {
        onSessionExpired?.call();
        return const UnauthorisedException();
      }
      return UnauthorisedException(serverMessage ?? 'Invalid credentials.');
    }
    if (code == HttpStatus.notFound) {
      return BadRequestException(serverMessage ?? 'The requested file was not found on the server.');
    }
    if (code == HttpStatus.requestEntityTooLarge) {
      return const BadRequestException('The file is too large for the server.');
    }
    if (code == HttpStatus.unsupportedMediaType) {
      return BadRequestException(serverMessage ?? 'This file type is not supported by the server.');
    }
    if (code == HttpStatus.requestTimeout || code == HttpStatus.tooManyRequests || code >= HttpStatus.internalServerError) {
      return FetchDataException('Server is temporarily unavailable ($code). Please try again later.');
    }
    return BadRequestException(serverMessage ?? 'Request failed ($code).');
  }

  AppException _mapFileSystemException(FileSystemException e) {
    const noSpaceErrorCode = 28;
    if (e.osError?.errorCode == noSpaceErrorCode) {
      return const StorageException('Not enough storage space on this device.');
    }
    return StorageException('Could not access the file: ${e.message}');
  }
}

/// Dio's sendTimeout spans the whole request body, which would abort large
/// uploads on slow links, so stalls are detected from progress events instead.
class _StallWatchdog {
  _StallWatchdog(CancelToken token) {
    _timer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (DateTime.now().difference(_lastActivity) > AppConfig.transferIdleTimeout) {
        token.cancel(NetworkApiService._stalled);
      }
    });
  }

  late final Timer _timer;
  DateTime _lastActivity = DateTime.now();

  void touch() => _lastActivity = DateTime.now();

  void stop() => _timer.cancel();
}
