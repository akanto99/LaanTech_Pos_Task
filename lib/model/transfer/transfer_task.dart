import 'package:laantech_pos_task/configs/utils/file_names.dart';
import 'package:laantech_pos_task/model/transfer/network_health.dart';

enum TransferType { upload, download }

enum TransferStatus {
  pending,
  running,
  paused,
  completed,
  failed,
  cancelled;

  bool get isActive => this == pending || this == running;
  bool get isFinished => this == completed || this == failed || this == cancelled;
}

class TransferTask {
  final String id;
  final TransferType type;
  final String fileName;

  /// Upload: the picked source file. Download: the final destination file.
  final String localPath;
  final int totalBytes;
  final int transferredBytes;
  final TransferStatus status;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? error;

  /// Server-side unique file name (returned after upload, source for download).
  final String? serverFileName;
  final String? remoteUrl;

  /// Link condition while running. Meaningful only for running transfers.
  final NetworkHealth networkHealth;

  /// Measured throughput of the current attempt; 0 when unknown or waiting.
  final int bytesPerSecond;

  /// Download: the server `ETag` of the partial file, so a resumed Range
  /// request is only appended when the file on the server is unchanged.
  final String? etag;

  /// Upload: when the whole body was last sent. If the response is then lost,
  /// the server may already have the file; a retry checks before re-uploading.
  final DateTime? bodySentAt;

  const TransferTask({
    required this.id,
    required this.type,
    required this.fileName,
    required this.localPath,
    required this.totalBytes,
    required this.transferredBytes,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    this.error,
    this.serverFileName,
    this.remoteUrl,
    this.networkHealth = NetworkHealth.good,
    this.bytesPerSecond = 0,
    this.etag,
    this.bodySentAt,
  });

  bool get isUpload => type == TransferType.upload;

  double get progress => totalBytes > 0 ? (transferredBytes / totalBytes).clamp(0, 1).toDouble() : 0;

  int get percent => (progress * 100).floor();

  /// The backend accepts uploads only as a single multipart request, so only
  /// downloads (HTTP Range) can genuinely pause and resume.
  bool get canPause => !isUpload && status.isActive;
  bool get canResume => status == TransferStatus.paused;
  bool get canRetry => status == TransferStatus.failed || status == TransferStatus.cancelled;
  bool get canCancel => status.isActive || status == TransferStatus.paused;

  String get partialPath => '$localPath.part';

  /// A finished transfer of a video references a server file that can be streamed.
  bool get canPlayVideo => status == TransferStatus.completed && serverFileName != null && FileNames.isVideo(fileName);

  TransferTask copyWith({
    String? localPath,
    int? totalBytes,
    int? transferredBytes,
    TransferStatus? status,
    String? error,
    bool clearError = false,
    String? serverFileName,
    String? remoteUrl,
    NetworkHealth? networkHealth,
    int? bytesPerSecond,
    String? etag,
    bool clearEtag = false,
    DateTime? bodySentAt,
    bool clearBodySentAt = false,
  }) => TransferTask(
    id: id,
    type: type,
    fileName: fileName,
    localPath: localPath ?? this.localPath,
    totalBytes: totalBytes ?? this.totalBytes,
    transferredBytes: transferredBytes ?? this.transferredBytes,
    status: status ?? this.status,
    createdAt: createdAt,
    updatedAt: DateTime.now(),
    error: clearError ? null : error ?? this.error,
    serverFileName: serverFileName ?? this.serverFileName,
    remoteUrl: remoteUrl ?? this.remoteUrl,
    networkHealth: networkHealth ?? this.networkHealth,
    bytesPerSecond: bytesPerSecond ?? this.bytesPerSecond,
    etag: clearEtag ? null : etag ?? this.etag,
    bodySentAt: clearBodySentAt ? null : bodySentAt ?? this.bodySentAt,
  );

  factory TransferTask.fromJson(Map<String, dynamic> json) => TransferTask(
    id: json['id'] as String,
    type: TransferType.values.byName(json['type'] as String),
    fileName: json['fileName'] as String,
    localPath: json['localPath'] as String,
    totalBytes: (json['totalBytes'] as num).toInt(),
    transferredBytes: (json['transferredBytes'] as num).toInt(),
    status: TransferStatus.values.byName(json['status'] as String),
    createdAt: DateTime.parse(json['createdAt'] as String),
    updatedAt: DateTime.parse(json['updatedAt'] as String),
    error: json['error'] as String?,
    serverFileName: json['serverFileName'] as String?,
    remoteUrl: json['remoteUrl'] as String?,
    networkHealth: NetworkHealth.values.asNameMap()[json['networkHealth']] ?? NetworkHealth.good,
    bytesPerSecond: (json['bytesPerSecond'] as num?)?.toInt() ?? 0,
    etag: json['etag'] as String?,
    bodySentAt: DateTime.tryParse(json['bodySentAt'] as String? ?? ''),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type.name,
    'fileName': fileName,
    'localPath': localPath,
    'totalBytes': totalBytes,
    'transferredBytes': transferredBytes,
    'status': status.name,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
    'error': error,
    'serverFileName': serverFileName,
    'remoteUrl': remoteUrl,
    'networkHealth': networkHealth.name,
    'bytesPerSecond': bytesPerSecond,
    'etag': etag,
    'bodySentAt': bodySentAt?.toIso8601String(),
  };
}
