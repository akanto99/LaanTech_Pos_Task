import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:laantech_pos_task/configs/res/app_config.dart';
import 'package:laantech_pos_task/configs/services/navigator_services/navigation_service.dart';
import 'package:laantech_pos_task/configs/services/session_expired_services/session_expired.dart';
import 'package:laantech_pos_task/configs/utils/routes/routes.dart';
import 'package:laantech_pos_task/configs/utils/routes/routes_name.dart';
import 'package:laantech_pos_task/data/network/network_api_service.dart';
import 'package:laantech_pos_task/theme/app_theme.dart';
import 'package:laantech_pos_task/view_model/auth_view_model/auth_view_model.dart';
import 'package:provider/provider.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  NetworkApiService.onSessionExpired = SessionExpiredService.handle;

  runApp(
    MultiProvider(
      providers: [ChangeNotifierProvider(create: (_) => AuthViewModel())],
      child: const PosApp(),
    ),
  );
}

class PosApp extends StatelessWidget {
  const PosApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: AppConfig.appName,
      navigatorKey: NavigationService.navigatorKey,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      initialRoute: RoutesName.splash,
      onGenerateRoute: Routes.generateRoute,
    );
  }
}
