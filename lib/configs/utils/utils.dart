import 'package:another_flushbar/flushbar.dart';
import 'package:flutter/material.dart';
import 'package:laantech_pos_task/configs/res/color.dart';
import 'package:laantech_pos_task/configs/res/text_styles.dart';
import 'package:laantech_pos_task/configs/responsive/responsive_ui.dart';

class Utils {
  static void flushBarSuccessMessage(String message, BuildContext context) =>
      _flushBar(
        message,
        context,
        Icons.check_circle_outline,
        AppColors.success,
      );

  static void flushBarErrorMessage(String message, BuildContext context) =>
      _flushBar(message, context, Icons.error_outline, AppColors.error);

  static void _flushBar(
    String message,
    BuildContext context,
    IconData icon,
    Color iconColor,
  ) {
    Flushbar(
      margin: ResPonsiveUi.padding(context, horizontal: 0.04, vertical: 0.0125),
      padding: ResPonsiveUi.padding(context, horizontal: 0.04, vertical: 0.018),
      messageText: Text(
        message,
        style: AppTextStyles.textSize14(
          context,
          color: AppColors.textPrimary(context),
        ),
      ),
      duration: const Duration(seconds: 3),
      borderRadius: BorderRadius.circular(10),
      flushbarPosition: FlushbarPosition.TOP,
      backgroundColor: AppColors.containerBackground(context),
      boxShadows: [
        BoxShadow(
          color: AppColors.flushbarColor(context),
          offset: const Offset(0, 2),
          blurRadius: 8,
        ),
      ],
      icon: Icon(icon, size: 26, color: iconColor),
    ).show(context);
  }

  static Future<bool> confirm(
    BuildContext context, {
    required String title,
    required String message,
    required String confirmLabel,
    bool destructive = false,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title, style: AppTextStyles.textSize18(dialogContext)),
        content: Text(message, style: AppTextStyles.textSize14(dialogContext)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Keep'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: TextButton.styleFrom(
              foregroundColor: destructive
                  ? AppColors.error
                  : AppColors.primary,
            ),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
    return result ?? false;
  }
}
