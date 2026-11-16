import 'dart:io';

import 'package:laantech_pos_task/configs/res/app_config.dart';

abstract final class FileNames {
  /// Returns [desired], or the first free "name (n).ext" variant of it, so an
  /// existing file is never overwritten. Only the last path segment is renamed.
  static String available(String desired, bool Function(String candidate) taken) {
    final dot = desired.lastIndexOf('.');
    final slash = desired.lastIndexOf(Platform.pathSeparator);
    final hasExtension = dot > slash + 1;
    final base = hasExtension ? desired.substring(0, dot) : desired;
    final extension = hasExtension ? desired.substring(dot) : '';

    var candidate = desired;
    for (var copy = 1; taken(candidate); copy++) {
      candidate = '$base ($copy)$extension';
    }
    return candidate;
  }

  static bool isVideo(String fileName) {
    final dot = fileName.lastIndexOf('.');
    return dot > 0 && AppConfig.videoExtensions.contains(fileName.substring(dot + 1).toLowerCase());
  }
}
