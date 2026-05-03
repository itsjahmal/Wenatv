import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_radius.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';
import 'focusable_card.dart';

class AppStreamCard extends StatelessWidget {
  const AppStreamCard({
    super.key,
    required this.provider,
    required this.title,
    required this.quality,
    required this.primaryMeta,
    required this.secondaryMeta,
    required this.selected,
    required this.onPressed,
    this.artwork,
  });

  final String provider;
  final String title;
  final String quality;
  final String primaryMeta;
  final String secondaryMeta;
  final bool selected;
  final VoidCallback onPressed;
  final Widget? artwork;

  @override
  Widget build(BuildContext context) {
    return FocusableCard(
      selected: selected,
      borderRadius: AppRadius.sm,
      scale: 1.018,
      onPressed: onPressed,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xs),
        child: Row(
          children: [
            if (artwork != null) ...[
              artwork!,
              const SizedBox(width: AppSpacing.sm),
            ],
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          provider,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.label.copyWith(fontSize: 11.5),
                        ),
                      ),
                      _QualityPill(text: quality, selected: selected),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.label,
                  ),
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    primaryMeta,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.metadata.copyWith(fontSize: 11),
                  ),
                  if (secondaryMeta.isNotEmpty)
                    Text(
                      secondaryMeta,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.metadata.copyWith(
                        color: AppColors.textMuted,
                        fontSize: 10,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _QualityPill extends StatelessWidget {
  const _QualityPill({required this.text, required this.selected});

  final String text;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    if (text.isEmpty) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(left: AppSpacing.xs),
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: selected ? AppColors.accentRed : AppColors.white(.12),
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Text(
        text,
        maxLines: 1,
        style: AppTypography.label.copyWith(fontSize: 9.5),
      ),
    );
  }
}
