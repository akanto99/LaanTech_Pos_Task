import 'dart:io';

import 'package:flutter/services.dart';
import 'package:laantech_pos_task/configs/res/app_config.dart';
import 'package:laantech_pos_task/configs/utils/file_names.dart';
import 'package:laantech_pos_task/data/app_exceptions.dart';
import 'package:laantech_pos_task/data/storage/base_download_storage.dart';
import 'package:path_provider/path_provider.dart';
import 'package:public_downloads/public_downloads.dart';

/// Saves completed downloads to the public `Download/LaanTech/` folder.
///
/// Android 10+ uses MediaStore (no permission, file hidden until complete);
/// Android 7-9 uses WRITE_EXTERNAL_STORAGE. Other platforms, which have no
/// shared Download folder, fall back to the app's documents directory.
class PublicDownloadStorage extends BaseDownloadStorage {
  PublicDownloadStorage({PublicDownloads plugin = const PublicDownloads()}) : _plugin = plugin;

  final PublicDownloads _plugin;

  @override
  Future<PublishedDownload> publish({required String sourcePath, required String fileName}) async {
    if (!Platform.isAndroid) return _publishToDocuments(sourcePath, fileName);
    try {
      final published = await _plugin.publish(sourcePath: sourcePath, fileName: fileName, folder: AppConfig.publicDownloadFolder);
      await _deleteQuietly(sourcePath);
      return (path: published.path, size: published.size);
    } on PlatformException catch (e) {
      throw _map(e);
    } on MissingPluginException {
      throw const StorageException('Saving to the Download folder is not supported on this device.');
    }
  }

  @override
  Future<bool> ensureWriteAccess() async {
    if (!Platform.isAndroid) return true;
    try {
      return await _plugin.hasWriteAccess() || await _plugin.requestWriteAccess();
    } on PlatformException catch (e) {
      throw _map(e);
    }
  }

  Future<PublishedDownload> _publishToDocuments(String sourcePath, String fileName) async {
    try {
      final directory = await Directory('${(await getApplicationDocumentsDirectory()).path}/${AppConfig.publicDownloadFolder}').create(recursive: true);
      final destination = FileNames.available('${directory.path}/$fileName', (path) => File(path).existsSync());
      final file = await File(sourcePath).rename(destination);
      return (path: file.path, size: await file.length());
    } on FileSystemException catch (e) {
      throw StorageException('Could not save the file: ${e.message}');
    }
  }

  Future<void> _deleteQuietly(String path) async {
    try {
      await File(path).delete();
    } on FileSystemException {
      // The public copy is complete; a leftover staging file is harmless.
    }
  }

  AppException _map(PlatformException e) => switch (e.code) {
    'permission_denied' => const StorageException('Storage permission is required to save files to Download/${AppConfig.publicDownloadFolder}.'),
    'no_space' => const StorageException('Not enough storage space on this device.'),
    'source_missing' => const StorageException('The downloaded data was lost. Retry to download it again.'),
    _ => StorageException('Could not save the file to Download/${AppConfig.publicDownloadFolder}: ${e.message ?? e.code}'),
  };
}
