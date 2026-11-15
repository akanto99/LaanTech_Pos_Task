import 'package:flutter/material.dart';
import 'package:laantech_pos_task/configs/utils/utils.dart';
import 'package:laantech_pos_task/configs/widgets/state_views.dart';
import 'package:laantech_pos_task/configs/widgets/transfer/transfer_tile.dart';
import 'package:laantech_pos_task/model/transfer/transfer_task.dart';
import 'package:laantech_pos_task/view_model/transfer_view_model/transfer_view_model.dart';
import 'package:provider/provider.dart';

enum _Filter {
  all('All'),
  active('Active'),
  paused('Paused'),
  completed('Completed'),
  failed('Failed');

  const _Filter(this.label);
  final String label;

  bool matches(TransferTask task) => switch (this) {
    _Filter.all => true,
    _Filter.active => task.status.isActive,
    _Filter.paused => task.status == TransferStatus.paused,
    _Filter.completed => task.status == TransferStatus.completed,
    _Filter.failed =>
      task.status == TransferStatus.failed ||
          task.status == TransferStatus.cancelled,
  };
}

class TransfersView extends StatefulWidget {
  const TransfersView({super.key});

  @override
  State<TransfersView> createState() => _TransfersViewState();
}

class _TransfersViewState extends State<TransfersView> {
  _Filter _filter = _Filter.all;

  Future<void> _clearFinished() async {
    final confirmed = await Utils.confirm(
      context,
      title: 'Clear finished transfers?',
      message:
          'Completed, failed and cancelled entries will be removed from the history. Downloaded files stay on the device.',
      confirmLabel: 'Clear',
    );
    if (!confirmed || !mounted) return;
    final error = await context.read<TransferViewModel>().clearFinished();
    if (error != null && mounted) Utils.flushBarErrorMessage(error, context);
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<TransferViewModel>();
    final visible = vm.tasks.where(_filter.matches).toList();
    final hasFinished = vm.tasks.any((task) => task.status.isFinished);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Transfer center'),
        actions: [
          IconButton(
            tooltip: 'Clear finished',
            onPressed: hasFinished ? _clearFinished : null,
            icon: const Icon(Icons.cleaning_services_outlined),
          ),
        ],
      ),
      body: Column(
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Row(
              children: [
                for (final filter in _Filter.values)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(
                        '${filter.label} (${vm.tasks.where(filter.matches).length})',
                      ),
                      selected: _filter == filter,
                      onSelected: (_) => setState(() => _filter = filter),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: vm.refresh,
              child: visible.isEmpty
                  ? ListView(
                      children: [
                        const SizedBox(height: 80),
                        EmptyStateView(
                          icon: Icons.swap_vert_rounded,
                          title: 'Nothing here',
                          message: _filter == _Filter.all
                              ? 'Uploads and downloads will be tracked here.'
                              : 'No ${_filter.label.toLowerCase()} transfers.',
                        ),
                      ],
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: visible.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (_, index) =>
                          TransferTile(task: visible[index]),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
