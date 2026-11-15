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

  static String dateTime(DateTime? date) => date == null
      ? '—'
      : DateFormat('dd MMM yyyy, hh:mm a').format(date.toLocal());
}
