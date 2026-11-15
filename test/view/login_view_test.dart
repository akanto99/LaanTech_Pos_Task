import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:laantech_pos_task/view/auth/login_view.dart';
import 'package:laantech_pos_task/view_model/auth_view_model/auth_view_model.dart';
import 'package:provider/provider.dart';

import '../helpers/fakes.dart';

void main() {
  testWidgets('shows validation errors and does not call the API', (
    tester,
  ) async {
    final repository = FakeAuthRepository();
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => AuthViewModel(repository: repository),
        child: const MaterialApp(home: LoginView()),
      ),
    );

    await tester.enterText(find.byType(TextFormField).first, 'a b');
    await tester.tap(find.text('Sign In'));
    await tester.pump();

    expect(find.text('Use 3-32 letters, numbers, _ . or -'), findsOneWidget);
    expect(find.text('Please enter your password'), findsOneWidget);
    expect(repository.session, isNull);
  });
}
