class AppConfig {
  static const String appName = 'LaanTech POS';

  /// Completed downloads are saved to the public `Download/<this>/` folder.
  static const String publicDownloadFolder = 'LaanTech';

  static const Duration connectTimeout = Duration(seconds: 20);
  static const Duration apiTimeout = Duration(seconds: 30);
  // Idle timeout between data chunks, so slow-but-moving transfers are never killed.
  static const Duration transferIdleTimeout = Duration(seconds: 60);

  static const int maxConcurrentTransfers = 2;
  static const int maxAutoRetries = 5;
  static const Duration retryBaseDelay = Duration(seconds: 3);
  static const int maxHistory = 100;

  /// Mirrors the server whitelist; anything else is rejected with HTTP 415.
  static const List<String> uploadExtensions = [
    'jpg',
    'jpeg',
    'png',
    'gif',
    'webp',
    'pdf',
    'txt',
    'csv',
    'doc',
    'docx',
    'xls',
    'xlsx',
    'zip',
    'json',
    'mp4',
    'mov',
    'mkv',
    'webm',
    'avi',
    'mp3',
    'wav',
  ];
}
