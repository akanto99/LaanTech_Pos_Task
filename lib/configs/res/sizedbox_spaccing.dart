import 'package:flutter/material.dart';

/// Gaps sized as a fraction of the screen: widths of the screen width,
/// heights of the screen height (see [ResPonsiveUi] for padding helpers).
/// On a typical 393 x 852 dp phone: width01 ≈ 4, width02 ≈ 8, width03 ≈ 12,
/// height005 ≈ 4, height01 ≈ 9, height015 ≈ 13, height02 ≈ 17, height03 ≈ 26.
class SizedboxSpaccing {
  /// Width-based SizedBox getters
  static SizedBox width01(BuildContext context) =>
      SizedBox(width: MediaQuery.sizeOf(context).width * 0.01);

  static SizedBox width015(BuildContext context) =>
      SizedBox(width: MediaQuery.sizeOf(context).width * 0.015);

  static SizedBox width02(BuildContext context) =>
      SizedBox(width: MediaQuery.sizeOf(context).width * 0.02);

  static SizedBox width025(BuildContext context) =>
      SizedBox(width: MediaQuery.sizeOf(context).width * 0.025);

  static SizedBox width03(BuildContext context) =>
      SizedBox(width: MediaQuery.sizeOf(context).width * 0.03);

  static SizedBox width035(BuildContext context) =>
      SizedBox(width: MediaQuery.sizeOf(context).width * 0.035);

  /// Height-based SizedBox getters
  static SizedBox height005(BuildContext context) =>
      SizedBox(height: MediaQuery.sizeOf(context).height * 0.005);

  static SizedBox height0075(BuildContext context) =>
      SizedBox(height: MediaQuery.sizeOf(context).height * 0.0075);

  static SizedBox height01(BuildContext context) =>
      SizedBox(height: MediaQuery.sizeOf(context).height * 0.01);

  static SizedBox height0125(BuildContext context) =>
      SizedBox(height: MediaQuery.sizeOf(context).height * 0.0125);

  static SizedBox height015(BuildContext context) =>
      SizedBox(height: MediaQuery.sizeOf(context).height * 0.015);

  static SizedBox height02(BuildContext context) =>
      SizedBox(height: MediaQuery.sizeOf(context).height * 0.02);

  static SizedBox height025(BuildContext context) =>
      SizedBox(height: MediaQuery.sizeOf(context).height * 0.025);

  static SizedBox height03(BuildContext context) =>
      SizedBox(height: MediaQuery.sizeOf(context).height * 0.03);

  static SizedBox height04(BuildContext context) =>
      SizedBox(height: MediaQuery.sizeOf(context).height * 0.04);
}
