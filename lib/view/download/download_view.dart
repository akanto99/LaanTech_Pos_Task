import 'package:flutter/material.dart';
import 'package:laantech_pos_task/configs/res/color.dart';
import 'package:laantech_pos_task/configs/res/text_styles.dart';
import 'package:laantech_pos_task/configs/utils/formatters/formatters.dart';
import 'package:laantech_pos_task/configs/utils/routes/routes_name.dart';
import 'package:laantech_pos_task/configs/utils/utils.dart';
import 'package:laantech_pos_task/configs/widgets/state_views.dart';
import 'package:laantech_pos_task/configs/widgets/transfer/transfer_actions.dart';
import 'package:laantech_pos_task/configs/widgets/transfer/transfer_network_indicator.dart';
import 'package:laantech_pos_task/data/response/status.dart';
import 'package:laantech_pos_task/model/server_file/server_file_model.dart';
import 'package:laantech_pos_task/model/transfer/transfer_task.dart';
import 'package:laantech_pos_task/model/video/video_player_args.dart';
import 'package:laantech_pos_task/view_model/server_files_view_model/server_files_view_model.dart';
import 'package:laantech_pos_task/view_model/transfer_view_model/transfer_view_model.dart';
import 'package:laantech_pos_task/configs/res/sizedbox_spaccing.dart';
import 'package:laantech_pos_task/configs/responsive/responsive_ui.dart';
import 'package:provider/provider.dart';

class DownloadView extends StatelessWidget {
  const DownloadView({super.key, this.createViewModel});

  /// Supplies the screen's view model in tests; it creates its own otherwise.
  @visibleForTesting
  final ServerFilesViewModel Function()? createViewModel;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(create: (_) => (createViewModel?.call() ?? ServerFilesViewModel())..fetchFiles(), child: const _ServerFilesScreen());
  }
}

class _ServerFilesScreen extends StatelessWidget {
  const _ServerFilesScreen();

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<ServerFilesViewModel>();
    final files = vm.files;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Server files'),
        actions: [IconButton(tooltip: 'Refresh', icon: const Icon(Icons.refresh_rounded), onPressed: vm.fetchFiles)],
      ),
      body: ResPonsiveUi.body(
        child: switch (files.status) {
          Status.loading => const Center(child: CircularProgressIndicator()),
          Status.error => ErrorStateView(
            message: vm.recoversAutomatically ? '${files.message!}\nThe list will reload automatically when the connection is back.' : files.message!,
            onRetry: vm.fetchFiles,
          ),
          Status.completed => RefreshIndicator(
            onRefresh: () => vm.fetchFiles(silent: true),
            child: files.data!.isEmpty
                ? ListView(
                    children: [
                      SizedBox(height: ResPonsiveUi.height(context, 0.1)),
                      const EmptyStateView(icon: Icons.folder_open_rounded, title: 'No files on the server', message: 'Files you upload will be listed here.'),
                    ],
                  )
                : ListView.separated(
                    padding: ResPonsiveUi.pagePadding(context),
                    itemCount: files.data!.length,
                    separatorBuilder: (_, _) => SizedboxSpaccing.height0125(context),
                    itemBuilder: (_, index) => _ServerFileTile(file: files.data![index]),
                  ),
          ),
        },
      ),
    );
  }
}

class _ServerFileTile extends StatelessWidget {
  const _ServerFileTile({required this.file});

  final ServerFileModel file;

  IconData get _icon {
    if (file.type.startsWith('image/')) return Icons.image_outlined;
    if (file.isVideo) return Icons.play_circle_outline_rounded;
    if (file.type.startsWith('audio/')) return Icons.audiotrack_outlined;
    if (file.type.contains('csv') || file.type.contains('sheet')) {
      return Icons.table_chart_outlined;
    }
    return Icons.insert_drive_file_outlined;
  }

  Future<void> _download(BuildContext context) async {
    final error = await context.read<TransferViewModel>().download(file);
    if (!context.mounted) return;
    error == null ? Utils.flushBarSuccessMessage('Download started', context) : Utils.flushBarErrorMessage(error, context);
  }

