import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:laantech_pos_task/data/storage/public_download_storage.dart';
import 'package:laantech_pos_task/data/transfer/transfer_store.dart';

/// Runs the real MediaStore plugin on a device or emulator:
/// `flutter test integration_test/public_download_storage_test.dart`
///
/// Files are left in Download/LaanTech so they can be checked in the Files
/// app or with `adb shell ls /sdcard/Download/LaanTech`.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  test('publishes into Download/LaanTech without overwriting', () async {
    final storage = PublicDownloadStorage();
    final staging = await TransferStore().stagingDirectory();
    final name = 'it_products_${DateTime.now().millisecondsSinceEpoch}.csv';

    Future<File> stage(String content) => File('${staging.path}/$name.part').writeAsString(content);

    expect(await storage.ensureWriteAccess(), isTrue);

    final firstSource = await stage('sku,price\nA,1\n');
    final first = await storage.publish(sourcePath: firstSource.path, fileName: name);
    final secondSource = await stage('sku,price\nB,2\n');
    final second = await storage.publish(sourcePath: secondSource.path, fileName: name);

    expect(first.path, '/storage/emulated/0/Download/LaanTech/$name');
    expect(second.path, '/storage/emulated/0/Download/LaanTech/${name.replaceFirst('.csv', ' (1).csv')}');
    expect(first.size, 14);
    expect(firstSource.existsSync(), isFalse, reason: 'staging copy is removed after publishing');
    expect(secondSource.existsSync(), isFalse);
    // ignore: avoid_print
    print('PUBLISHED ${first.path} | ${second.path}');
  });

  test('a missing staged file is reported as a storage error', () async {
    await expectLater(
      PublicDownloadStorage().publish(sourcePath: '/data/local/tmp/does-not-exist.part', fileName: 'x.csv'),
      throwsA(isA<Exception>().having((e) => e.toString(), 'message', contains('lost'))),
    );
  });
}
