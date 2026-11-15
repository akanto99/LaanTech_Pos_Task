import 'dart:convert';
import 'dart:io';

import 'package:laantech_pos_task/model/transfer/transfer_task.dart';
import 'package:path_provider/path_provider.dart';

/// Persists transfer history as JSON so it survives app and service restarts.
class TransferStore {
  TransferStore({
    Future<Directory> Function()? dataDirectory,
    Future<Directory> Function()? downloadsDirectory,
    Future<Directory> Function()? temporaryDirectory,
  }) : _dataDirectory = dataDirectory ?? getApplicationSupportDirectory,
       _downloadsDirectory = downloadsDirectory ?? _defaultDownloadsDirectory,
       _temporaryDirectory = temporaryDirectory ?? getTemporaryDirectory;

  final Future<Directory> Function() _dataDirectory;
  final Future<Directory> Function() _downloadsDirectory;
  final Future<Directory> Function() _temporaryDirectory;
  Future<void> _lastWrite = Future.value();

  Future<File> get _file async =>
      File('${(await _dataDirectory()).path}/transfers.json');

  Future<List<TransferTask>> load() async {
    try {
      final file = await _file;
      if (!await file.exists()) return [];
      return (jsonDecode(await file.readAsString()) as List<dynamic>)
          .map((json) => TransferTask.fromJson(json as Map<String, dynamic>))
          .toList();
    } on FormatException {
      return [];
    }
  }

  /// Writes are serialized and atomic (temp file + rename) so a crash never
  /// leaves a half-written history file.
  Future<void> save(List<TransferTask> tasks) {
    final json = jsonEncode(tasks.map((task) => task.toJson()).toList());
    return _lastWrite = _lastWrite.then((_) async {
      final file = await _file;
      final temp = File('${file.path}.tmp');
      await temp.writeAsString(json, flush: true);
      await temp.rename(file.path);
    });
  }

  /// The file picker copies selections into the app cache; those copies are
  /// app-owned and deleted once no longer needed. User files are never touched.
  Future<void> deleteIfTemporary(String path) async {
    final temporary = (await _temporaryDirectory()).path;
    final file = File(path);
    if (path.startsWith('$temporary/') && await file.exists()) {
      await file.delete();
    }
  }

  Future<Directory> downloadsDirectory() async {
    final directory = Directory(
      '${(await _downloadsDirectory()).path}/Downloads',
    );
    return directory.create(recursive: true);
  }

  /// App-specific external storage needs no runtime permission on any
  /// Android version and is visible over USB / in Files on most devices.
  static Future<Directory> _defaultDownloadsDirectory() async =>
      (Platform.isAndroid ? await getExternalStorageDirectory() : null) ??
      await getApplicationDocumentsDirectory();
}
