import 'package:flutter/material.dart';

class AppColors {
  static const Color primary = Color(0xFF0088CC); // Light blue from buttons
  static const Color secondary = Color(0xFF003366); // Dark blue for text/logo
  static const Color accent = Color(0xFF00AADD); // Brighter blue
  static const Color splashBackground = Color(0xFFAAD4F5); // Light blue splash
  static const Color danger = Color(0xFFCC0000); // SOS Red
  static const Color success = Color(0xFF28A745);
  static const Color white = Colors.white;
  static const Color grey = Color(0xFF9E9E9E);
  static const Color lightGrey = Color(0xFFF5F5F5);
  static const Color textDark = Color(0xFF333333);
  static const Color textLight = Color(0xFF777777);

  /// Page background behind cards. A near-white blue-grey rather than the
  /// saturated [splashBackground], so white cards read as raised instead of
  /// competing with the backdrop.
  static const Color canvas = Color(0xFFF2F6FA);
}