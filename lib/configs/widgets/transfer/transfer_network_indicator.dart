import 'package:flutter/material.dart';
import 'package:laantech_pos_task/configs/res/color.dart';
import 'package:laantech_pos_task/configs/res/text_styles.dart';
import 'package:laantech_pos_task/configs/utils/formatters/formatters.dart';
import 'package:laantech_pos_task/configs/widgets/transfer/transfer_status_chip.dart';
import 'package:laantech_pos_task/model/transfer/network_health.dart';
import 'package:laantech_pos_task/model/transfer/transfer_task.dart';

/// Shared visual language for transfer network health, so the upload,
/// download, dashboard and persistent bar all show the same state.
abstract final class TransferNetworkStyle {
  static Color colorOf(NetworkHealth health) => switch (health) {
    NetworkHealth.good || NetworkHealth.resumed => AppColors.success,
    NetworkHealth.poor || NetworkHealth.stalled || NetworkHealth.reconnecting => AppColors.warning,
    NetworkHealth.offline => AppColors.error,
  };

  static IconData iconOf(NetworkHealth health) => switch (health) {
    NetworkHealth.good => Icons.wifi_rounded,
    NetworkHealth.resumed => Icons.restart_alt_rounded,
    NetworkHealth.poor => Icons.network_check_rounded,
    NetworkHealth.stalled => Icons.hourglass_bottom_rounded,
    NetworkHealth.reconnecting => Icons.sync_rounded,
    NetworkHealth.offline => Icons.wifi_off_rounded,
  };

  static String labelOf(TransferTask task) => switch (task.networkHealth) {
    NetworkHealth.good => 'Good connection',
    NetworkHealth.resumed => task.isUpload ? 'Upload restarted' : 'Transfer resumed',
    NetworkHealth.poor => 'Poor connection',
    NetworkHealth.stalled => 'Stalled · no data received',
    NetworkHealth.reconnecting => 'Reconnecting…',
    NetworkHealth.offline => 'Connection lost · waiting for network',
  };

  /// Network health applies only while a transfer is running.
  static bool appliesTo(TransferTask task) => task.status == TransferStatus.running;

  /// Progress bar color: the normal running color while healthy, a subtle
  /// warning or error tint when the network degrades, otherwise the status color.
  static Color progressColorOf(TransferTask task) {
    if (!appliesTo(task)) return TransferStatusChip.colorOf(task.status);
    return switch (task.networkHealth) {
      NetworkHealth.good || NetworkHealth.resumed => TransferStatusChip.colorOf(task.status),
      final health => colorOf(health).withValues(alpha: 0.85),
    };
  }
}

/// Small "● Good connection · 1.2 MB/s" line for a running transfer. Shows
/// nothing for queued, paused or finished transfers.
class TransferNetworkIndicator extends StatelessWidget {
  const TransferNetworkIndicator({super.key, required this.task});

  final TransferTask task;

  @override
  Widget build(BuildContext context) {
    if (!TransferNetworkStyle.appliesTo(task)) return const SizedBox.shrink();
    final health = task.networkHealth;
    final color = TransferNetworkStyle.colorOf(health);
    final speed = task.bytesPerSecond > 0 && !health.isWaiting ? ' · ${Formatters.fileSize(task.bytesPerSecond)}/s' : '';
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(TransferNetworkStyle.iconOf(health), size: 14, color: color),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            '${TransferNetworkStyle.labelOf(task)}$speed',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.textSize12(context, weight: FontWeight.w500, color: color),
          ),
        ),
      ],
    );
  }
}
