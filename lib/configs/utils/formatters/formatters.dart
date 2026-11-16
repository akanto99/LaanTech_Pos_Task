import 'package:intl/intl.dart';

class Formatters {
  Formatters._();

  static const _units = ['B', 'KB', 'MB', 'GB', 'TB'];

  static String fileSize(int bytes) {
    if (bytes <= 0) return '0 B';
    var size = bytes.toDouble();
    var unit = 0;
    while (size >= 1024 && unit < _units.length - 1) {
      size /= 1024;
      unit++;
    }
    return '${size.toStringAsFixed(unit == 0 || size >= 100 ? 0 : 1)} ${_units[unit]}';
  }

  /// 75 s → "1:15", 3725 s → "1:02:05".
  static String duration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return hours > 0 ? '$hours:${minutes.toString().padLeft(2, '0')}:$seconds' : '$minutes:$seconds';
  }

  static String dateTime(DateTime? date) => date == null
      ? '—'
      : DateFormat('dd MMM yyyy, hh:mm a').format(date.toLocal());
}
