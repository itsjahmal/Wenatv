import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../core/config/api_config.dart';
import '../../data/models/media_item.dart';
import '../../theme/app_spacing.dart';
import 'focusable_scale.dart';

class PosterCard extends StatelessWidget {
  const PosterCard({
    super.key,
    required this.item,
    required this.onPressed,
    this.width,
  });

  final MediaItem item;
  final VoidCallback onPressed;
  final double? width;

  @override
  Widget build(BuildContext context) {
    final imageUrl =
        item.externalPosterUrl ?? ApiConfig.poster(item.posterPath);
    final cardWidth =
        width ?? TvLayout.posterWidthFor(MediaQuery.sizeOf(context));
    return SizedBox(
      width: cardWidth,
      child: FocusableScale(
        borderRadius: 7,
        scale: 1.03,
        onPressed: onPressed,
        child: AspectRatio(
          aspectRatio: 2 / 3,
          child: DecoratedBox(
            decoration: const BoxDecoration(color: Color(0xFF202020)),
            child: imageUrl.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text(item.title, textAlign: TextAlign.center),
                    ),
                  )
                : CachedNetworkImage(
                    imageUrl: imageUrl,
                    fit: BoxFit.cover,
                    memCacheWidth: 360,
                    errorWidget: (_, __, ___) => Center(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text(item.title, textAlign: TextAlign.center),
                      ),
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}
