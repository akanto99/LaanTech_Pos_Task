import 'package:flutter/services.dart';

class AppConfig {
  static const String appName = 'LaanTech POS';

  /// Completed downloads are saved to the public `Download/<this>/` folder.
  static const String publicDownloadFolder = 'LaanTech';

  /// App-wide orientations; the video player restores these after fullscreen.
  static const List<DeviceOrientation> orientations = [DeviceOrientation.portraitUp, DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight];

  static const Duration connectTimeout = Duration(seconds: 20);
  static const Duration apiTimeout = Duration(seconds: 30);
  // Idle timeout between data chunks, so slow-but-moving transfers are never killed.
  static const Duration transferIdleTimeout = Duration(seconds: 60);

  static const int maxConcurrentTransfers = 2;
  static const int maxAutoRetries = 5;
  static const Duration retryBaseDelay = Duration(seconds: 3);
  static const int maxHistory = 100;

  // --- Transfer network health ---------------------------------------------

  /// How often running transfers are re-evaluated (speed, slow, stalled, offline).
  static const Duration networkHealthTick = Duration(seconds: 1);

  /// Throughput is averaged over this sliding window, so one slow chunk or a
  /// burst into the socket buffer does not flip the state.
  static const Duration throughputWindow = Duration(seconds: 8);

  /// No classification right after an attempt starts: TCP slow start and the
  /// first progress events are not representative.
  static const Duration networkHealthWarmup = Duration(seconds: 3);

  /// Below this average rate a moving transfer is reported as a poor connection…
  static const int poorThroughputBytesPerSecond = 32 * 1024;

  /// …and it must recover above this rate to be good again (hysteresis).
  static const int goodThroughputBytesPerSecond = 64 * 1024;

  /// No bytes for this long (while online) is reported as stalled. The request
  /// is only aborted after [transferIdleTimeout].
  static const Duration stallWarningAfter = Duration(seconds: 10);

  /// "Resumed" stays visible this long after a transfer restarts.
  static const Duration resumedNoticeDuration = Duration(seconds: 4);

  /// When the device reports no network, a request that has also stopped
  /// moving for this long is aborted instead of waiting for the idle timeout.
  /// Short network blips that do not stop the data are left alone.
  static const Duration offlineAbortAfter = Duration(seconds: 10);

  /// A transfer waits this long for the network to come back. After that a
  /// download is paused (it can be resumed later) and an upload fails.
  static const Duration networkWaitLimit = Duration(minutes: 30);

  /// Upper bound for exponential backoff between retries and reachability checks.
  static const Duration maxRetryDelay = Duration(seconds: 60);

  /// Timeout for the lightweight request that checks the server is reachable.
  static const Duration reachabilityTimeout = Duration(seconds: 8);

  /// A retried upload whose previous attempt sent the whole body first looks
  /// for a server file with the same name and size uploaded since then. This
  /// tolerance absorbs clock differences between the device and the server.
  static const Duration uploadMatchClockSkew = Duration(minutes: 2);

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
    ...videoExtensions,
    'mp3',
    'wav',
  ];

  /// Uploaded files with these extensions can be played in the app.
  static const List<String> videoExtensions = ['mp4', 'mov', 'mkv', 'webm', 'avi'];
}
