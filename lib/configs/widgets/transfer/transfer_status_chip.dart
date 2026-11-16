import 'package:flutter/material.dart';
import 'package:laantech_pos_task/configs/res/color.dart';
import 'package:laantech_pos_task/configs/res/text_styles.dart';
import 'package:laantech_pos_task/model/transfer/transfer_task.dart';

class TransferStatusChip extends StatelessWidget {
  const TransferStatusChip({super.key, required this.status});

  final TransferStatus status;

  static Color colorOf(TransferStatus status) => switch (status) {
    TransferStatus.pending => AppColors.greyColor,
    TransferStatus.running => AppColors.primary,
    TransferStatus.paused => AppColors.warning,
    TransferStatus.completed => AppColors.success,
    TransferStatus.failed => AppColors.error,
    TransferStatus.cancelled => AppColors.greyColor,
  };

  static String labelOf(TransferStatus status) => switch (status) {
    TransferStatus.pending => 'Queued',
    TransferStatus.running => 'In progress',
    TransferStatus.paused => 'Paused',
    TransferStatus.completed => 'Completed',
    TransferStatus.failed => 'Failed',
    TransferStatus.cancelled => 'Cancelled',
  };

  @override
  Widget build(BuildContext context) {
    final color = colorOf(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        labelOf(status),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: AppTextStyles.textSize12(
          context,
          weight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}
