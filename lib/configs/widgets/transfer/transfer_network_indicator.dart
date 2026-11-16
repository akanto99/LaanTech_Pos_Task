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
    NetworkHealth.good || NetworkHealth.resumed => Icons.wifi_rounded,
    NetworkHealth.poor || NetworkHealth.stalled => Icons.network_check_rounded,
    NetworkHealth.reconnecting => Icons.sync_rounded,
    NetworkHealth.offline => Icons.wifi_off_rounded,
  };

  /// Network health applies only while a transfer is running.
  static bool appliesTo(TransferTask task) => task.status == TransferStatus.running;

  /// Progress bar color: the normal running color on a good connection,
  /// amber when poor or reconnecting, red when the connection is lost.
  /// Purely visual: it never affects the transfer itself.
  static Color progressColorOf(TransferTask task) {
    if (!appliesTo(task) || !task.networkHealth.isDegraded) return TransferStatusChip.colorOf(task.status);
    return colorOf(task.networkHealth);
  }

  /// Compact speed such as "820 KB/s" or "1.4 MB/s", or null when no data is moving.
  static String? speedOf(TransferTask task) => task.bytesPerSecond > 0 && !task.networkHealth.isWaiting ? '${Formatters.fileSize(task.bytesPerSecond)}/s' : null;
}

/// Small "Good Connection · 1.2 MB/s" line for a running transfer. Shows
/// nothing for queued, paused or finished transfers.
class TransferNetworkIndicator extends StatelessWidget {
  const TransferNetworkIndicator({super.key, required this.task});

  final TransferTask task;

  @override
  Widget build(BuildContext context) {
    if (!TransferNetworkStyle.appliesTo(task)) return const SizedBox.shrink();
    final health = task.networkHealth;
    final color = TransferNetworkStyle.colorOf(health);
    final speed = TransferNetworkStyle.speedOf(task);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(TransferNetworkStyle.iconOf(health), size: 14, color: color),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            speed == null ? health.label : '${health.label} · $speed',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.textSize12(context, weight: FontWeight.w500, color: color),
          ),
        ),
      ],
    );
  }
}
