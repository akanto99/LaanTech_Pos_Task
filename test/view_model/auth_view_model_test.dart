import 'package:flutter_test/flutter_test.dart';
import 'package:laantech_pos_task/data/app_exceptions.dart';
import 'package:laantech_pos_task/view_model/auth_view_model/auth_view_model.dart';

import '../helpers/fakes.dart';

void main() {
  late FakeAuthRepository repository;
  late AuthViewModel viewModel;

  setUp(() {
    repository = FakeAuthRepository();
    viewModel = AuthViewModel(repository: repository);
  });

  test('successful login stores the session and clears loading', () async {
    final error = await viewModel.login('  cashier ', 'secret1');

    expect(error, isNull);
    expect(viewModel.isLoggedIn, isTrue);
    expect(viewModel.username, 'cashier');
    expect(viewModel.loading, isFalse);
  });

  test('failed login returns the server message', () async {
    repository.error = const UnauthorisedException(
      'Invalid username or password',
    );

    final error = await viewModel.login('cashier', 'wrong!');

    expect(error, 'Invalid username or password');
    expect(viewModel.isLoggedIn, isFalse);
    expect(viewModel.loading, isFalse);
  });

  test('logout clears the session', () async {
    await viewModel.register('cashier', 'secret1');
    await viewModel.logout();

    expect(repository.loggedOut, isTrue);
    expect(viewModel.isLoggedIn, isFalse);
  });
}
