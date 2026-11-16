import 'package:flutter/material.dart';

class AppTextStyles {
  static TextStyle _style(BuildContext c, TextStyle? base, double fallbackSize, FontWeight defaultWeight, FontWeight? weight, Color? color) =>
      (base ?? TextStyle(fontSize: fallbackSize)).copyWith(fontWeight: weight ?? defaultWeight, color: color);

  static TextStyle textSize24(BuildContext c, {FontWeight? weight, Color? color}) => _style(c, Theme.of(c).textTheme.headlineSmall, 24, FontWeight.w600, weight, color);
  static TextStyle textSize20(BuildContext c, {FontWeight? weight, Color? color}) => _style(c, Theme.of(c).textTheme.titleMedium, 20, FontWeight.w500, weight, color);
  static TextStyle textSize18(BuildContext c, {FontWeight? weight, Color? color}) => _style(c, Theme.of(c).textTheme.titleSmall, 18, FontWeight.w500, weight, color);
  static TextStyle textSize16(BuildContext c, {FontWeight? weight, Color? color}) => _style(c, Theme.of(c).textTheme.bodyLarge, 16, FontWeight.w400, weight, color);
  static TextStyle textSize14(BuildContext c, {FontWeight? weight, Color? color}) => _style(c, Theme.of(c).textTheme.bodyMedium, 14, FontWeight.w400, weight, color);
  static TextStyle textSize12(BuildContext c, {FontWeight? weight, Color? color}) => _style(c, Theme.of(c).textTheme.bodySmall, 12, FontWeight.w400, weight, color);
}
