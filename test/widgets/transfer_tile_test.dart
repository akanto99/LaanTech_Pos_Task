import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:laantech_pos_task/configs/utils/routes/routes_name.dart';
import 'package:laantech_pos_task/configs/res/color.dart';
import 'package:laantech_pos_task/configs/services/notification_services/notification_service.dart';
import 'package:laantech_pos_task/configs/widgets/transfer/transfer_tile.dart';
import 'package:laantech_pos_task/model/transfer/network_health.dart';
import 'package:laantech_pos_task/model/transfer/transfer_command.dart';
import 'package:laantech_pos_task/model/transfer/transfer_task.dart';
import 'package:laantech_pos_task/model/video/video_player_args.dart';
import 'package:laantech_pos_task/view_model/transfer_view_model/transfer_view_model.dart';
import 'package:provider/provider.dart';

import '../helpers/fake_transfer_repository.dart';

void main() {
  late FakeTransferRepository repository;

  late List<RouteSettings> pushed;

  Future<void> pumpTile(WidgetTester tester, TransferTask task) async {
    repository = FakeTransferRepository();
    pushed = [];
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => TransferViewModel(repository: repository),
        child: MaterialApp(
          home: Scaffold(body: TransferTile(task: task)),
          onGenerateRoute: (settings) {
            pushed.add(settings);
            return MaterialPageRoute(builder: (_) => const SizedBox(), settings: settings);
          },
        ),
      ),
    );
  }

  TransferTask uploadedVideo() => TransferTask(
    id: 'v',
    type: TransferType.upload,
    fileName: 'promo.mp4',
    localPath: '/tmp/promo.mp4',
    totalBytes: 1000,
    transferredBytes: 1000,
    status: TransferStatus.completed,
    createdAt: DateTime(2026),
    updatedAt: DateTime(2026),
    serverFileName: 'promo_ab12.mp4',
  );

  testWidgets('tapping an uploaded video opens the player', (tester) async {
    await pumpTile(tester, uploadedVideo());

    await tester.tap(find.text('promo.mp4'));
    await tester.pumpAndSettle();

    expect(pushed.single.name, RoutesName.videoPlayer);
    final args = pushed.single.arguments! as VideoPlayerArgs;
    expect(args.serverFileName, 'promo_ab12.mp4');
    expect(args.title, 'promo.mp4');
  });

  testWidgets('a playable video keeps its details one tap away', (tester) async {
    await pumpTile(tester, uploadedVideo());

    await tester.tap(find.byTooltip('Transfer details'));
    await tester.pumpAndSettle();

    expect(pushed.single.name, RoutesName.transferDetails);
  });

  testWidgets('non-video transfers open their details', (tester) async {
    await pumpTile(tester, buildTask('c', status: TransferStatus.completed, transferred: 1000, serverFileName: 'c.csv'));

    await tester.tap(find.text('c.csv'));
    await tester.pumpAndSettle();

    expect(pushed.single.name, RoutesName.transferDetails);
  });

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

  group('network health', () {
    TransferTask running(NetworkHealth health, {bool upload = false, int speed = 0}) => TransferTask(
      id: 'n',
      type: upload ? TransferType.upload : TransferType.download,
      fileName: 'catalog.csv',
      localPath: '/tmp/catalog.csv',
      totalBytes: 1000,
      transferredBytes: 400,
      status: TransferStatus.running,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
      serverFileName: 'catalog_1.csv',
      networkHealth: health,
      bytesPerSecond: speed,
    );

    Color barColor(WidgetTester tester) => tester.widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator)).color!;

    testWidgets('good connection keeps the normal bar color and shows speed', (tester) async {
      await pumpTile(tester, running(NetworkHealth.good, speed: 1536 * 1024));
      expect(find.textContaining('Good connection'), findsOneWidget);
      expect(find.textContaining('/s'), findsOneWidget);
      expect(barColor(tester), AppColors.primary);
      expect(find.text('40%'), findsOneWidget);
    });

    testWidgets('poor connection tints the bar amber but keeps the real percentage', (tester) async {
      await pumpTile(tester, running(NetworkHealth.poor, speed: 10 * 1024));
      expect(find.textContaining('Poor connection'), findsOneWidget);
      expect(barColor(tester).toARGB32() & 0xFFFFFF, AppColors.warning.toARGB32() & 0xFFFFFF);
      expect(find.text('40%'), findsOneWidget);
    });

    testWidgets('connection lost turns the bar red, hides speed and keeps progress', (tester) async {
      await pumpTile(tester, running(NetworkHealth.offline, speed: 99999));
      expect(find.textContaining('Connection lost'), findsOneWidget);
      expect(find.textContaining('/s'), findsNothing);
      expect(barColor(tester).toARGB32() & 0xFFFFFF, AppColors.error.toARGB32() & 0xFFFFFF);
      expect(find.text('40%'), findsOneWidget);
    });

    testWidgets('a resumed upload says it restarted rather than resumed', (tester) async {
      await pumpTile(tester, running(NetworkHealth.resumed, upload: true));
      expect(find.textContaining('Upload restarted'), findsOneWidget);
    });

    testWidgets('no network indicator for paused or finished transfers', (tester) async {
      await pumpTile(tester, uploadedVideo());
      expect(find.textContaining('connection'), findsNothing);
    });

    test('notification text follows the network state', () {
      expect(NotificationService.progressText(running(NetworkHealth.offline)).title, 'Waiting for network');
      expect(NotificationService.progressText(running(NetworkHealth.reconnecting)).title, 'Reconnecting…');
      expect(NotificationService.progressText(running(NetworkHealth.resumed, upload: true)).title, 'Restarting upload…');
      expect(NotificationService.progressText(running(NetworkHealth.resumed)).title, 'Resuming download…');
      expect(NotificationService.progressText(running(NetworkHealth.poor)).body, startsWith('Poor network connection · 40%'));
      expect(NotificationService.progressText(running(NetworkHealth.good, upload: true)).title, 'Uploading…');
      final paused = running(NetworkHealth.offline).copyWith(status: TransferStatus.paused);
      expect(NotificationService.progressText(paused).title, 'Download paused due to connection loss');
    });
  });
}
