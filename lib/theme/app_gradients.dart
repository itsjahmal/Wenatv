import 'package:flutter/material.dart';

import 'app_colors.dart';

class AppGradients {
  const AppGradients._();

  static const heroLeft = LinearGradient(
    colors: [Colors.black, Color(0xDD000000), Colors.transparent],
    stops: [0, .44, 1],
  );

  static const heroBottom = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Colors.transparent, AppColors.background],
    stops: [.46, 1],
  );

  static const panel = LinearGradient(
    colors: [Color(0xFF101317), Color(0xFF080A0D)],
  );

  static LinearGradient redActive = LinearGradient(
    colors: [AppColors.red(.82), AppColors.red(.24)],
  );
}
