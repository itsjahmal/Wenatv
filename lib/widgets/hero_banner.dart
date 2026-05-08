import 'package:flutter/material.dart';

import '../theme/app_gradients.dart';

class HeroBanner extends StatelessWidget {
  const HeroBanner({super.key, required this.child, this.background});

  final Widget child;
  final Widget? background;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        if (background != null) background!,
        Container(
          decoration: const BoxDecoration(gradient: AppGradients.heroLeft),
        ),
        Container(
          decoration: const BoxDecoration(gradient: AppGradients.heroBottom),
        ),
        child,
      ],
    );
  }
}
