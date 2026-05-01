import 'package:flutter/material.dart';

class AppColors {
  const AppColors._();

  static const background = Color(0xFF050505);
  static const black = Color(0xFF050505);
  static const surface = Color(0xFF111111);
  static const surfaceSoft = Color(0xFF181818);
  static const surfaceElevated = Color(0xFF202020);
  static const accentRed = Color(0xFFE50914);
  static const textPrimary = Colors.white;
  static const textSecondary = Color(0xFFB8B8B8);
  static const textMuted = Color(0xFF7E7E7E);
  static const borderSubtle = Color(0x1FFFFFFF);
  static const gold = Color(0xFFFFC400);

  static Color scrim(double opacity) => Colors.black.withValues(alpha: opacity);
  static Color white(double opacity) => Colors.white.withValues(alpha: opacity);
  static Color red(double opacity) => accentRed.withValues(alpha: opacity);
}
