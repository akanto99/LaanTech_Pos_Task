import 'dart:io';

/// What the player should open for a server video.
sealed class VideoSource {
  const VideoSource();
}

/// Streamed progressively with HTTP Range requests. [headers] carry the
/// Bearer token, so it never appears in the URL.
class NetworkVideoSource extends VideoSource {
  const NetworkVideoSource(this.uri, {required this.headers});

  final Uri uri;
  final Map<String, String> headers;
}

/// Download-first fallback: a complete local copy in the app cache.
class FileVideoSource extends VideoSource {
  const FileVideoSource(this.file);

  final File file;
}
