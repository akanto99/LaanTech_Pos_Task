import 'package:flutter/foundation.dart';
import 'package:laantech_pos_task/data/app_exceptions.dart';
import 'package:laantech_pos_task/data/response/api_response.dart';
import 'package:laantech_pos_task/model/server_file/server_file_model.dart';
import 'package:laantech_pos_task/repository/file_repository/file_repository.dart';

class ServerFilesViewModel with ChangeNotifier {
  ServerFilesViewModel({FileRepository? repository}) : _repository = repository ?? FileRepository();

  final FileRepository _repository;

  ApiResponse<List<ServerFileModel>> files = const ApiResponse.loading();
  final Set<String> _deleting = {};

  bool isDeleting(String name) => _deleting.contains(name);

  Future<void> fetchFiles({bool silent = false}) async {
    if (!silent) {
      files = const ApiResponse.loading();
      notifyListeners();
    }
    try {
      files = ApiResponse.completed(await _repository.fetchFiles());
    } catch (error) {
      files = ApiResponse.error(_message(error));
    }
    notifyListeners();
  }

  /// Returns a user-facing error message, or `null` on success.
  Future<String?> deleteFile(ServerFileModel file) async {
    _deleting.add(file.name);
    notifyListeners();
    try {
      await _repository.deleteFile(file.name);
      files = ApiResponse.completed(files.data!.where((item) => item.name != file.name).toList());
      return null;
    } catch (error) {
      return _message(error);
    } finally {
      _deleting.remove(file.name);
      notifyListeners();
    }
  }

  String _message(Object error) => error is AppException ? error.message : 'Something went wrong. Please try again.';
}
