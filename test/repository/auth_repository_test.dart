import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:laantech_pos_task/configs/res/app_url.dart';
import 'package:laantech_pos_task/data/network/base_api_services.dart';
import 'package:laantech_pos_task/data/network/token_manager.dart';
import 'package:laantech_pos_task/repository/auth_repository/auth_repository.dart';

class _RecordingApi implements BaseApiServices {
  String? postedUrl;
  Map<String, dynamic>? postedData;

  @override
  Future<dynamic> getPostApiResponse(
    String url,
    Map<String, dynamic> data,
  ) async {
    postedUrl = url;
    postedData = data;
    return {
      'success': true,
      'user': {'id': 22, 'username': data['username']},
      'token': 'jwt-token',
      'token_type': 'Bearer',
      'expires_in': 86400,
    };
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _RecordingApi api;
  late AuthRepository repository;

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    api = _RecordingApi();
    repository = AuthRepository(apiServices: api, tokenManager: TokenManager());
  });

  test(
    'login posts form credentials to /token and persists the session',
    () async {
      final session = await repository.login('cashier', 'secret1');

      expect(api.postedUrl, AppUrl.token);
      expect(api.postedData, {'username': 'cashier', 'password': 'secret1'});
      expect(session.token, 'jwt-token');
      expect(session.username, 'cashier');
      expect(session.isExpired, isFalse);

      final stored = await repository.currentSession();
      expect(stored?.token, 'jwt-token');
    },
  );

  test('register uses /register and signs the user in', () async {
    await repository.register('newuser', 'secret1');
    expect(api.postedUrl, AppUrl.register);
    expect((await repository.currentSession())?.username, 'newuser');
  });

  test('logout removes the stored session', () async {
    await repository.login('cashier', 'secret1');
    await repository.logout();
    expect(await repository.currentSession(), isNull);
  });
}
