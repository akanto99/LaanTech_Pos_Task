import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:laantech_pos_task/model/user/session_model.dart';

/// Shared by the UI isolate and the foreground-service isolate, so the token
/// is always read from secure storage instead of an in-memory cache.
class TokenManager {
  TokenManager({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  static const _tokenKey = 'access_token';
  static const _usernameKey = 'username';
  static const _expiresAtKey = 'expires_at';

  Future<String?> get token => _storage.read(key: _tokenKey);

  Future<void> saveSession(SessionModel session) async {
    await _storage.write(key: _tokenKey, value: session.token);
    await _storage.write(key: _usernameKey, value: session.username);
    await _storage.write(
      key: _expiresAtKey,
      value: session.expiresAt.toIso8601String(),
    );
  }

  Future<SessionModel?> readSession() async {
    final values = await _storage.readAll();
    final token = values[_tokenKey];
    final expiresAt = DateTime.tryParse(values[_expiresAtKey] ?? '');
    if (token == null || token.isEmpty || expiresAt == null) return null;
    return SessionModel(
      token: token,
      username: values[_usernameKey] ?? '',
      expiresAt: expiresAt,
    );
  }

  Future<void> clear() => _storage.deleteAll();
}
