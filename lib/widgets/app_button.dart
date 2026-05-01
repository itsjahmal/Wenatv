import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_radius.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';
import 'focusable_card.dart';

class AppButton extends StatelessWidget {
  const AppButton({
    super.key,
    required this.label,
    required this.icon,
    required this.onPressed,
    this.primary = false,
    this.autofocus = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback onPressed;
  final bool primary;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    return FocusableCard(
      autofocus: autofocus,
      borderRadius: AppRadius.button,
      scale: 1.025,
      onPressed: onPressed,
      decorationBuilder: (focused, _) => BoxDecoration(
        color: primary ? AppColors.accentRed : AppColors.white(.92),
        borderRadius: BorderRadius.circular(AppRadius.button),
        boxShadow: focused
            ? [
                BoxShadow(
                  color: (primary ? AppColors.accentRed : Colors.white)
                      .withValues(alpha: .38),
                  blurRadius: 14,
                ),
              ]
            : null,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.sm,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: primary ? Colors.white : Colors.black, size: 20),
            const SizedBox(width: AppSpacing.sm),
            Text(
              label,
              style: AppTypography.label.copyWith(
                color: primary ? Colors.white : Colors.black,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
