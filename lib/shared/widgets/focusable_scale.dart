import 'package:flutter/material.dart';

import '../../widgets/focusable_card.dart';

class FocusableScale extends StatelessWidget {
  const FocusableScale({
    super.key,
    required this.child,
    required this.onPressed,
    this.borderRadius = 8,
    this.scale = 1.035,
    this.autofocus = false,
    this.selected = false,
  });

  final Widget child;
  final VoidCallback onPressed;
  final double borderRadius;
  final double scale;
  final bool autofocus;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final safeScale = scale.clamp(1.0, 1.03).toDouble();
    return FocusableCard(
      autofocus: autofocus,
      borderRadius: borderRadius,
      scale: safeScale,
      selected: selected,
      onPressed: onPressed,
      child: child,
    );
  }
}
