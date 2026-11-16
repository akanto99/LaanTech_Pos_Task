import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:laantech_pos_task/data/app_exceptions.dart';
import 'package:laantech_pos_task/data/network/network_api_service.dart';
import 'package:laantech_pos_task/data/network/token_manager.dart';

class _FakeTokenManager extends TokenManager {
  _FakeTokenManager(this._token);
  final String? _token;

  @override
  Future<String?> get token async => _token;
}

class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter(this.respond);
  final ResponseBody Function(RequestOptions options) respond;
  final requests = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? body,
    Future<void>? cancel,
  ) async {
    requests.add(options);
    return respond(options);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody _json(int status, Object body) => ResponseBody.fromString(
  jsonEncode(body),
  status,
  headers: {
    Headers.contentTypeHeader: [Headers.jsonContentType],
  },
);

extension<T> on Stream<T> {
  Stream<T> followedBy(Object error) async* {
    yield* this;
    throw error;
  }
}

void main() {
  late Directory root;

  setUp(() async => root = await Directory.systemTemp.createTemp('network'));
  tearDown(() => root.delete(recursive: true));

  NetworkApiService service(_FakeAdapter adapter, {String? token = 'jwt'}) =>
      NetworkApiService(
        dio: Dio()..httpClientAdapter = adapter,
        tokenManager: _FakeTokenManager(token),
      );

  test('attaches the bearer token to protected endpoints only', () async {
    final adapter = _FakeAdapter((_) => _json(200, {'success': true}));
    final api = service(adapter);

    await api.getGetApiResponse('http://108.136.142.112:90/get');
    await api.getPostApiResponse('http://108.136.142.112:90/token', {
      'username': 'a',
    });

    expect(adapter.requests[0].headers['Authorization'], 'Bearer jwt');
    expect(adapter.requests[1].headers.containsKey('Authorization'), isFalse);
  });

  test('maps status codes to typed exceptions', () async {
    Future<Object> errorFor(int status, {String? token = 'jwt'}) async {
      final api = service(
        _FakeAdapter(
          (_) => _json(status, {'success': false, 'error': 'Server says no'}),
        ),
        token: token,
      );
      try {
        await api.getGetApiResponse('http://host/get');
      } catch (error) {
        return error;
      }
      fail('expected an error for $status');
    }

    var expired = false;
    NetworkApiService.onSessionExpired = () => expired = true;
    expect(await errorFor(401), isA<UnauthorisedException>());
    expect(expired, isTrue);

    expired = false;
    final login = await errorFor(401, token: null);
    expect((login as AppException).message, 'Server says no');
    expect(expired, isFalse);

    final unsupported = await errorFor(415) as AppException;
    expect(unsupported.message, 'Server says no');
    expect(unsupported.retryable, isFalse);
    expect((await errorFor(503) as AppException).retryable, isTrue);
    expect(await errorFor(404), isA<BadRequestException>());
    NetworkApiService.onSessionExpired = null;
  });

  test('resumes a download with a Range request and appends', () async {
    final path = '${root.path}/file.bin.part';
    File(path).writeAsBytesSync([1, 2, 3]);
    final adapter = _FakeAdapter(
      (_) => ResponseBody.fromBytes(
        [4, 5],
        206,
        headers: {
          HttpHeaders.contentRangeHeader: ['bytes 3-4/5'],
        },
      ),
    );

    int? lastTotal;
    await service(adapter).downloadFileApi(
      'http://host/get?file=f',
      savePath: path,
      cancelToken: CancelToken(),
      onProgress: (_, total) => lastTotal = total,
    );

    expect(adapter.requests.single.headers['Range'], 'bytes=3-');
    expect(File(path).readAsBytesSync(), [1, 2, 3, 4, 5]);
    expect(lastTotal, 5);
  });

  test('restarts from scratch when the server ignores Range', () async {
    final path = '${root.path}/file.bin.part';
    File(path).writeAsBytesSync([9, 9]);
    final adapter = _FakeAdapter(
      (_) => ResponseBody.fromBytes(
        [1, 2, 3],
        200,
        headers: {
          HttpHeaders.contentLengthHeader: ['3'],
        },
      ),
    );

    await service(adapter).downloadFileApi(
      'http://host/get?file=f',
      savePath: path,
      cancelToken: CancelToken(),
      onProgress: (_, _) {},
    );

    expect(File(path).readAsBytesSync(), [1, 2, 3]);
  });

  test('treats 416 on a complete partial file as finished', () async {
    final path = '${root.path}/file.bin.part';
    File(path).writeAsBytesSync([1, 2, 3]);
    final adapter = _FakeAdapter(
      (_) => ResponseBody.fromString(
        '',
        416,
        headers: {
          HttpHeaders.contentRangeHeader: ['bytes */3'],
        },
      ),
    );

    await service(adapter).downloadFileApi(
      'http://host/get?file=f',
      savePath: path,
      cancelToken: CancelToken(),
      onProgress: (_, _) {},
    );

    expect(File(path).lengthSync(), 3);
  });

  test('a connection dropped mid-download is a retryable error', () async {
    final path = '${root.path}/file.bin.part';
    final adapter = _FakeAdapter(
      (_) => ResponseBody(
        Stream<Uint8List>.fromIterable([
          Uint8List.fromList([1, 2]),
        ]).followedBy(const SocketException('Connection reset')),
        200,
        headers: {
          HttpHeaders.contentLengthHeader: ['10'],
        },
      ),
    );

    await expectLater(
      service(adapter).downloadFileApi(
        'http://host/get?file=f',
        savePath: path,
        cancelToken: CancelToken(),
        onProgress: (_, _) {},
      ),
      throwsA(isA<FetchDataException>()),
    );
    expect(File(path).readAsBytesSync(), [1, 2]);
  });

  test('detects Range support from a 206 with Content-Range', () async {
    final adapter = _FakeAdapter(
      (options) => options.headers['Range'] == 'bytes=0-1'
          ? ResponseBody.fromBytes([0, 0], 206, headers: {'content-range': ['bytes 0-1/1000']})
          : ResponseBody.fromBytes(List.filled(1000, 0), 200),
    );
    expect(await service(adapter).supportsRangeRequests('http://108.136.142.112:90/get?file=a.mp4'), isTrue);
    expect(adapter.requests.single.headers['Authorization'], 'Bearer jwt');

    final ignoring = _FakeAdapter((_) => ResponseBody.fromBytes(List.filled(1000, 0), 200));
    expect(await service(ignoring).supportsRangeRequests('http://108.136.142.112:90/get?file=a.mp4'), isFalse);

    final rejected = _FakeAdapter((_) => _json(401, {'error': 'Unauthorized'}));
    await expectLater(service(rejected).supportsRangeRequests('http://108.136.142.112:90/get?file=a.mp4'), throwsA(isA<UnauthorisedException>()));
  });

  test('rejects uploads whose source file no longer exists', () async {
    final api = service(_FakeAdapter((_) => _json(201, {})));
    expect(
      api.uploadFileApi(
        'http://host/upload',
        filePath: '${root.path}/missing.csv',
        fileName: 'missing.csv',
        cancelToken: CancelToken(),
        onProgress: (_, _) {},
      ),
      throwsA(isA<InvalidInputException>()),
    );
  });

  group('Range resume validation', () {
    Future<Object?> resume(_FakeAdapter adapter, String path, {String? etag, void Function(String)? onEtag}) async {
      try {
        await service(adapter).downloadFileApi('http://host/get?file=f', savePath: path, cancelToken: CancelToken(), onProgress: (_, _) {}, expectedEtag: etag, onEtag: onEtag);
        return null;
      } catch (e) {
        return e;
      }
    }

    test('a 206 that does not start at the partial length is never appended', () async {
      final path = '${root.path}/file.bin.part';
      File(path).writeAsBytesSync([1, 2, 3]);
      final adapter = _FakeAdapter(
        (_) => ResponseBody.fromBytes([9, 9], 206, headers: {
          HttpHeaders.contentRangeHeader: ['bytes 0-1/5'],
        }),
      );

      final error = await resume(adapter, path);
      expect(error, isA<FetchDataException>().having((e) => e.message, 'message', contains('unexpected byte range')));
      expect(File(path).existsSync(), isFalse, reason: 'the partial file is discarded and the download restarts');
    });

    test('a 206 without Content-Range is never appended', () async {
      final path = '${root.path}/file.bin.part';
      File(path).writeAsBytesSync([1, 2, 3]);
      final error = await resume(_FakeAdapter((_) => ResponseBody.fromBytes([4, 5], 206)), path);
      expect(error, isA<FetchDataException>());
      expect(File(path).existsSync(), isFalse);
    });

    test('a changed ETag discards the partial file instead of mixing versions', () async {
      final path = '${root.path}/file.bin.part';
      File(path).writeAsBytesSync([1, 2, 3]);
      final adapter = _FakeAdapter(
        (_) => ResponseBody.fromBytes([4, 5], 206, headers: {
          HttpHeaders.contentRangeHeader: ['bytes 3-4/5'],
          HttpHeaders.etagHeader: ['"v2"'],
        }),
      );

      final error = await resume(adapter, path, etag: '"v1"');
      expect(error, isA<FetchDataException>().having((e) => e.message, 'message', contains('changed on the server')));
      expect(File(path).existsSync(), isFalse);
    });

    test('sends If-Range with a strong ETag and reports the response ETag', () async {
      final path = '${root.path}/file.bin.part';
      File(path).writeAsBytesSync([1, 2, 3]);
      final adapter = _FakeAdapter(
        (_) => ResponseBody.fromBytes([4, 5], 206, headers: {
          HttpHeaders.contentRangeHeader: ['bytes 3-4/5'],
          HttpHeaders.etagHeader: ['"v1"'],
        }),
      );
      String? reported;

      expect(await resume(adapter, path, etag: '"v1"', onEtag: (etag) => reported = etag), isNull);
      expect(adapter.requests.single.headers['If-Range'], '"v1"');
      expect(File(path).readAsBytesSync(), [1, 2, 3, 4, 5]);
      expect(reported, '"v1"');

      // Weak validators cannot be used with If-Range.
      File(path).writeAsBytesSync([1, 2, 3]);
      final weak = _FakeAdapter((_) => ResponseBody.fromBytes([4, 5], 206, headers: {HttpHeaders.contentRangeHeader: ['bytes 3-4/5']}));
      await resume(weak, path, etag: 'W/"v1"');
      expect(weak.requests.single.headers.containsKey('If-Range'), isFalse);
    });
  });

  test('network failures are NetworkExceptions; server errors are not', () async {
    final dropped = _FakeAdapter((_) => throw const SocketException('Network is unreachable'));
    await expectLater(service(dropped).getGetApiResponse('http://108.136.142.112:90/get'), throwsA(isA<NetworkException>()));

    final unavailable = _FakeAdapter((_) => _json(503, {}));
    final error = await service(unavailable).getGetApiResponse('http://108.136.142.112:90/get').then<Object?>((_) => null, onError: (Object e) => e);
    expect(error, isA<FetchDataException>().having((e) => e is NetworkException, 'is network', isFalse));
  });

}
