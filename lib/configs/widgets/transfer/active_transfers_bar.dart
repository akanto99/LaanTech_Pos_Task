import 'package:flutter/material.dart';
import 'package:laantech_pos_task/configs/res/color.dart';
import 'package:laantech_pos_task/configs/res/text_styles.dart';
import 'package:laantech_pos_task/configs/services/navigator_services/navigation_service.dart';
import 'package:laantech_pos_task/configs/widgets/transfer/transfer_network_indicator.dart';
import 'package:laantech_pos_task/view_model/transfer_view_model/transfer_view_model.dart';
import 'package:laantech_pos_task/configs/res/sizedbox_spaccing.dart';
import 'package:laantech_pos_task/configs/responsive/responsive_ui.dart';
import 'package:provider/provider.dart';

/// Persistent strip shown above every screen while transfers are active.
class ActiveTransfersBar extends StatelessWidget {
  const ActiveTransfersBar({super.key});

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<TransferViewModel>();
    final active = vm.activeCount;
    if (active == 0) return const SizedBox.shrink();
    final percent = (vm.activeProgress * 100).floor();
    final health = vm.activeNetworkHealth;
    final degraded = health.isDegraded;
    final note = degraded ? ' · ${health.label}' : '';

    return Material(
      color: AppColors.primary,
      child: SafeArea(
        top: false,
        child: InkWell(
          onTap: NavigationService.openTransfers,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              LinearProgressIndicator(
                value: vm.activeProgress,
                minHeight: 3,
                // On the brand-colored bar, healthy progress stays white and
                // degraded network tints it (amber, or red when offline).
                color: degraded ? Color.lerp(TransferNetworkStyle.colorOf(health), AppColors.whiteColor, 0.35) : AppColors.whiteColor,
                backgroundColor: AppColors.whiteColor.withValues(alpha: 0.25),
              ),
              Padding(
                padding: ResPonsiveUi.padding(context, horizontal: 0.04, vertical: 0.0125),
                child: Row(
                  children: [
                    Icon(degraded ? TransferNetworkStyle.iconOf(health) : Icons.sync_rounded, color: AppColors.whiteColor),
                    SizedboxSpaccing.width03(context),
                    Expanded(
                      child: Text(
                        '$active transfer${active == 1 ? '' : 's'} in progress · $percent%$note',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.textSize14(
                          context,
                          weight: FontWeight.w500,
                          color: AppColors.whiteColor,
                        ),
                      ),
                    ),
                    Text(
                      'View',
                      style: AppTextStyles.textSize14(
                        context,
                        weight: FontWeight.w600,
                        color: AppColors.whiteColor,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
