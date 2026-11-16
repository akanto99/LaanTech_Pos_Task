import 'package:flutter/material.dart';
import 'package:laantech_pos_task/configs/res/color.dart';
import 'package:laantech_pos_task/configs/res/text_styles.dart';
import 'package:laantech_pos_task/configs/utils/formatters/formatters.dart';
import 'package:laantech_pos_task/configs/utils/routes/routes_name.dart';
import 'package:laantech_pos_task/configs/widgets/transfer/transfer_actions.dart';
import 'package:laantech_pos_task/configs/widgets/transfer/transfer_status_chip.dart';
import 'package:laantech_pos_task/model/transfer/transfer_task.dart';
import 'package:laantech_pos_task/model/video/video_player_args.dart';

class TransferTile extends StatelessWidget {
  const TransferTile({super.key, required this.task});

  final TransferTask task;

  void _openDetails(BuildContext context) => Navigator.pushNamed(context, RoutesName.transferDetails, arguments: task.id);

  void _play(BuildContext context) => Navigator.pushNamed(
    context,
    RoutesName.videoPlayer,
    arguments: VideoPlayerArgs(serverFileName: task.serverFileName!, title: task.fileName),
  );

  @override
  Widget build(BuildContext context) {
    final showProgress = !task.status.isFinished;
    final subtitle = task.totalBytes > 0
        ? '${Formatters.fileSize(task.transferredBytes)} of ${Formatters.fileSize(task.totalBytes)}'
        : 'Waiting for size…';

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => task.canPlayVideo ? _play(context) : _openDetails(context),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _TypeIcon(isUpload: task.isUpload, playable: task.canPlayVideo),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          task.fileName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.textSize14(
                            context,
                            weight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            TransferStatusChip(status: task.status),
                            const SizedBox(width: 8),
                            Flexible(
                              child: Text(
                                showProgress
                                    ? subtitle
                                    : Formatters.fileSize(task.totalBytes),
                                overflow: TextOverflow.ellipsis,
                                style: AppTextStyles.textSize12(
                                  context,
                                  color: AppColors.subtitle(context),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  TransferActions(task: task),
                  if (task.canPlayVideo)
                    IconButton(
                      tooltip: 'Transfer details',
                      onPressed: () => _openDetails(context),
                      icon: const Icon(Icons.info_outline_rounded),
                    ),
                ],
              ),
              if (showProgress) ...[
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          minHeight: 6,
                          value:
                              task.status == TransferStatus.running &&
                                  task.totalBytes <= 0
                              ? null
                              : task.progress,
                          color: TransferStatusChip.colorOf(task.status),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      '${task.percent}%',
                      style: AppTextStyles.textSize12(
                        context,
                        weight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 6),
                  ],
                ),
              ],
              if (task.error != null) ...[
                const SizedBox(height: 8),
                Text(
                  task.error!,
                  style: AppTextStyles.textSize12(
                    context,
                    color: task.status == TransferStatus.failed
                        ? AppColors.error
                        : AppColors.warning,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _TypeIcon extends StatelessWidget {
  const _TypeIcon({required this.isUpload, required this.playable});

  final bool isUpload;
  final bool playable;

  @override
  Widget build(BuildContext context) {
    final color = isUpload ? AppColors.primary : AppColors.secondary;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(
        playable ? Icons.play_arrow_rounded : (isUpload ? Icons.upload_rounded : Icons.download_rounded),
        color: color,
        semanticLabel: playable ? 'Play video' : (isUpload ? 'Upload' : 'Download'),
      ),
    );
  }
}
