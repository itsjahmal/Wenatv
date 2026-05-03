import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'app_typography.dart';

class AppTheme {
  const AppTheme._();

  static ThemeData get dark {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: AppColors.background,
      colorScheme: const ColorScheme.dark(
        primary: AppColors.accentRed,
        surface: AppColors.surface,
        secondary: AppColors.textPrimary,
      ),
      fontFamily: 'Roboto',
      textTheme: const TextTheme(
        displayLarge: AppTypography.heroTitle,
        headlineLarge: AppTypography.screenTitle,
        headlineMedium: AppTypography.sectionTitle,
        titleLarge: AppTypography.title,
        bodyLarge: AppTypography.body,
        bodyMedium: AppTypography.metadata,
        labelLarge: AppTypography.label,
      ),
    );
  }

  static ThemeData get light {
    return dark.copyWith(
      brightness: Brightness.light,
      scaffoldBackgroundColor: const Color(0xFFF4F4F4),
      colorScheme: const ColorScheme.light(
        primary: AppColors.accentRed,
        surface: Color(0xFFFFFFFF),
        secondary: Color(0xFF111111),
      ),
    );
  }
}
