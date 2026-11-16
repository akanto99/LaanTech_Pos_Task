import 'package:flutter/services.dart';

/// Raw result of [PublicDownloads.publish].
typedef PublishedFile = ({String path, String uri, String name, int size});

/// Thin Dart binding for the Android `PublicDownloadsPlugin`.
///
/// Errors surface as [PlatformException] with one of the codes
/// `permission_denied`, `source_missing`, `no_space`, `io_error`, `busy` or
/// `invalid_arguments`.
class PublicDownloads {
  const PublicDownloads();

  static const _channel = MethodChannel('laantech/public_downloads');

  /// Copies [sourcePath] into `Download/<folder>/` under [fileName] (or a
  /// free "name (n).ext" variant). The source file is left in place.
  Future<PublishedFile> publish({required String sourcePath, required String fileName, required String folder}) async {
    final result = await _channel.invokeMapMethod<String, Object?>('publish', {'sourcePath': sourcePath, 'fileName': fileName, 'folder': folder});
    if (result == null) throw PlatformException(code: 'io_error', message: 'The file could not be saved to Downloads.');
    return (path: result['path']! as String, uri: result['uri']! as String, name: result['name']! as String, size: (result['size']! as num).toInt());
  }

  /// Always true on Android 10+, where MediaStore needs no permission.
  Future<bool> hasWriteAccess() async => await _channel.invokeMethod<bool>('hasWriteAccess') ?? false;

  /// Asks for WRITE_EXTERNAL_STORAGE on Android 7-9. Needs a foreground Activity.
  Future<bool> requestWriteAccess() async => await _channel.invokeMethod<bool>('requestWriteAccess') ?? false;
}
