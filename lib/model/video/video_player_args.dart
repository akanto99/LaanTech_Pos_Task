/// Route arguments for `RoutesName.videoPlayer`.
class VideoPlayerArgs {
  const VideoPlayerArgs({required this.serverFileName, required this.title});

  /// Unique server-side name used by `GET /get?file=`.
  final String serverFileName;
  final String title;
}
