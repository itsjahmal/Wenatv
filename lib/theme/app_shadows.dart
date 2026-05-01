import 'package:flutter/material.dart';

import 'app_colors.dart';

class AppShadows {
  const AppShadows._();

  static List<BoxShadow> focus({double opacity = .42}) => [
    BoxShadow(color: AppColors.red(opacity), blurRadius: 16),
  ];

  static List<BoxShadow> panel = [
    BoxShadow(
      color: AppColors.scrim(.32),
      blurRadius: 24,
      offset: const Offset(0, 12),
    ),
  ];

  static List<BoxShadow> nav = [
    BoxShadow(
      color: AppColors.scrim(.50),
      blurRadius: 22,
      offset: const Offset(8, 0),
    ),
  ];
}
