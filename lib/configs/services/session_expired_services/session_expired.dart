import 'package:flutter/material.dart';
import 'package:laantech_pos_task/configs/services/navigator_services/navigation_service.dart';
import 'package:laantech_pos_task/configs/utils/routes/routes_name.dart';
import 'package:laantech_pos_task/configs/responsive/responsive_ui.dart';
import 'package:laantech_pos_task/view_model/auth_view_model/auth_view_model.dart';
import 'package:provider/provider.dart';

class SessionExpiredService {
  static bool _handling = false;

  static Future<void> handle() async {
    final context = NavigationService.context;
    if (_handling || context == null) return;
    _handling = true;
    try {
      await context.read<AuthViewModel>().logout();
      if (!context.mounted) return;
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => AlertDialog(
          insetPadding: ResPonsiveUi.dialogInsets(dialogContext),
          icon: const Icon(Icons.lock_clock_outlined, size: 40),
          title: const Text('Session expired'),
          content: const Text(
            'Your session has expired. Please sign in again to continue.',
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Sign in'),
            ),
          ],
        ),
      );
      NavigationService.navigatorKey.currentState?.pushNamedAndRemoveUntil(
        RoutesName.login,
        (_) => false,
      );
    } finally {
      _handling = false;
    }
  }
}