  Future<void> _delete(BuildContext context) async {
    final confirmed = await Utils.confirm(
      context,
      title: 'Delete from server?',
      message: '"${file.originalName}" will be permanently removed from the server.',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (!confirmed || !context.mounted) return;
    final error = await context.read<ServerFilesViewModel>().deleteFile(file);
    if (error != null && context.mounted) {
      Utils.flushBarErrorMessage(error, context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final task = context.select<TransferViewModel, TransferTask?>((vm) => vm.latestDownloadOf(file.name));
    final deleting = context.select<ServerFilesViewModel, bool>((vm) => vm.isDeleting(file.name));
    final inFlight = task != null && task.status != TransferStatus.completed && task.status != TransferStatus.cancelled;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: file.isVideo
            ? () => Navigator.pushNamed(
                context,
                RoutesName.videoPlayer,
                arguments: VideoPlayerArgs(serverFileName: file.name, title: file.originalName),
              )
            : null,
        child: Padding(
          padding: ResPonsiveUi.paddingLTRB(context, 0.035, 0.014, 0.01, 0.014),
          child: Column(
            children: [
              Row(
                children: [
                  Icon(_icon, color: AppColors.secondary, size: 32),
                  SizedboxSpaccing.width03(context),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          file.originalName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.textSize14(context, weight: FontWeight.w600),
                        ),
                        Text('${Formatters.fileSize(file.size)} · ${Formatters.dateTime(file.uploadedAt)}', style: AppTextStyles.textSize12(context, color: AppColors.subtitle(context))),
                        if (file.isVideo)
                          Text(
                            'Tap to play',
                            style: AppTextStyles.textSize12(context, weight: FontWeight.w600, color: AppColors.primary),
                          ),
                        if (task?.status == TransferStatus.completed)
                          Text(
                            'Downloaded',
                            style: AppTextStyles.textSize12(context, weight: FontWeight.w600, color: AppColors.success),
                          ),
                      ],
                    ),
                  ),
                  if (inFlight) TransferActions(task: task) else IconButton.filledTonal(tooltip: 'Download', onPressed: () => _download(context), icon: const Icon(Icons.download_rounded)),
                  deleting
                      ? const Padding(
                          padding: EdgeInsets.all(12),
                          child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                        )
                      : IconButton(tooltip: 'Delete from server', onPressed: inFlight ? null : () => _delete(context), icon: const Icon(Icons.delete_outline_rounded)),
                ],
              ),
              if (inFlight) ...[
                SizedboxSpaccing.height0125(context),
                Padding(
                  padding: EdgeInsets.only(right: ResPonsiveUi.width(context, 0.025)),
                  child: Row(
                    children: [
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(minHeight: 6, value: task.progress, color: TransferNetworkStyle.progressColorOf(task)),
                        ),
                      ),
                      SizedboxSpaccing.width025(context),
                      Text(switch (task.status) {
                        TransferStatus.paused => 'Paused ${task.percent}%',
                        TransferStatus.failed => 'Failed ${task.percent}%',
                        _ => '${task.percent}%',
                      }, style: AppTextStyles.textSize12(context, weight: FontWeight.w600)),
                    ],
                  ),
                ),
                if (TransferNetworkStyle.appliesTo(task))
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Padding(
                      padding: EdgeInsets.only(top: ResPonsiveUi.height(context, 0.0075), right: ResPonsiveUi.width(context, 0.025)),
                      child: TransferNetworkIndicator(task: task),
                    ),
                  ),
                if (task.error != null)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Padding(
                      padding: EdgeInsets.only(top: ResPonsiveUi.height(context, 0.0075), right: ResPonsiveUi.width(context, 0.025)),
                      child: Text(task.error!, style: AppTextStyles.textSize12(context, color: task.status == TransferStatus.failed ? AppColors.error : AppColors.warning)),
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
