import 'package:flutter/material.dart';

export '../../theme/app_animations.dart';
export '../../theme/app_colors.dart';
export '../../theme/app_focus.dart';
export '../../theme/app_gradients.dart';
export '../../theme/app_radius.dart';
export '../../theme/app_shadows.dart';
export '../../theme/app_spacing.dart';
export '../../theme/app_theme.dart';
export '../../theme/app_typography.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_theme.dart';

class WenaTheme {
  const WenaTheme._();

  static const red = AppColors.accentRed;
  static const black = AppColors.background;
  static const surface = AppColors.surface;
  static const soft = AppColors.surfaceElevated;

  static ThemeData get dark => AppTheme.dark;
  static ThemeData get light => AppTheme.light;
}
