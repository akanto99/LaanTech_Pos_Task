import 'package:flutter/material.dart';

abstract final class AppColors {
  static const Color primary = Color(0xFF1F4FD8);
  static const Color secondary = Color(0xFF0EA5A4);
  static const Color error = Color(0xFFDC2626);
  static const Color success = Color(0xFF16A34A);
  static const Color warning = Color(0xFFD97706);
  static const Color whiteColor = Colors.white;
  static const Color blackColor = Colors.black;
  static const Color greyColor = Colors.grey;

  static bool _isDark(BuildContext c) =>
      Theme.of(c).brightness == Brightness.dark;

  static Color textPrimary(BuildContext c) =>
      _isDark(c) ? Colors.grey.shade100 : const Color(0xFF111827);
  static Color textSecondary(BuildContext c) =>
      _isDark(c) ? Colors.grey.shade400 : const Color(0xFF6B7280);
  static Color subtitle(BuildContext c) => textSecondary(c);
  static Color appBackground(BuildContext c) =>
      _isDark(c) ? const Color(0xFF0F172A) : const Color(0xFFF3F5F9);
  static Color containerBackground(BuildContext c) =>
      _isDark(c) ? const Color(0xFF1E293B) : whiteColor;
  static Color border(BuildContext c) =>
      _isDark(c) ? const Color(0xFF334155) : const Color(0xFFE5E7EB);
  static Color textFieldFill(BuildContext c) =>
      _isDark(c) ? const Color(0xFF273449) : const Color(0xFFF3F4F6);
  static Color flushbarColor(BuildContext c) =>
      _isDark(c) ? Colors.black54 : Colors.black12;
}
