import 'package:flutter/material.dart';

import '../../widgets/app_button.dart';

class WenaButton extends StatelessWidget {
  const WenaButton({
    super.key,
    required this.label,
    required this.icon,
    required this.onPressed,
    this.primary = false,
    this.autofocus = false,
    this.focusNode,
  });

  final String label;
  final IconData icon;
  final VoidCallback onPressed;
  final bool primary;
  final bool autofocus;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: focusNode,
      child: AppButton(
        label: label,
        icon: icon,
        primary: primary,
        autofocus: autofocus,
        onPressed: onPressed,
      ),
    );
  }
}
