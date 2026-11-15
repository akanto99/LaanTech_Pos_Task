import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:laantech_pos_task/configs/utils/routes/routes_name.dart';
import 'package:laantech_pos_task/model/user/session_model.dart';
import 'package:laantech_pos_task/view/splash_screen/splash_view.dart';
import 'package:laantech_pos_task/view_model/auth_view_model/auth_view_model.dart';
import 'package:provider/provider.dart';

import '../helpers/fakes.dart';

Future<String?> _routeAfterSplash(
  WidgetTester tester,
  SessionModel? session,
) async {
  final repository = FakeAuthRepository()..session = session;
  String? pushed;
  await tester.pumpWidget(
    ChangeNotifierProvider(
      create: (_) => AuthViewModel(repository: repository),
      child: MaterialApp(
        home: const SplashView(),
        onGenerateRoute: (settings) {
          pushed = settings.name;
          return MaterialPageRoute(builder: (_) => const SizedBox());
        },
      ),
    ),
  );
  await tester.pump(const Duration(seconds: 2));
  await tester.pumpAndSettle();
  return pushed;
}

void main() {
  testWidgets('routes to login when there is no session', (tester) async {
    expect(await _routeAfterSplash(tester, null), RoutesName.login);
  });

  testWidgets('routes to login when the stored session expired', (
    tester,
  ) async {
    final expired = SessionModel(
      token: 't',
      username: 'cashier',
      expiresAt: DateTime.now().subtract(const Duration(minutes: 1)),
    );
    expect(await _routeAfterSplash(tester, expired), RoutesName.login);
  });

  testWidgets('routes to home with a valid session', (tester) async {
    final valid = SessionModel(
      token: 't',
      username: 'cashier',
      expiresAt: DateTime.now().add(const Duration(hours: 1)),
    );
    expect(await _routeAfterSplash(tester, valid), RoutesName.home);
  });
}
