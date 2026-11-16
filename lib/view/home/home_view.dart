import 'dart:async';

import 'package:flutter/material.dart';
import 'package:laantech_pos_task/configs/res/app_config.dart';
import 'package:laantech_pos_task/configs/res/color.dart';
import 'package:laantech_pos_task/configs/res/text_styles.dart';
import 'package:laantech_pos_task/configs/services/navigator_services/navigation_service.dart';
import 'package:laantech_pos_task/configs/utils/routes/routes_name.dart';
import 'package:laantech_pos_task/configs/utils/utils.dart';
import 'package:laantech_pos_task/configs/widgets/transfer/transfer_tile.dart';
import 'package:laantech_pos_task/model/transfer/transfer_task.dart';
import 'package:laantech_pos_task/view_model/auth_view_model/auth_view_model.dart';
import 'package:laantech_pos_task/view_model/transfer_view_model/transfer_view_model.dart';
import 'package:laantech_pos_task/configs/res/sizedbox_spaccing.dart';
import 'package:laantech_pos_task/configs/responsive/responsive_ui.dart';
import 'package:provider/provider.dart';

class HomeView extends StatefulWidget {
  const HomeView({super.key});

  @override
  State<HomeView> createState() => _HomeViewState();
}

class _HomeViewState extends State<HomeView> {
  StreamSubscription<void>? _openRequests;

