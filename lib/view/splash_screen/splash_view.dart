import 'package:flutter/material.dart';
import 'package:laantech_pos_task/configs/res/app_config.dart';
import 'package:laantech_pos_task/configs/res/color.dart';
import 'package:laantech_pos_task/configs/res/text_styles.dart';
import 'package:laantech_pos_task/configs/utils/routes/routes_name.dart';
import 'package:laantech_pos_task/view_model/auth_view_model/auth_view_model.dart';
import 'package:laantech_pos_task/configs/res/sizedbox_spaccing.dart';
import 'package:laantech_pos_task/configs/responsive/responsive_ui.dart';
import 'package:provider/provider.dart';

class SplashView extends StatefulWidget {
  const SplashView({super.key});

  @override
  State<SplashView> createState() => _SplashViewState();
}

class _SplashViewState extends State<SplashView> {
  static const _minimumDisplay = Duration(milliseconds: 1200);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrap());
  }

  Future<void> _bootstrap() async {
    final auth = context.read<AuthViewModel>();
    final results = await Future.wait([
      auth.restoreSession(),
      Future<void>.delayed(_minimumDisplay),
    ]);
    if (!mounted) return;
    final loggedIn = results.first as bool;
    Navigator.pushReplacementNamed(
      context,
      loggedIn ? RoutesName.home : RoutesName.login,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.primary,
      body: ResPonsiveUi.body(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(22),
                decoration: BoxDecoration(
                  color: AppColors.whiteColor,
                  borderRadius: BorderRadius.circular(28),
                ),
                child: const Icon(
                  Icons.point_of_sale_rounded,
                  size: 56,
                  color: AppColors.primary,
                ),
              ),
              SizedboxSpaccing.height025(context),
              Text(
                AppConfig.appName,
                style: AppTextStyles.textSize24(
                  context,
                  color: AppColors.whiteColor,
                ),
              ),
              SizedboxSpaccing.height005(context),
              Text(
                'File Transfer Center',
                style: AppTextStyles.textSize14(
                  context,
                  color: AppColors.whiteColor.withValues(alpha: 0.8),
                ),
              ),
              SizedboxSpaccing.height04(context),
              const SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: AppColors.whiteColor,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
