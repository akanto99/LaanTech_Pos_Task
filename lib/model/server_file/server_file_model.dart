import 'package:laantech_pos_task/configs/utils/file_names.dart';

class ServerFileModel {
  final int id;

  /// Unique name assigned by the server; used for download and delete.
  final String name;
  final String originalName;
  final int size;
  final String type;
  final DateTime? uploadedAt;
  final String url;

  bool get isVideo => type.startsWith('video/') || FileNames.isVideo(originalName);

  const ServerFileModel({required this.id, required this.name, required this.originalName, required this.size, required this.type, required this.uploadedAt, required this.url});

  factory ServerFileModel.fromJson(Map<String, dynamic> json) {
    final name = json['name'] as String;
    return ServerFileModel(
      id: (json['id'] as num).toInt(),
      name: name,
      originalName: json['original_name'] as String? ?? name,
      size: (json['size'] as num?)?.toInt() ?? 0,
      type: json['type'] as String? ?? 'application/octet-stream',
      uploadedAt: DateTime.tryParse(json['uploaded_at'] as String? ?? '')?.toLocal(),
      url: json['url'] as String? ?? '',
    );
  }

  static List<ServerFileModel> listFromJson(dynamic json) =>
      ((json as Map<String, dynamic>)['files'] as List<dynamic>? ?? []).map((file) => ServerFileModel.fromJson(file as Map<String, dynamic>)).toList();
}
