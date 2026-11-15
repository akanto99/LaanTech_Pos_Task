import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:laantech_pos_task/configs/res/app_config.dart';
import 'package:laantech_pos_task/configs/services/navigator_services/navigation_service.dart';
import 'package:laantech_pos_task/configs/services/notification_services/notification_service.dart';
import 'package:laantech_pos_task/configs/services/session_expired_services/session_expired.dart';
import 'package:laantech_pos_task/configs/utils/routes/routes.dart';
import 'package:laantech_pos_task/configs/utils/routes/routes_name.dart';
import 'package:laantech_pos_task/configs/widgets/transfer/active_transfers_bar.dart';
import 'package:laantech_pos_task/data/network/network_api_service.dart';
import 'package:laantech_pos_task/repository/transfer_repository/transfer_repository.dart';
import 'package:laantech_pos_task/theme/app_theme.dart';
import 'package:laantech_pos_task/view_model/auth_view_model/auth_view_model.dart';
import 'package:laantech_pos_task/view_model/transfer_view_model/transfer_view_model.dart';
import 'package:provider/provider.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  NetworkApiService.onSessionExpired = SessionExpiredService.handle;
  TransferRepository.initialize();
  await NotificationService.instance.initialize(onTap: _onNotificationTap);
  NavigationService.pendingTransferId = await NotificationService.instance
      .launchTransferId();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthViewModel()),
        ChangeNotifierProvider(create: (_) => TransferViewModel(), lazy: false),
      ],
      child: const PosApp(),
    ),
  );
}

void _onNotificationTap(String? transferId) {
  final context = NavigationService.context;
  if (context != null && context.read<AuthViewModel>().isLoggedIn) {
    NavigationService.openTransfer(transferId);
  } else {
    NavigationService.pendingTransferId = transferId;
  }
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
      builder: (context, child) => Column(
        children: [
          Expanded(child: child!),
          const ActiveTransfersBar(),
        ],
      ),
    );
  }
}
