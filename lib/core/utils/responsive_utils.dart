// lib/core/utils/responsive_utils.dart
import 'package:flutter/material.dart';

class ResponsiveUtils {
  static double getWidth(BuildContext context) {
    return MediaQuery.of(context).size.width;
  }

  static double getHeight(BuildContext context) {
    return MediaQuery.of(context).size.height;
  }

  static bool isMobile(BuildContext context) {
    return getWidth(context) < 600;
  }

  static bool isTablet(BuildContext context) {
    return getWidth(context) >= 600 && getWidth(context) < 1024;
  }

  static bool isDesktop(BuildContext context) {
    return getWidth(context) >= 1024;
  }

  static double getResponsiveFontSize(BuildContext context, double size) {
    double baseWidth = 375; // iPhone SE width
    return size * (getWidth(context) / baseWidth);
  }

  static double getResponsivePadding(BuildContext context) {
    if (isMobile(context)) return 16.0;
    if (isTablet(context)) return 32.0;
    return 48.0;
  }

  static EdgeInsets getResponsiveInsets(BuildContext context) {
    final padding = getResponsivePadding(context);
    return EdgeInsets.all(padding);
  }

  static double getScaledSize(BuildContext context, double size) {
    final width = getWidth(context);
    if (width < 360) {
      return size * 0.85; // Small phones
    } else if (width < 400) {
      return size * 0.95; // Medium phones
    } else if (width > 600) {
      return size * 1.1; // Tablets
    }
    return size; // Default
  }
}