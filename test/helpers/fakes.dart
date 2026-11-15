import 'package:laantech_pos_task/data/app_exceptions.dart';
import 'package:laantech_pos_task/model/user/session_model.dart';
import 'package:laantech_pos_task/repository/auth_repository/auth_repository.dart';

class FakeAuthRepository implements AuthRepository {
  SessionModel? session;
  AppException? error;
  bool loggedOut = false;

  @override
  Future<SessionModel?> currentSession() async => session;

  @override
  Future<SessionModel> login(String username, String password) =>
      _authenticate(username);

  @override
  Future<SessionModel> register(String username, String password) =>
      _authenticate(username);

  @override
  Future<void> logout() async {
    loggedOut = true;
    session = null;
  }

  Future<SessionModel> _authenticate(String username) async {
    if (error != null) throw error!;
    return session = SessionModel(
      token: 'token',
      username: username,
      expiresAt: DateTime.now().add(const Duration(hours: 1)),
    );
  }
}
