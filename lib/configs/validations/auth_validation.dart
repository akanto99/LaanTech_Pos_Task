/// Rules mirror the backend's /register validation responses.
class AuthValidation {
  static final _usernamePattern = RegExp(r'^[A-Za-z0-9_.\-]{3,32}$');

  static String? username(String? value) {
    final username = value?.trim() ?? '';
    if (username.isEmpty) return 'Please enter your username';
    if (!_usernamePattern.hasMatch(username)) {
      return 'Use 3-32 letters, numbers, _ . or -';
    }
    return null;
  }

  static String? password(String? value) {
    if (value == null || value.isEmpty) return 'Please enter your password';
    if (value.length < 6) return 'Password must be at least 6 characters';
    return null;
  }

  static String? confirmPassword(String? value, String password) {
    if (value == null || value.isEmpty) return 'Please confirm your password';
    if (value != password) return 'Passwords do not match';
    return null;
  }
}
