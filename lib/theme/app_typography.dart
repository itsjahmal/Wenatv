import 'package:flutter/material.dart';

import 'app_colors.dart';

class AppTypography {
  const AppTypography._();

  static const heroTitle = TextStyle(
    color: AppColors.textPrimary,
    fontSize: 40,
    height: 1.05,
    fontWeight: FontWeight.w900,
  );

  static const screenTitle = TextStyle(
    color: AppColors.textPrimary,
    fontSize: 24,
    fontWeight: FontWeight.w800,
  );

  static const sectionTitle = TextStyle(
    color: AppColors.textPrimary,
    fontSize: 18,
    fontWeight: FontWeight.w800,
  );

  static const title = TextStyle(
    color: AppColors.textPrimary,
    fontSize: 16,
    fontWeight: FontWeight.w800,
  );

  static const body = TextStyle(
    color: Color(0xFFE5E5E5),
    fontSize: 13,
    height: 1.32,
    fontWeight: FontWeight.w400,
  );

  static const metadata = TextStyle(
    color: AppColors.textSecondary,
    fontSize: 11.5,
    fontWeight: FontWeight.w500,
  );

  static const label = TextStyle(
    color: AppColors.textPrimary,
    fontSize: 11,
    fontWeight: FontWeight.w800,
  );
}
