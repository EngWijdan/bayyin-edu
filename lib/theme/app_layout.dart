import 'package:flutter/material.dart';

/// Shared breakpoints and content widths. Screens read these instead of
/// repeating MediaQuery checks, so mobile stays the default layout.
abstract final class AppLayout {
  static const double mobile = 600;
  static const double tablet = 1024;

  static const double formMaxWidth = 720;
  static const double compactMaxWidth = 800;
  static const double dashboardMaxWidth = 1120;

  static bool isMobile(double width) => width < mobile;
  static bool isTablet(double width) => width >= mobile && width < tablet;
  static bool isDesktop(double width) => width >= tablet;

  static bool isCompact(BuildContext context) =>
      MediaQuery.sizeOf(context).width < mobile;

  static bool isWide(BuildContext context) =>
      MediaQuery.sizeOf(context).width >= tablet;

  static int columnsFor(
    double width, {
    int mobile = 1,
    int tablet = 2,
    int desktop = 2,
  }) {
    if (width >= AppLayout.tablet) return desktop;
    if (width >= AppLayout.mobile) return tablet;
    return mobile;
  }

  static EdgeInsets pagePaddingOf(double width) {
    if (width >= tablet) {
      return const EdgeInsets.fromLTRB(32, 20, 32, 32);
    }
    if (width >= mobile) {
      return const EdgeInsets.fromLTRB(24, 16, 24, 28);
    }
    return const EdgeInsets.fromLTRB(20, 12, 20, 28);
  }

  static EdgeInsets barPaddingOf(double width) {
    if (width >= tablet) {
      return const EdgeInsets.fromLTRB(32, 8, 32, 16);
    }
    if (width >= mobile) {
      return const EdgeInsets.fromLTRB(24, 8, 24, 16);
    }
    return const EdgeInsets.fromLTRB(20, 8, 20, 16);
  }
}
