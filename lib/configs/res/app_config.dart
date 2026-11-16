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

  /// Backoff for automatic reloads after a network failure. Having a network
  /// (connectivity) does not mean the API is reachable yet, e.g. while DNS or
  /// a captive portal settles, so a reload that still fails is retried.
  static const List<Duration> reconnectRetryDelays = [Duration(seconds: 2), Duration(seconds: 5), Duration(seconds: 10)];

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
