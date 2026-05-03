import 'dart:math' as math;

import 'package:flutter/widgets.dart';

class AppSpacing {
  const AppSpacing._();

  static const xxs = 4.0;
  static const xs = 6.0;
  static const sm = 10.0;
  static const md = 16.0;
  static const lg = 24.0;
  static const xl = 32.0;
  static const xxl = 48.0;
}

class TvLayout {
  const TvLayout._();

  static const baseWidth = 1280.0;
  static const baseHeight = 720.0;
  static const collapsedSidebarWidth = 84.0;
  static const expandedSidebarWidth = 232.0;
  static const navRailWidth = collapsedSidebarWidth;
  static const safeHorizontal = 32.0;
  static const safeHorizontalMax = 54.0;
  static const safeVertical = 18.0;
  static const heroHeightRatio = 0.44;
  static const heroMinHeight = 245.0;
  static const heroMaxHeight = 330.0;
  static const posterWidth = 92.0;
  static const contentRowHeight = 148.0;
  static const streamCardWidth = 260.0;
  static const streamRowHeight = 106.0;

  static double tvScale(Size size) {
    final widthScale = size.width / baseWidth;
    final heightScale = size.height / baseHeight;
    return math.min(widthScale, heightScale).clamp(.85, 1.0).toDouble();
  }

  static double horizontalInset(Size size) {
    return (size.width * .038)
        .clamp(safeHorizontal, safeHorizontalMax)
        .toDouble();
  }

  static double heroHeight(Size size, {double ratio = heroHeightRatio}) {
    return (size.height * ratio).clamp(heroMinHeight, heroMaxHeight).toDouble();
  }

  static double movieHeroHeight(Size size) {
    return (size.height * .36).clamp(220.0, 285.0).toDouble();
  }

  static double seriesHeroHeight(Size size) {
    return (size.height * .34).clamp(210.0, 275.0).toDouble();
  }

  static double posterWidthFor(Size size) {
    return (size.width * .079).clamp(74.0, 98.0).toDouble();
  }

  static double posterRowHeightFor(Size size) {
    return (posterWidthFor(size) * 1.5 + 18).clamp(126.0, 162.0).toDouble();
  }

  static double heroTitleSize(Size size) {
    return (size.width * .032).clamp(28.0, 40.0).toDouble();
  }

  static double detailTitleSize(Size size) {
    return (size.width * .030).clamp(26.0, 36.0).toDouble();
  }

  static double sectionTitleSize(Size size) {
    return (size.width * .019).clamp(17.0, 23.0).toDouble();
  }

  static double bodySize(Size size) {
    return (size.width * .013).clamp(12.0, 15.5).toDouble();
  }

  static double metadataSize(Size size) {
    return (size.width * .011).clamp(10.5, 13.5).toDouble();
  }
}
