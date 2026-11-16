import 'package:flutter/material.dart';
import 'package:laantech_pos_task/configs/utils/routes/routes_name.dart';
import 'package:laantech_pos_task/model/video/video_player_args.dart';
import 'package:laantech_pos_task/view/auth/login_view.dart';
import 'package:laantech_pos_task/view/auth/register_view.dart';
import 'package:laantech_pos_task/view/download/download_view.dart';
import 'package:laantech_pos_task/view/home/home_view.dart';
import 'package:laantech_pos_task/view/splash_screen/splash_view.dart';
import 'package:laantech_pos_task/view/transfers/transfer_details_view.dart';
import 'package:laantech_pos_task/view/transfers/transfers_view.dart';
import 'package:laantech_pos_task/view/upload/upload_view.dart';
import 'package:laantech_pos_task/view/video_player/video_player_view.dart';

class Routes {
  static Route<dynamic> generateRoute(RouteSettings settings) {
    final Widget page = switch (settings.name) {
      RoutesName.splash => const SplashView(),
      RoutesName.login => const LoginView(),
      RoutesName.register => const RegisterView(),
      RoutesName.home => const HomeView(),
      RoutesName.upload => const UploadView(),
      RoutesName.download => const DownloadView(),
      RoutesName.transfers => const TransfersView(),
      RoutesName.transferDetails => TransferDetailsView(transferId: settings.arguments as String),
      RoutesName.videoPlayer => VideoPlayerView(video: settings.arguments as VideoPlayerArgs),
      _ => const Scaffold(body: Center(child: Text('No route defined'))),
    };
    return MaterialPageRoute(builder: (_) => page, settings: settings);
  }
}
