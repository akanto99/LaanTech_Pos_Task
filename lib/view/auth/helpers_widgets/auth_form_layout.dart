import 'package:flutter/material.dart';
import 'package:laantech_pos_task/configs/res/color.dart';
import 'package:laantech_pos_task/configs/res/text_styles.dart';
import 'package:laantech_pos_task/configs/res/sizedbox_spaccing.dart';
import 'package:laantech_pos_task/configs/responsive/responsive_ui.dart';

/// Shared shell for the login and registration forms.
class AuthFormLayout extends StatelessWidget {
  const AuthFormLayout({
    super.key,
    required this.title,
    required this.subtitle,
    required this.form,
    required this.footer,
  });

  final String title;
  final String subtitle;
  final Widget form;
  final Widget footer;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: ResPonsiveUi.padding(context, horizontal: 0.05, vertical: 0.023),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Icon(
                      Icons.point_of_sale_rounded,
                      size: 40,
                      color: AppColors.whiteColor,
                    ),
                  ),
                  SizedboxSpaccing.height025(context),
                  Text(title, style: AppTextStyles.textSize24(context)),
                  SizedboxSpaccing.height0075(context),
                  Text(
                    subtitle,
                    textAlign: TextAlign.center,
                    style: AppTextStyles.textSize14(
                      context,
                      color: AppColors.subtitle(context),
                    ),
                  ),
                  SizedboxSpaccing.height03(context),
                  Card(
                    child: Padding(
                      padding: ResPonsiveUi.cardPadding(context),
                      child: form,
                    ),
                  ),
                  SizedboxSpaccing.height025(context),
                  footer,
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
