import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:laantech_pos_task/main.dart' as app;
import 'package:laantech_pos_task/model/transfer/transfer_command.dart';
import 'package:laantech_pos_task/model/transfer/transfer_task.dart';
import 'package:laantech_pos_task/repository/transfer_repository/transfer_repository.dart';
import 'package:laantech_pos_task/view/home/home_view.dart';
import 'package:laantech_pos_task/view_model/transfer_view_model/transfer_view_model.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

/// Runs against the live mock API. Provide an existing account:
/// flutter test integration_test --dart-define=TEST_USERNAME=... --dart-define=TEST_PASSWORD=...
const _username = String.fromEnvironment('TEST_USERNAME');
const _password = String.fromEnvironment('TEST_PASSWORD');

Future<void> _pumpUntil(
  WidgetTester tester,
  bool Function() condition, {
  Duration timeout = const Duration(minutes: 3),
}) async {
  final end = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(end)) fail('Timed out waiting for condition');
    await tester.pump(const Duration(milliseconds: 250));
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'login, background upload and resumable download',
    (tester) async {
      app.main();
      await _pumpUntil(
        tester,
        () =>
            find.text('Welcome back').evaluate().isNotEmpty ||
            find.byType(HomeView).evaluate().isNotEmpty,
      );

      if (find.text('Welcome back').evaluate().isNotEmpty) {
        await tester.enterText(find.byType(TextFormField).at(0), _username);
        await tester.enterText(find.byType(TextFormField).at(1), _password);
        await tester.tap(find.text('Sign In'));
        await _pumpUntil(
          tester,
          () => find.byType(HomeView).evaluate().isNotEmpty,
        );
      }

      final transfers = Provider.of<TransferViewModel>(
        tester.element(find.byType(HomeView)),
        listen: false,
      );

      final bytes = List<int>.generate(
        512 * 1024,
        (_) => Random().nextInt(256),
      );
      final source = File(
        '${(await getTemporaryDirectory()).path}/it_upload.csv',
      )..writeAsBytesSync(bytes);
      final now = DateTime.now();
      final upload = TransferTask(
        id: 'it-upload-${now.microsecondsSinceEpoch}',
        type: TransferType.upload,
        fileName: 'it_upload.csv',
        localPath: source.path,
        totalBytes: bytes.length,
        transferredBytes: 0,
        status: TransferStatus.pending,
        createdAt: now,
        updatedAt: now,
      );
      final repository = TransferRepository();
      await repository.dispatch(
        TransferCommand(TransferAction.enqueue, tasks: [upload]),
      );

      await _pumpUntil(
        tester,
        () => transfers.byId(upload.id)?.status == TransferStatus.completed,
      );
      final serverName = transfers.byId(upload.id)!.serverFileName!;
      expect(serverName, startsWith('it_upload_'));

      await tester.tap(find.text('Server files'));
      await _pumpUntil(
        tester,
        () => find.byTooltip('Download').evaluate().isNotEmpty,
      );
      await tester.tap(find.byTooltip('Download').first);

      await _pumpUntil(
        tester,
        () =>
            transfers.latestDownloadOf(serverName)?.status ==
            TransferStatus.completed,
      );
      final downloaded = File(
        transfers.latestDownloadOf(serverName)!.localPath,
      );
      expect(downloaded.readAsBytesSync(), bytes);
    },
    skip: _username.isEmpty,
    timeout: const Timeout(Duration(minutes: 10)),
  );
}