  @override
  void initState() {
    super.initState();
    _openRequests = context.read<TransferViewModel>().openRequests.listen(
      (_) => NavigationService.openTransfers(),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final pending = NavigationService.pendingTransferId;
      NavigationService.pendingTransferId = null;
      if (pending != null) NavigationService.openTransfer(pending);
    });
  }

  @override
  void dispose() {
    _openRequests?.cancel();
    super.dispose();
  }

  Future<void> _logout() async {
    final transfers = context.read<TransferViewModel>();
    final active = transfers.activeCount;
    final confirmed = await Utils.confirm(
      context,
      title: 'Sign out?',
      message: active > 0
          ? '$active active transfer(s) will be cancelled and transfer history cleared.'
          : 'Transfer history on this device will be cleared.',
      confirmLabel: 'Sign out',
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    final auth = context.read<AuthViewModel>();
    await transfers.reset();
    await auth.logout();
    if (!mounted) return;
    Navigator.pushNamedAndRemoveUntil(context, RoutesName.login, (_) => false);
  }

  @override
  Widget build(BuildContext context) {
    final transfers = context.watch<TransferViewModel>();
    final username = context.select<AuthViewModel, String>((vm) => vm.username);
    final recent = transfers.tasks.take(3).toList();

    return Scaffold(
      appBar: AppBar(
        title: Text(
          AppConfig.appName,
          style: AppTextStyles.textSize20(context, weight: FontWeight.w600),
        ),
        actions: [
          IconButton(
            tooltip: 'Sign out',
            icon: const Icon(Icons.logout_rounded),
            onPressed: _logout,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: transfers.refresh,
        child: ListView(
          padding: ResPonsiveUi.pagePadding(context),
          children: [
            _WelcomeCard(username: username),
            SizedboxSpaccing.height02(context),
            Row(
              children: [
                _StatTile(
                  label: 'Active',
                  value: transfers.activeCount,
                  color: AppColors.primary,
                ),
                SizedboxSpaccing.width03(context),
                _StatTile(
                  label: 'Completed',
                  value: transfers.count(TransferStatus.completed),
                  color: AppColors.success,
                ),
                SizedboxSpaccing.width03(context),
                _StatTile(
                  label: 'Failed',
                  value: transfers.count(TransferStatus.failed),
                  color: AppColors.error,
                ),
              ],
            ),
            SizedboxSpaccing.height03(context),
            _SectionTitle(title: 'Quick actions'),
            SizedboxSpaccing.height015(context),
            GridView(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 420,
                // Grows with the user's text size so the two text lines fit.
                mainAxisExtent: MediaQuery.textScalerOf(context).scale(84),
                crossAxisSpacing: ResPonsiveUi.width(context, 0.03),
                mainAxisSpacing: ResPonsiveUi.height(context, 0.015),
              ),
              children: const [
                _ActionCard(
                  icon: Icons.cloud_upload_outlined,
                  title: 'Upload files',
                  subtitle: 'Catalogs, CSV, images, videos',
                  route: RoutesName.upload,
                ),
                _ActionCard(
                  icon: Icons.cloud_download_outlined,
                  title: 'Server files',
                  subtitle: 'Browse and download',
                  route: RoutesName.download,
                ),
                _ActionCard(
                  icon: Icons.swap_vert_rounded,
                  title: 'Transfer center',
                  subtitle: 'Track every upload and download',
                  route: RoutesName.transfers,
                ),
              ],
            ),
            SizedboxSpaccing.height03(context),
            _SectionTitle(
              title: 'Recent transfers',
              action: recent.isEmpty
                  ? null
                  : TextButton(
                      onPressed: () =>
                          Navigator.pushNamed(context, RoutesName.transfers),
                      child: const Text('View all'),
                    ),
            ),
            SizedboxSpaccing.height01(context),
            if (recent.isEmpty)
              Padding(
                padding: ResPonsiveUi.padding(context, vertical: 0.028),
                child: Text(
                  'No transfers yet. Upload a file to get started.',
                  textAlign: TextAlign.center,
                  style: AppTextStyles.textSize14(
                    context,
                    color: AppColors.subtitle(context),
                  ),
                ),
              )
            else
              for (final task in recent)
                Padding(
                  padding: EdgeInsets.only(bottom: ResPonsiveUi.height(context, 0.0125)),
                  child: TransferTile(task: task),
                ),
          ],
        ),
      ),
    );
  }
}

class _WelcomeCard extends StatelessWidget {
  const _WelcomeCard({required this.username});

  final String username;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: ResPonsiveUi.cardPadding(context),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.primary, Color(0xFF3B6CF0)],
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Hello, $username',
                  style: AppTextStyles.textSize20(
                    context,
                    weight: FontWeight.w600,
                    color: AppColors.whiteColor,
                  ),
                ),
                SizedboxSpaccing.height005(context),
                Text(
                  'Transfers keep running in the background, even when the app is minimised.',
                  style: AppTextStyles.textSize12(
                    context,
                    color: AppColors.whiteColor.withValues(alpha: 0.85),
                  ),
                ),
              ],
            ),
          ),
          SizedboxSpaccing.width03(context),
          const Icon(
            Icons.storefront_rounded,
            size: 44,
            color: AppColors.whiteColor,
          ),
        ],
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final int value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Card(
        child: Padding(
          padding: ResPonsiveUi.padding(context, horizontal: 0.03, vertical: 0.016),
          // One line each, scaled down on narrow screens or large text.
          child: Column(
            children: [
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  '$value',
                  maxLines: 1,
                  style: AppTextStyles.textSize24(context, color: color),
                ),
              ),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  label,
                  maxLines: 1,
                  style: AppTextStyles.textSize12(
                    context,
                    color: AppColors.subtitle(context),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, this.action});

  final String title;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: AppTextStyles.textSize16(context, weight: FontWeight.w600),
          ),
        ),
        ?action,
      ],
    );
  }
}

class _ActionCard extends StatelessWidget {
  const _ActionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.route,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String route;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.pushNamed(context, route),
        child: Padding(
          padding: ResPonsiveUi.padding(context, horizontal: 0.04),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: AppColors.primary),
              ),
              SizedboxSpaccing.width035(context),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.textSize16(
                        context,
                        weight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.textSize12(
                        context,
                        color: AppColors.subtitle(context),
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: AppColors.subtitle(context),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
