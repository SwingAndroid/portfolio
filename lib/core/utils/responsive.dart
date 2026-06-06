import 'package:flutter/material.dart';

/// Screen-size breakpoints used throughout the app.
class Responsive {
  static const double _mobile = 600;
  static const double _tablet = 1024;

  static bool isMobile(BuildContext context) =>
      MediaQuery.sizeOf(context).width < _mobile;

  static bool isTablet(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    return w >= _mobile && w < _tablet;
  }

  static bool isDesktop(BuildContext context) =>
      MediaQuery.sizeOf(context).width >= _tablet;

  static bool isWide(BuildContext context) =>
      MediaQuery.sizeOf(context).width >= _mobile;

  /// Returns one of three values depending on current breakpoint.
  static T value<T>(
    BuildContext context, {
    required T mobile,
    T? tablet,
    required T desktop,
  }) {
    if (isDesktop(context)) return desktop;
    if (isTablet(context)) return tablet ?? desktop;
    return mobile;
  }

  /// Horizontal content padding that grows on wider screens.
  static double horizontalPadding(BuildContext context) =>
      value(context, mobile: 16, tablet: 32, desktop: 0);

  /// Max width for centered content columns on large screens.
  static const double maxContentWidth = 1280;
  static const double sidebarWidth = 300;
  static const double detailMinWidth = 480;
}
