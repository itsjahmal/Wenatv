import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:youtube_player_flutter/youtube_player_flutter.dart';

import '../../core/config/api_config.dart';
import '../../core/theme/app_theme.dart';
import '../../data/models/media_item.dart';
import '../../data/repositories/tmdb_repository.dart';
import '../../shared/widgets/focusable_scale.dart';
import '../../shared/widgets/poster_card.dart';
import '../../shared/widgets/wena_button.dart';
import 'home_providers.dart';
import 'navigation_rail.dart';

final _heroTrailerKeyProvider =
    FutureProvider.family<String?, ({int id, MediaKind kind})>((ref, args) {
      return ref.watch(tmdbRepositoryProvider).trailerKey(args.id, args.kind);
    });

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key, this.section});

  final String? section;

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  MediaItem? _hero;
  late final ScrollController _scrollController;
  double _scrollOffset = 0;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController()..addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    final offset = _scrollController.hasClients
        ? _scrollController.offset
        : 0.0;
    if ((offset - _scrollOffset).abs() < 2) return;
    setState(() => _scrollOffset = offset);
  }

  @override
  Widget build(BuildContext context) {
    final rows = ref.watch(homeRowsProvider);
    final active = _activeRailLabel(widget.section);
    return Scaffold(
      body: Row(
        children: [
          WenaNavigationRail(active: active),
          Expanded(
            child: ClipRect(
              child: rows.when(
                data: (data) {
                  if (data.isEmpty) {
                    return _HomeStatus(
                      status: ref.watch(homeProviderStatusProvider),
                      onRetry: () => ref.invalidate(homeRowsProvider),
                    );
                  }
                  final visibleRows = _rowsForSection(data, widget.section);
                  if (visibleRows.isEmpty) {
                    return _HomeStatus(
                      status: HomeProviderStatus(
                        title: '$active is empty',
                        message:
                            'The selected provider did not return items for this section yet. Try Home or choose another provider.',
                      ),
                      onRetry: () => ref.invalidate(homeRowsProvider),
                    );
                  }
                  final hero =
                      _hero ??
                      (visibleRows.isNotEmpty &&
                              visibleRows.first.items.isNotEmpty
                          ? visibleRows.first.items.first
                          : null);
                  return LayoutBuilder(
                    builder: (context, constraints) {
                      final viewportSize = Size(
                        constraints.maxWidth,
                        constraints.maxHeight,
                      );
                      final contentInset = _contentInset(viewportSize);
                      return Stack(
                        fit: StackFit.expand,
                        children: [
                          if (hero != null) _HeroBackdrop(item: hero),
                          CustomScrollView(
                            controller: _scrollController,
                            cacheExtent: 900,
                            slivers: [
                              SliverToBoxAdapter(
                                child: SizedBox(
                                  height: TvLayout.heroHeight(viewportSize),
                                ),
                              ),
                              for (final row in visibleRows)
                                SliverToBoxAdapter(
                                  child: _ContentRow(
                                    row: row,
                                    contentInset: contentInset,
                                    onFocus: (item) =>
                                        setState(() => _hero = item),
                                    onOpen: (item) => context.push(
                                      '/details/${item.kind.name}/${item.id}',
                                      extra: item,
                                    ),
                                  ),
                                ),
                              const SliverToBoxAdapter(
                                child: SizedBox(height: 30),
                              ),
                            ],
                          ),
                          if (hero != null)
                            _HeroContent(
                              item: hero,
                              scrollOffset: _scrollOffset,
                              contentInset: contentInset,
                              viewportSize: viewportSize,
                            ),
                        ],
                      );
                    },
                  );
                },
                loading: () => const _HomeLoadingState(),
                error: (error, stack) => _HomeStatus(
                  status: const HomeProviderStatus(
                    title: 'Provider Home failed',
                    message:
                        'The selected provider failed while loading its catalog. Refresh the provider or choose another default provider in Settings.',
                  ),
                  onRetry: () => ref.invalidate(homeRowsProvider),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

double _contentInset(Size size) {
  return TvLayout.horizontalInset(size);
}

class _HeroBackdrop extends ConsumerWidget {
  const _HeroBackdrop({required this.item});

  final MediaItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final imageUrl =
        item.externalBackdropUrl ?? ApiConfig.backdrop(item.backdropPath);
    final trailerKey = ref.watch(
      _heroTrailerKeyProvider((id: item.id, kind: item.kind)),
    );
    return AnimatedSwitcher(
      duration: 450.ms,
      child: Stack(
        key: ValueKey('${item.kind.name}-${item.id}-$imageUrl'),
        fit: StackFit.expand,
        children: [
          if (imageUrl.isNotEmpty)
            CachedNetworkImage(
              imageUrl: imageUrl,
              fit: BoxFit.cover,
              memCacheWidth: 1280,
            ),
          trailerKey.when(
            data: (key) => key == null || key.isEmpty
                ? const SizedBox.shrink()
                : _HeroTrailerPreview(videoId: key),
            loading: () => const SizedBox.shrink(),
            error: (_, __) => const SizedBox.shrink(),
          ),
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.black, Color(0xDD000000), Color(0x22000000)],
                stops: [0, .42, 1],
              ),
            ),
          ),
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.transparent, WenaTheme.black],
                stops: [.46, 1],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HeroTrailerPreview extends StatefulWidget {
  const _HeroTrailerPreview({required this.videoId});

  final String videoId;

  @override
  State<_HeroTrailerPreview> createState() => _HeroTrailerPreviewState();
}

class _HeroTrailerPreviewState extends State<_HeroTrailerPreview> {
  late YoutubePlayerController _controller;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _controller = _createController(widget.videoId);
  }

  @override
  void didUpdateWidget(covariant _HeroTrailerPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.videoId == widget.videoId) return;
    _controller.dispose();
    _ready = false;
    _controller = _createController(widget.videoId);
  }

  YoutubePlayerController _createController(String videoId) {
    return YoutubePlayerController(
      initialVideoId: videoId,
      flags: const YoutubePlayerFlags(
        autoPlay: true,
        mute: true,
        loop: true,
        hideControls: true,
        controlsVisibleAtStart: false,
        disableDragSeek: true,
        enableCaption: false,
        forceHD: false,
      ),
    )..addListener(_onPlayerChanged);
  }

  void _onPlayerChanged() {
    final value = _controller.value;
    if (!_ready && value.isReady && mounted) {
      setState(() => _ready = true);
      _controller.mute();
      _controller.play();
    }
    if (value.playerState == PlayerState.ended) {
      _controller.seekTo(Duration.zero);
      _controller.play();
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_onPlayerChanged);
    _controller.pause();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedOpacity(
        opacity: _ready ? .92 : 0,
        duration: const Duration(milliseconds: 500),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            return Align(
              alignment: Alignment.topCenter,
              child: SizedBox(
                width: width,
                height: width * 9 / 16,
                child: YoutubePlayer(
                  controller: _controller,
                  showVideoProgressIndicator: false,
                  topActions: const [],
                  bottomActions: const [],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

String _activeRailLabel(String? section) {
  return switch (section) {
    'movies' => 'Browse',
    'tv' => 'TV Shows',
    'trending' => 'Trending',
    'watchlist' => 'My List',
    _ => 'Home',
  };
}

List<HomeRow> _rowsForSection(List<HomeRow> rows, String? section) {
  if (section == null || section == 'home') return rows;
  final lower = section.toLowerCase();
  if (lower == 'watchlist') return const [];
  final filtered = rows.where((row) {
    final title = row.title.toLowerCase();
    if (lower == 'movies') {
      return title.contains('movie') ||
          row.items.any((item) => item.kind == MediaKind.movie);
    }
    if (lower == 'tv') {
      return title.contains('tv') ||
          title.contains('series') ||
          row.items.any((item) => item.kind == MediaKind.tv);
    }
    if (lower == 'trending') {
      return title.contains('trend') ||
          title.contains('new') ||
          title.contains('popular');
    }
    return true;
  }).toList();
  return filtered.isEmpty ? rows : filtered;
}

class _HeroContent extends ConsumerWidget {
  const _HeroContent({
    required this.item,
    required this.scrollOffset,
    required this.contentInset,
    required this.viewportSize,
  });

  final MediaItem item;
  final double scrollOffset;
  final double contentInset;
  final Size viewportSize;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final screenHeight = viewportSize.height;
    final compact = screenHeight < 650;
    final collapse = (scrollOffset / 190).clamp(0.0, 1.0);
    final opacity = (1 - collapse).clamp(0.0, 1.0);
    final yOffset = -72 * collapse;
    final scale = TvLayout.tvScale(viewportSize);
    return Positioned(
      left: contentInset,
      top: (compact ? 30 : 42) + yOffset,
      width: (viewportSize.width - (contentInset * 2))
          .clamp(compact ? 430.0 : 500.0, compact ? 580.0 : 660.0)
          .toDouble(),
      child: IgnorePointer(
        ignoring: collapse > .35,
        child: AnimatedOpacity(
          opacity: opacity,
          duration: const Duration(milliseconds: 120),
          child: Transform.scale(
            alignment: Alignment.topLeft,
            scale: 1 - (.08 * collapse),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'WENATV ORIGINAL',
                  style: TextStyle(
                    color: WenaTheme.red,
                    fontWeight: FontWeight.w900,
                    fontSize: 12,
                    letterSpacing: 2.8,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  item.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.displayLarge?.copyWith(
                    fontSize: TvLayout.heroTitleSize(viewportSize),
                    height: 1.02,
                    shadows: const [
                      Shadow(color: Colors.black87, blurRadius: 20),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    const _HeroMetaBadge(label: 'TMDB', highlighted: true),
                    _HeroMetaBadge(
                      label: '${item.rating.toStringAsFixed(1)}/10',
                    ),
                    const _HeroMetaBadge(label: '2B+ Streams'),
                    if (item.year.isNotEmpty) _HeroMetaBadge(label: item.year),
                  ],
                ),
                if (item.overview.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(
                    item.overview,
                    maxLines: compact ? 2 : 3,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 14,
                      height: 1.35,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
                const SizedBox(height: 18),
                Row(
                  children: [
                    _HeroActionButton(
                      label: 'Play',
                      icon: Icons.play_arrow,
                      primary: true,
                      scale: scale,
                      onPressed: () => context.push(
                        '/details/${item.kind.name}/${item.id}',
                        extra: item,
                      ),
                    ),
                    const SizedBox(width: 12),
                    _HeroActionButton(
                      label: 'Trailer',
                      icon: Icons.movie_outlined,
                      scale: scale,
                      onPressed: () async {
                        final uri = await ref
                            .read(tmdbRepositoryProvider)
                            .trailerUri(item.id, item.kind);
                        if (uri != null) {
                          await launchUrl(
                            uri,
                            mode: LaunchMode.externalApplication,
                          );
                        }
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _HeroMetaBadge extends StatelessWidget {
  const _HeroMetaBadge({required this.label, this.highlighted = false});

  final String label;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: highlighted
            ? const Color(0xFFFFC400)
            : Colors.black.withValues(alpha: .42),
        borderRadius: BorderRadius.circular(5),
        border: highlighted
            ? null
            : Border.all(color: Colors.white.withValues(alpha: .12)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: highlighted ? Colors.black : Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _HeroActionButton extends StatelessWidget {
  const _HeroActionButton({
    required this.label,
    required this.icon,
    required this.onPressed,
    this.primary = false,
    this.scale = 1,
  });

  final String label;
  final IconData icon;
  final VoidCallback onPressed;
  final bool primary;
  final double scale;

  @override
  Widget build(BuildContext context) {
    return FocusableScale(
      borderRadius: 999,
      scale: 1.025,
      onPressed: onPressed,
      child: Container(
        height: (40 * scale).clamp(38.0, 44.0).toDouble(),
        padding: EdgeInsets.symmetric(
          horizontal: (22 * scale).clamp(20.0, 25.0).toDouble(),
        ),
        decoration: BoxDecoration(
          color: primary ? WenaTheme.red : Colors.white.withValues(alpha: .92),
          borderRadius: BorderRadius.circular(999),
          boxShadow: primary
              ? [
                  BoxShadow(
                    color: WenaTheme.red.withValues(alpha: .34),
                    blurRadius: 22,
                    offset: const Offset(0, 8),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: primary ? Colors.white : Colors.black, size: 19),
            const SizedBox(width: 9),
            Text(
              label,
              style: TextStyle(
                color: primary ? Colors.white : Colors.black,
                fontSize: (13.5 * scale).clamp(13.0, 15.0).toDouble(),
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ContentRow extends StatelessWidget {
  const _ContentRow({
    required this.row,
    required this.contentInset,
    required this.onFocus,
    required this.onOpen,
  });

  final HomeRow row;
  final double contentInset;
  final ValueChanged<MediaItem> onFocus;
  final ValueChanged<MediaItem> onOpen;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final posterWidth = TvLayout.posterWidthFor(size);
    final rowHeight = TvLayout.posterRowHeightFor(size);
    return Padding(
      padding: EdgeInsets.only(
        left: contentInset,
        right: contentInset,
        bottom: AppSpacing.xs,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(row.title, style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: AppSpacing.xs),
          SizedBox(
            height: rowHeight,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              cacheExtent: 700,
              itemCount: row.items.length,
              separatorBuilder: (_, __) => const SizedBox(width: AppSpacing.sm),
              itemBuilder: (context, index) {
                final item = row.items[index];
                return Focus(
                  onFocusChange: (focused) {
                    if (focused) onFocus(item);
                  },
                  child: PosterCard(
                    item: item,
                    width: posterWidth,
                    onPressed: () => onOpen(item),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _HomeLoadingState extends StatelessWidget {
  const _HomeLoadingState();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black,
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.only(
        left: AppSpacing.xl,
        right: TvLayout.safeHorizontal,
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(color: WenaTheme.red),
          ),
          SizedBox(width: 18),
          Text(
            'Loading selected provider catalog...',
            style: TextStyle(color: Colors.white70, fontSize: 17),
          ),
        ],
      ),
    );
  }
}

class _HomeStatus extends StatelessWidget {
  const _HomeStatus({required this.status, required this.onRetry});

  final HomeProviderStatus status;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return _EmptyProviderHome(status: status, onRetry: onRetry);
  }
}

class _EmptyProviderHome extends StatelessWidget {
  const _EmptyProviderHome({required this.status, required this.onRetry});

  final HomeProviderStatus status;

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black,
      padding: const EdgeInsets.only(
        left: AppSpacing.xl,
        right: TvLayout.safeHorizontal,
      ),
      alignment: Alignment.centerLeft,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            status.title,
            style: Theme.of(
              context,
            ).textTheme.headlineLarge?.copyWith(color: Colors.white),
          ),
          const SizedBox(height: 12),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 700),
            child: Text(
              status.message,
              style: const TextStyle(color: Colors.white70, fontSize: 16),
            ),
          ),
          const SizedBox(height: 18),
          Wrap(
            spacing: 14,
            runSpacing: 12,
            children: [
              WenaButton(
                label: 'Retry',
                icon: Icons.refresh,
                primary: true,
                autofocus: true,
                onPressed: onRetry,
              ),
              WenaButton(
                label: 'Settings',
                icon: Icons.settings,
                onPressed: () => context.go('/settings'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
