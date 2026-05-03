import 'package:flutter/material.dart';

import 'app_animations.dart';
import 'app_colors.dart';
import 'app_radius.dart';
import 'app_shadows.dart';

class AppFocus {
  const AppFocus._();

  static const focusedScale = 1.025;
  static const subtleScale = 1.012;
  static const duration = AppAnimations.normal;

  static BoxDecoration cardDecoration(
    bool focused, {
    bool selected = false,
    double radius = AppRadius.card,
    Color? color,
  }) {
    final active = focused || selected;
    return BoxDecoration(
      color: color ?? (selected ? AppColors.red(.15) : AppColors.surface),
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(
        color: active ? AppColors.accentRed : AppColors.white(.10),
        width: active ? 2 : 1,
      ),
      boxShadow: focused ? AppShadows.focus() : null,
    );
  }
}
