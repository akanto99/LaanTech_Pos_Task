/// Where a finished download ended up.
typedef PublishedDownload = ({String path, int size});

/// Final, user-visible destination for completed downloads.
///
/// Downloads are written (and resumed) in app-private staging; only a fully
/// downloaded file is handed to [publish], so partial data is never exposed.
abstract class BaseDownloadStorage {
  /// Moves the staged file at [sourcePath] to the public destination as
  /// [fileName] (or a free "name (n).ext" variant) and deletes the source.
  Future<PublishedDownload> publish({required String sourcePath, required String fileName});

  /// Makes sure the destination is writable, asking the user if the platform
  /// requires it. Returns false when access was denied.
  Future<bool> ensureWriteAccess();
}
