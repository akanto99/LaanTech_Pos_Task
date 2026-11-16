import 'package:laantech_pos_task/configs/res/app_url.dart';
import 'package:laantech_pos_task/data/network/base_api_services.dart';
import 'package:laantech_pos_task/data/network/network_api_service.dart';
import 'package:laantech_pos_task/model/server_file/server_file_model.dart';

class FileRepository {
  FileRepository({BaseApiServices? apiServices}) : _apiServices = apiServices ?? NetworkApiService();

  final BaseApiServices _apiServices;

  Future<List<ServerFileModel>> fetchFiles() async => ServerFileModel.listFromJson(await _apiServices.getGetApiResponse(AppUrl.files));

  Future<void> deleteFile(String name) => _apiServices.getDeleteApiResponse(AppUrl.deleteFileUrl(name));
}
