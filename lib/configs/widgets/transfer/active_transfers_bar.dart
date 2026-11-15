import 'package:flutter/material.dart';
import 'package:laantech_pos_task/configs/res/color.dart';
import 'package:laantech_pos_task/configs/res/text_styles.dart';
import 'package:laantech_pos_task/configs/services/navigator_services/navigation_service.dart';
import 'package:laantech_pos_task/view_model/transfer_view_model/transfer_view_model.dart';
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
                color: AppColors.whiteColor,
                backgroundColor: AppColors.whiteColor.withValues(alpha: 0.25),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                child: Row(
                  children: [
                    const Icon(Icons.sync_rounded, color: AppColors.whiteColor),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        '$active transfer${active == 1 ? '' : 's'} in progress · $percent%',
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
