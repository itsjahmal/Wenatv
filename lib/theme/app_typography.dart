import 'package:flutter/material.dart';

import 'app_colors.dart';

class AppTypography {
  const AppTypography._();

  static const heroTitle = TextStyle(
    color: AppColors.textPrimary,
    fontSize: 46,
    height: 1.05,
    fontWeight: FontWeight.w900,
  );

  static const screenTitle = TextStyle(
    color: AppColors.textPrimary,
    fontSize: 28,
    fontWeight: FontWeight.w800,
  );

  static const sectionTitle = TextStyle(
    color: AppColors.textPrimary,
    fontSize: 21,
    fontWeight: FontWeight.w800,
  );

  static const title = TextStyle(
    color: AppColors.textPrimary,
    fontSize: 18,
    fontWeight: FontWeight.w800,
  );

  static const body = TextStyle(
    color: Color(0xFFE5E5E5),
    fontSize: 15,
    height: 1.32,
    fontWeight: FontWeight.w400,
  );

  static const metadata = TextStyle(
    color: AppColors.textSecondary,
    fontSize: 13,
    fontWeight: FontWeight.w500,
  );

  static const label = TextStyle(
    color: AppColors.textPrimary,
    fontSize: 12,
    fontWeight: FontWeight.w800,
  );
}
