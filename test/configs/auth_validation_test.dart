import 'package:flutter_test/flutter_test.dart';
import 'package:laantech_pos_task/configs/validations/auth_validation.dart';

void main() {
  test('username follows the backend rules', () {
    expect(AuthValidation.username(''), isNotNull);
    expect(AuthValidation.username('ab'), isNotNull);
    expect(AuthValidation.username('bad name'), isNotNull);
    expect(AuthValidation.username('a' * 33), isNotNull);
    expect(AuthValidation.username('cashier_01.main-1'), isNull);
  });

  test('password requires at least 6 characters', () {
    expect(AuthValidation.password('12345'), isNotNull);
    expect(AuthValidation.password('123456'), isNull);
  });

  test('confirm password must match', () {
    expect(AuthValidation.confirmPassword('abcdef', 'abcdeg'), isNotNull);
    expect(AuthValidation.confirmPassword('abcdef', 'abcdef'), isNull);
  });
}
