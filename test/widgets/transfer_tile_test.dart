import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:laantech_pos_task/configs/widgets/transfer/transfer_tile.dart';
import 'package:laantech_pos_task/model/transfer/transfer_command.dart';
import 'package:laantech_pos_task/model/transfer/transfer_task.dart';
import 'package:laantech_pos_task/view_model/transfer_view_model/transfer_view_model.dart';
import 'package:provider/provider.dart';

import '../helpers/fake_transfer_repository.dart';

void main() {
  late FakeTransferRepository repository;

  Future<void> pumpTile(WidgetTester tester, TransferTask task) async {
    repository = FakeTransferRepository();
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => TransferViewModel(repository: repository),
        child: MaterialApp(
          home: Scaffold(body: TransferTile(task: task)),
        ),
      ),
    );
  }

  testWidgets('running download shows progress with pause and cancel', (
    tester,
  ) async {
    await pumpTile(tester, buildTask('d', type: TransferType.download));

    expect(find.text('d.csv'), findsOneWidget);
    expect(find.text('In progress'), findsOneWidget);
    expect(find.text('25%'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(find.byTooltip('Pause'), findsOneWidget);
    expect(find.byTooltip('Cancel'), findsOneWidget);

    await tester.tap(find.byTooltip('Pause'));
    await tester.pump();
    expect(repository.commands.single.action, TransferAction.pause);
  });

  testWidgets('running upload cannot be paused', (tester) async {
    await pumpTile(tester, buildTask('u'));

    expect(find.byTooltip('Pause'), findsNothing);
    expect(find.byTooltip('Cancel'), findsOneWidget);
  });

  testWidgets('failed upload shows its error and a restart action', (
    tester,
  ) async {
    await pumpTile(
      tester,
      buildTask(
        'u',
        status: TransferStatus.failed,
        error: 'No internet connection.',
      ),
    );

    expect(find.text('Failed'), findsOneWidget);
    expect(find.text('No internet connection.'), findsOneWidget);
    expect(find.byTooltip('Restart upload'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNothing);
  });

  testWidgets('cancel asks for confirmation first', (tester) async {
    await pumpTile(tester, buildTask('u'));

    await tester.tap(find.byTooltip('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Cancel upload?'), findsOneWidget);

    await tester.tap(find.text('Keep'));
    await tester.pumpAndSettle();
    expect(repository.commands, isEmpty);
  });
}
