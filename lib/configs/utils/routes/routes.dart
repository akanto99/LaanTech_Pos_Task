import 'package:flutter/material.dart';
import 'package:laantech_pos_task/configs/utils/routes/routes_name.dart';
import 'package:laantech_pos_task/view/auth/login_view.dart';
import 'package:laantech_pos_task/view/auth/register_view.dart';
import 'package:laantech_pos_task/view/splash_screen/splash_view.dart';

class Routes {
  static Route<dynamic> generateRoute(RouteSettings settings) {
    final Widget page = switch (settings.name) {
      RoutesName.splash => const SplashView(),
      RoutesName.login => const LoginView(),
      RoutesName.register => const RegisterView(),
      _ => const Scaffold(body: Center(child: Text('No route defined'))),
    };
    return MaterialPageRoute(builder: (_) => page, settings: settings);
  }
}
