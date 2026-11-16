import 'package:flutter/material.dart';
import 'package:laantech_pos_task/configs/buttons/round_button.dart';
import 'package:laantech_pos_task/configs/res/app_config.dart';
import 'package:laantech_pos_task/configs/res/color.dart';
import 'package:laantech_pos_task/configs/res/text_styles.dart';
import 'package:laantech_pos_task/configs/utils/utils.dart';
import 'package:laantech_pos_task/configs/widgets/state_views.dart';
import 'package:laantech_pos_task/configs/widgets/transfer/transfer_tile.dart';
import 'package:laantech_pos_task/view_model/transfer_view_model/transfer_view_model.dart';
import 'package:laantech_pos_task/configs/res/sizedbox_spaccing.dart';
import 'package:laantech_pos_task/configs/responsive/responsive_ui.dart';
import 'package:provider/provider.dart';

class UploadView extends StatelessWidget {
  const UploadView({super.key});

  Future<void> _pick(BuildContext context) async {
    final message = await context.read<TransferViewModel>().pickAndUpload();
    if (message != null && context.mounted) {
      Utils.flushBarErrorMessage(message, context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<TransferViewModel>();
    final uploads = vm.uploads;

    return Scaffold(
      appBar: AppBar(title: const Text('Upload files')),
      body: ResPonsiveUi.body(child: CustomScrollView(
        slivers: [
          SliverPadding(
            padding: ResPonsiveUi.pagePadding(context),
            sliver: SliverToBoxAdapter(
              child: Card(
                child: Padding(
                  padding: ResPonsiveUi.cardPadding(context),
                  child: Column(
                    children: [
                      const Icon(
                        Icons.cloud_upload_outlined,
                        size: 48,
                        color: AppColors.primary,
                      ),
                      SizedboxSpaccing.height015(context),
                      Text(
                        'Select one or more files',
                        style: AppTextStyles.textSize16(
                          context,
                          weight: FontWeight.w600,
                        ),
                      ),
                      SizedboxSpaccing.height0075(context),
                      Text(
                        'Large files are streamed from storage and keep uploading in the background.\n'
                        'Supported: ${AppConfig.uploadExtensions.join(', ')}',
                        textAlign: TextAlign.center,
                        style: AppTextStyles.textSize12(
                          context,
                          color: AppColors.subtitle(context),
                        ),
                      ),
                      SizedboxSpaccing.height02(context),
                      RoundButton(
                        title: vm.picking ? 'Preparing files…' : 'Select files',
                        iconData: Icons.attach_file_rounded,
                        loading: vm.picking,
                        onPress: () => _pick(context),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (uploads.isEmpty)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: EmptyStateView(
                icon: Icons.inventory_2_outlined,
                title: 'No uploads yet',
                message: 'Selected files will appear here with live progress.',
              ),
            )
          else
            SliverPadding(
              padding: ResPonsiveUi.paddingLTRB(context, 0.04, 0, 0.04, 0.02),
              sliver: SliverList.separated(
                itemCount: uploads.length,
                separatorBuilder: (_, _) => SizedboxSpaccing.height0125(context),
                itemBuilder: (_, index) => TransferTile(task: uploads[index]),
              ),
            ),
        ],
      )),
    );
  }
}
