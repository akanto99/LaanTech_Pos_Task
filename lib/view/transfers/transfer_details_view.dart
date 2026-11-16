import 'package:flutter/material.dart';
import 'package:laantech_pos_task/configs/res/color.dart';
import 'package:laantech_pos_task/configs/res/text_styles.dart';
import 'package:laantech_pos_task/configs/utils/formatters/formatters.dart';
import 'package:laantech_pos_task/configs/utils/routes/routes_name.dart';
import 'package:laantech_pos_task/configs/utils/utils.dart';
import 'package:laantech_pos_task/configs/widgets/state_views.dart';
import 'package:laantech_pos_task/configs/widgets/transfer/transfer_actions.dart';
import 'package:laantech_pos_task/configs/widgets/transfer/transfer_network_indicator.dart';
import 'package:laantech_pos_task/configs/widgets/transfer/transfer_status_chip.dart';
import 'package:laantech_pos_task/model/transfer/transfer_task.dart';
import 'package:laantech_pos_task/model/video/video_player_args.dart';
import 'package:laantech_pos_task/view_model/transfer_view_model/transfer_view_model.dart';
import 'package:laantech_pos_task/configs/res/sizedbox_spaccing.dart';
import 'package:laantech_pos_task/configs/responsive/responsive_ui.dart';
import 'package:provider/provider.dart';

class TransferDetailsView extends StatelessWidget {
  const TransferDetailsView({super.key, required this.transferId});

  final String transferId;

  Future<void> _remove(BuildContext context, TransferTask task) async {
    final confirmed = await Utils.confirm(
      context,
      title: 'Remove from history?',
      message: task.status.isFinished
          ? 'This entry will be removed. Downloaded files stay on the device.'
          : 'The transfer will be cancelled and removed.',
      confirmLabel: 'Remove',
      destructive: true,
    );
    if (!confirmed || !context.mounted) return;
    final error = await context.read<TransferViewModel>().remove(task.id);
    if (!context.mounted) return;
    error == null
        ? Navigator.pop(context)
        : Utils.flushBarErrorMessage(error, context);
  }

  @override
  Widget build(BuildContext context) {
    final task = context.select<TransferViewModel, TransferTask?>(
      (vm) => vm.byId(transferId),
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Transfer details'),
        actions: [
          if (task != null)
            IconButton(
              tooltip: 'Remove from history',
              onPressed: () => _remove(context, task),
              icon: const Icon(Icons.delete_outline_rounded),
            ),
        ],
      ),
      body: ResPonsiveUi.body(child: task == null
          ? const EmptyStateView(
              icon: Icons.history_toggle_off_rounded,
              title: 'Transfer not found',
              message: 'It may have been cleared from the history.',
            )
          : ListView(
              padding: ResPonsiveUi.pagePadding(context),
              children: [
                Card(
                  child: Padding(
                    padding: ResPonsiveUi.cardPadding(context),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          task.fileName,
                          style: AppTextStyles.textSize18(
                            context,
                            weight: FontWeight.w600,
                          ),
                        ),
                        SizedboxSpaccing.height01(context),
                        TransferStatusChip(status: task.status),
                        SizedboxSpaccing.height02(context),
                        LinearProgressIndicator(
                          minHeight: 8,
                          borderRadius: BorderRadius.circular(4),
                          value: task.progress,
                          color: TransferNetworkStyle.progressColorOf(task),
                        ),
                        SizedboxSpaccing.height01(context),
                        Text(
                          '${task.percent}% · ${Formatters.fileSize(task.transferredBytes)} of ${Formatters.fileSize(task.totalBytes)}',
                          style: AppTextStyles.textSize14(context),
                        ),
                        if (TransferNetworkStyle.appliesTo(task)) ...[
                          SizedboxSpaccing.height0075(context),
                          TransferNetworkIndicator(task: task),
                        ],
                        if (task.error != null) ...[
                          SizedboxSpaccing.height015(context),
                          Text(
                            task.error!,
                            style: AppTextStyles.textSize14(
                              context,
                              color: task.status == TransferStatus.failed ? AppColors.error : AppColors.warning,
                            ),
                          ),
                        ],
                        SizedboxSpaccing.height015(context),
                        TransferActions(task: task),
                        if (task.canPlayVideo)
                          FilledButton.icon(
                            onPressed: () => Navigator.pushNamed(
                              context,
                              RoutesName.videoPlayer,
                              arguments: VideoPlayerArgs(serverFileName: task.serverFileName!, title: task.fileName),
                            ),
                            icon: const Icon(Icons.play_arrow_rounded),
                            label: const Text('Play video'),
                          ),
                      ],
                    ),
                  ),
                ),
                SizedboxSpaccing.height02(context),
                Card(
                  child: Column(
                    children: [
                      _InfoRow('Transfer ID', task.id),
                      _InfoRow('Type', task.isUpload ? 'Upload' : 'Download'),
                      _InfoRow('Local path', task.localPath),
                      _InfoRow('Server file', task.serverFileName ?? '—'),
                      _InfoRow('Created', Formatters.dateTime(task.createdAt)),
                      _InfoRow('Updated', Formatters.dateTime(task.updatedAt)),
                      if (task.isUpload)
                        const _InfoRow(
                          'Resume support',
                          'Not available: the server accepts uploads as a single request, so a retry restarts from 0%.',
                        )
                      else
                        const _InfoRow(
                          'Resume support',
                          'HTTP Range: pausing keeps the partial file and resumes from it.',
                        ),
                    ],
                  ),
                ),
              ],
            )),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      title: Text(
        label,
        style: AppTextStyles.textSize12(
          context,
          color: AppColors.subtitle(context),
        ),
      ),
      subtitle: SelectableText(value, style: AppTextStyles.textSize14(context)),
    );
  }
}
