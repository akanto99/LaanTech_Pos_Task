import 'package:flutter/material.dart';

/// Breakpoints and screen-relative sizing shared by every screen.
///
/// Sizes follow the same rule as [SizedboxSpaccing]: a fraction of the
/// screen, where horizontal values scale with the width and vertical values
/// with the height. On a typical 393 x 852 dp phone a width fraction of 0.04
/// is about 16 dp and a height fraction of 0.02 about 17 dp. Text sizes are
/// not scaled here: they follow the theme and the user's text-size setting.
class ResPonsiveUi extends StatelessWidget {
  final Widget mobile;
  final Widget? tablet;
  final Widget? desktop;

  const ResPonsiveUi({super.key, required this.mobile, this.tablet, this.desktop});

  static bool isMobile(BuildContext context) => MediaQuery.sizeOf(context).width < 800;

  static bool isTablet(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    return width >= 800 && width < 1200;
  }

  static bool isDesktop(BuildContext context) => MediaQuery.sizeOf(context).width >= 1200;

  /// [fraction] of the screen width.
  static double width(BuildContext context, double fraction) => MediaQuery.sizeOf(context).width * fraction;

  /// [fraction] of the screen height.
  static double height(BuildContext context, double fraction) => MediaQuery.sizeOf(context).height * fraction;

  /// Padding from screen fractions: [horizontal] of the width, [vertical] of the height.
  static EdgeInsets padding(BuildContext context, {double horizontal = 0, double vertical = 0}) =>
      EdgeInsets.symmetric(horizontal: width(context, horizontal), vertical: height(context, vertical));

  /// Padding from screen fractions: left/right of the width, top/bottom of the height.
  static EdgeInsets paddingLTRB(BuildContext context, double left, double top, double right, double bottom) =>
      EdgeInsets.fromLTRB(width(context, left), height(context, top), width(context, right), height(context, bottom));

  /// Standard screen padding (about 16 dp on a typical phone).
  static EdgeInsets pagePadding(BuildContext context) => padding(context, horizontal: 0.04, vertical: 0.02);

  /// Standard padding inside cards (about 20 dp on a typical phone).
  static EdgeInsets cardPadding(BuildContext context) => padding(context, horizontal: 0.05, vertical: 0.022);

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= 1200) {
          return desktop ?? tablet ?? mobile;
        } else if (constraints.maxWidth >= 800) {
          return tablet ?? mobile;
        } else {
          return mobile;
        }
      },
    );
  }
}
