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
}
