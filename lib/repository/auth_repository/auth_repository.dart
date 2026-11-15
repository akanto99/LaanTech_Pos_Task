import 'package:laantech_pos_task/configs/res/app_url.dart';
import 'package:laantech_pos_task/data/network/base_api_services.dart';
import 'package:laantech_pos_task/data/network/network_api_service.dart';
import 'package:laantech_pos_task/data/network/token_manager.dart';
import 'package:laantech_pos_task/model/user/session_model.dart';

class AuthRepository {
  AuthRepository({BaseApiServices? apiServices, TokenManager? tokenManager})
    : _apiServices = apiServices ?? NetworkApiService(),
      _tokenManager = tokenManager ?? TokenManager();

  final BaseApiServices _apiServices;
  final TokenManager _tokenManager;

  Future<SessionModel> login(String username, String password) =>
      _authenticate(AppUrl.token, username, password);

  /// The backend issues a token on successful registration, so the user is
  /// signed in immediately.
  Future<SessionModel> register(String username, String password) =>
      _authenticate(AppUrl.register, username, password);

  Future<SessionModel?> currentSession() => _tokenManager.readSession();

  /// The API has no logout/revoke endpoint; the token is discarded locally.
  Future<void> logout() => _tokenManager.clear();

  Future<SessionModel> _authenticate(
    String url,
    String username,
    String password,
  ) async {
    final response = await _apiServices.getPostApiResponse(url, {
      'username': username,
      'password': password,
    });
    final session = SessionModel.fromJson(response as Map<String, dynamic>);
    await _tokenManager.saveSession(session);
    return session;
  }
}
