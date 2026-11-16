import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:laantech_pos_task/data/app_exceptions.dart';
import 'package:laantech_pos_task/data/network/base_api_services.dart';
import 'package:laantech_pos_task/data/network/token_manager.dart';
import 'package:laantech_pos_task/repository/video_repository/video_repository.dart';

class _FakeTokenManager extends TokenManager {
  _FakeTokenManager(this._token);
  final String? _token;

  @override
  Future<String?> get token async => _token;
}

class _FakeApi implements BaseApiServices {
  bool rangeSupported = true;
  final requestedUrls = <String>[];

  @override
  Future<bool> supportsRangeRequests(String url) async {
    requestedUrls.add(url);
    return rangeSupported;
  }

  @override
  Future<void> downloadFileApi(String url, {required String savePath, required TransferProgress onProgress, required CancelToken cancelToken}) async {
    requestedUrls.add(url);
    File(savePath).writeAsBytesSync([1, 2, 3]);
    onProgress(3, 3);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

void main() {
  late Directory root;
  late _FakeApi api;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('video');
    api = _FakeApi();
  });
  tearDown(() => root.delete(recursive: true));

  VideoRepository repository({String? token = 'jwt'}) => VideoRepository(apiServices: api, tokenManager: _FakeTokenManager(token), cacheDirectory: () async => root);

  test('streams with the bearer token in a header, never in the URL', () async {
    final source = await repository().streamSource('clip_ab12.mp4');

    expect(source!.uri.toString(), 'http://108.136.142.112:90/get?file=clip_ab12.mp4');
    expect(source.uri.toString(), isNot(contains('jwt')));
    expect(source.headers, {'authorization': 'Bearer jwt'});
  });

  test('returns no stream when the server ignores Range requests', () async {
    api.rangeSupported = false;
    expect(await repository().streamSource('clip.mp4'), isNull);
  });

  test('a missing session is reported as unauthorised', () async {
    await expectLater(repository(token: null).streamSource('clip.mp4'), throwsA(isA<UnauthorisedException>()));
  });

  test('download-first fallback caches a complete copy and can discard it', () async {
    final progress = <double?>[];
    final repo = repository();
    final source = await repo.download('clip.mp4', cancelToken: CancelToken(), onProgress: progress.add);

    expect(source.file.readAsBytesSync(), [1, 2, 3]);
    expect(File('${source.file.path}.part').existsSync(), isFalse);
    expect(progress.last, 1);

    await repo.discardDownload('clip.mp4');
    expect(source.file.existsSync(), isFalse);
  });
}
