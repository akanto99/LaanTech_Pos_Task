import 'package:flutter/foundation.dart';
import 'package:laantech_pos_task/data/app_exceptions.dart';
import 'package:laantech_pos_task/model/user/session_model.dart';
import 'package:laantech_pos_task/repository/auth_repository/auth_repository.dart';

class AuthViewModel with ChangeNotifier {
  AuthViewModel({AuthRepository? repository})
    : _repository = repository ?? AuthRepository();

  final AuthRepository _repository;

  SessionModel? _session;
  bool _loading = false;

  bool get loading => _loading;
  bool get isLoggedIn => _session != null && !_session!.isExpired;
  String get username => _session?.username ?? '';

  Future<bool> restoreSession() async {
    final session = await _repository.currentSession();
    if (session != null && session.isExpired) await _repository.logout();
    _session = session != null && !session.isExpired ? session : null;
    notifyListeners();
    return isLoggedIn;
  }

  /// Returns a user-facing error message, or `null` on success.
  Future<String?> login(String username, String password) =>
      _authenticate(() => _repository.login(username.trim(), password));

  Future<String?> register(String username, String password) =>
      _authenticate(() => _repository.register(username.trim(), password));

  Future<void> logout() async {
    await _repository.logout();
    _session = null;
    notifyListeners();
  }

  Future<String?> _authenticate(Future<SessionModel> Function() request) async {
    _setLoading(true);
    try {
      _session = await request();
      return null;
    } on AppException catch (error) {
      return error.message;
    } catch (_) {
      return 'Something went wrong. Please try again.';
    } finally {
      _setLoading(false);
    }
  }

  void _setLoading(bool value) {
    _loading = value;
    notifyListeners();
  }
}
