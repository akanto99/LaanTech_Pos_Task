import 'dart:convert';
import 'dart:io';

import 'package:laantech_pos_task/model/transfer/transfer_task.dart';
import 'package:path_provider/path_provider.dart';

/// Persists transfer history as JSON so it survives app and service restarts.
class TransferStore {
  TransferStore({
    Future<Directory> Function()? dataDirectory,
    Future<Directory> Function()? stagingDirectory,
    Future<Directory> Function()? temporaryDirectory,
  }) : _dataDirectory = dataDirectory ?? getApplicationSupportDirectory,
       _stagingDirectory = stagingDirectory ?? getApplicationSupportDirectory,
       _temporaryDirectory = temporaryDirectory ?? getTemporaryDirectory;

  final Future<Directory> Function() _dataDirectory;
  final Future<Directory> Function() _stagingDirectory;
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

  /// App-private working area where downloads are written and resumed. It is
  /// invisible to file managers, so partial files are never exposed; finished
  /// files are moved to public storage by `BaseDownloadStorage.publish`.
  Future<Directory> stagingDirectory() async {
    final directory = Directory('${(await _stagingDirectory()).path}/download_staging');
    return directory.create(recursive: true);
  }
}
