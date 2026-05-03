import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_radius.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';
import 'focusable_card.dart';

class EpisodeTile extends StatelessWidget {
  const EpisodeTile({
    super.key,
    required this.title,
    required this.numberLabel,
    required this.onPressed,
    this.runtime,
    this.thumbnail,
    this.selected = false,
    this.trailing,
  });

  final String title;
  final String numberLabel;
  final String? runtime;
  final Widget? thumbnail;
  final Widget? trailing;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return FocusableCard(
      selected: selected,
      borderRadius: AppRadius.sm,
      scale: 1.012,
      onPressed: onPressed,
      child: Container(
        height: 46,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
        child: Row(
          children: [
            if (thumbnail != null) ...[
              thumbnail!,
              const SizedBox(width: AppSpacing.sm),
            ],
            Expanded(
              child: Text(
                '$numberLabel $title',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.label,
              ),
            ),
            if ((runtime ?? '').isNotEmpty) ...[
              const SizedBox(width: AppSpacing.sm),
              Text(
                runtime!,
                style: AppTypography.metadata.copyWith(fontSize: 12),
              ),
            ],
            const SizedBox(width: AppSpacing.sm),
            trailing ??
                const Icon(
                  Icons.download,
                  color: AppColors.textSecondary,
                  size: 17,
                ),
          ],
        ),
      ),
    );
  }
}
