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

  static const baseWidth = 960.0;
  static const baseHeight = 540.0;
  static const collapsedSidebarWidth = 86.0;
  static const expandedSidebarWidth = 236.0;
  static const navRailWidth = collapsedSidebarWidth;
  static const safeHorizontal = 34.0;
  static const safeHorizontalMax = 58.0;
  static const safeVertical = 22.0;
  static const heroHeightRatio = 0.50;
  static const heroMinHeight = 250.0;
  static const heroMaxHeight = 420.0;
  static const posterWidth = 108.0;
  static const contentRowHeight = 174.0;
  static const streamCardWidth = 292.0;
  static const streamRowHeight = 128.0;

  static double tvScale(Size size) {
    final shortestScale = size.shortestSide / baseHeight;
    final widthScale = size.width / baseWidth;
    return (shortestScale < widthScale
            ? shortestScale.clamp(.88, 1.06)
            : widthScale.clamp(.88, 1.06))
        .toDouble();
  }

  static double horizontalInset(Size size) {
    return (size.width * .044)
        .clamp(safeHorizontal, safeHorizontalMax)
        .toDouble();
  }

  static double heroHeight(Size size, {double ratio = heroHeightRatio}) {
    return (size.height * ratio).clamp(heroMinHeight, heroMaxHeight).toDouble();
  }

  static double posterWidthFor(Size size) {
    return (size.width * .108).clamp(94.0, 118.0).toDouble();
  }

  static double posterRowHeightFor(Size size) {
    return (posterWidthFor(size) * 1.5 + 22).clamp(152.0, 184.0).toDouble();
  }

  static double heroTitleSize(Size size) {
    return (size.width * .046).clamp(34.0, 46.0).toDouble();
  }

  static double detailTitleSize(Size size) {
    return (size.width * .052).clamp(38.0, 52.0).toDouble();
  }

  static double sectionTitleSize(Size size) {
    return (size.width * .024).clamp(21.0, 27.0).toDouble();
  }

  static double bodySize(Size size) {
    return (size.width * .016).clamp(14.0, 18.0).toDouble();
  }

  static double metadataSize(Size size) {
    return (size.width * .014).clamp(12.0, 16.0).toDouble();
  }
}
