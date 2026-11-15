import 'package:flutter/material.dart';
import 'package:laantech_pos_task/configs/res/color.dart';
import 'package:laantech_pos_task/configs/utils/utils.dart';
import 'package:laantech_pos_task/model/transfer/transfer_task.dart';
import 'package:laantech_pos_task/view_model/transfer_view_model/transfer_view_model.dart';
import 'package:provider/provider.dart';

/// Pause / resume / retry / cancel controls valid for the task's state.
class TransferActions extends StatelessWidget {
  const TransferActions({super.key, required this.task});

  final TransferTask task;

  Future<void> _run(
    BuildContext context,
    Future<String?> Function(TransferViewModel vm) action,
  ) async {
    final error = await action(context.read<TransferViewModel>());
    if (error != null && context.mounted) {
      Utils.flushBarErrorMessage(error, context);
    }
  }

  Future<void> _cancel(BuildContext context) async {
    final confirmed = await Utils.confirm(
      context,
      title: task.isUpload ? 'Cancel upload?' : 'Cancel download?',
      message: task.isUpload
          ? 'The server does not support resuming uploads. Retrying later will start "${task.fileName}" from the beginning.'
          : 'The partially downloaded data for "${task.fileName}" will be deleted.',
      confirmLabel: 'Cancel transfer',
      destructive: true,
    );
    if (confirmed && context.mounted) {
      await _run(context, (vm) => vm.cancel(task.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final retryLabel = task.isUpload ? 'Restart upload' : 'Retry (resumes)';
    return Wrap(
      spacing: 4,
      children: [
        if (task.canPause)
          _ActionButton(
            icon: Icons.pause_rounded,
            tooltip: 'Pause',
            onPressed: () => _run(context, (vm) => vm.pause(task.id)),
          ),
        if (task.canResume)
          _ActionButton(
            icon: Icons.play_arrow_rounded,
            tooltip: 'Resume',
            onPressed: () => _run(context, (vm) => vm.resume(task.id)),
          ),
        if (task.canRetry)
          _ActionButton(
            icon: Icons.refresh_rounded,
            tooltip: retryLabel,
            onPressed: () => _run(context, (vm) => vm.retry(task.id)),
          ),
        if (task.canCancel)
          _ActionButton(
            icon: Icons.close_rounded,
            tooltip: 'Cancel',
            color: AppColors.error,
            onPressed: () => _cancel(context),
          ),
      ],
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.color,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return IconButton.filledTonal(
      tooltip: tooltip,
      onPressed: onPressed,
      icon: Icon(icon, color: color),
      visualDensity: VisualDensity.compact,
    );
  }
}
