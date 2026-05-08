import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart';

import '../../core/config/api_config.dart';
import '../../core/theme/app_theme.dart';
import '../../data/models/media_item.dart';
import '../../data/repositories/tmdb_repository.dart';
import '../continue_watching/continue_watching_controller.dart';
import '../tv/native_tv_integration_service.dart';
import '../watchlist/watchlist_controller.dart';
import '../../shared/widgets/focusable_scale.dart';
import '../../shared/widgets/poster_card.dart';
import '../../shared/widgets/wena_button.dart';
import 'home_providers.dart';
import 'navigation_rail.dart';

final _heroTrailerKeyProvider =
    FutureProvider.family<String?, ({int id, MediaKind kind})>((ref, args) {
      return ref.watch(tmdbRepositoryProvider).trailerKey(args.id, args.kind);
    });

final _continuePosterProvider =
    FutureProvider.family<String?, ContinueWatchingEntry>((ref, entry) async {
      // Fix 5: Use stored artworkUrl if available — avoid an unnecessary TMDB request.
      if (entry.artworkUrl != null && entry.artworkUrl!.isNotEmpty) {
        return entry.artworkUrl;
      }
      final kind = entry.kind == 'tv' ? MediaKind.tv : MediaKind.movie;
      final details = await ref
          .watch(tmdbRepositoryProvider)
          .details(entry.mediaId, kind);
      return details.externalPosterUrl ?? ApiConfig.poster(details.posterPath);
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
  String? _lastPublishedChannelsKey;
  bool _isOffline = false;
  late StreamSubscription<List<ConnectivityResult>> _connectivitySubscription;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController()..addListener(_onScroll);
    _connectivitySubscription =
        Connectivity().onConnectivityChanged.listen(_updateConnectivity);
    Connectivity().checkConnectivity().then(_updateConnectivity);
  }

  void _updateConnectivity(List<ConnectivityResult> results) {
    if (!mounted) return;
    final isOffline =
        results.isEmpty || results.every((r) => r == ConnectivityResult.none);
    if (_isOffline != isOffline) {
      setState(() => _isOffline = isOffline);
    }
  }

  @override
  void dispose() {
    _connectivitySubscription.cancel();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    // Fix 1: Increase threshold to 8px — reduces setState frequency by ~4x
    // during scrolling, preventing constant hero-overlay rebuilds.
    final offset = _scrollController.hasClients
        ? _scrollController.offset
        : 0.0;
    if ((offset - _scrollOffset).abs() < 8) return;
    setState(() => _scrollOffset = offset);
  }

  @override
  Widget build(BuildContext context) {
    final rows = ref.watch(homeRowsProvider);
    final updatingHome = ref.watch(homeRefreshingProvider);
    final continueWatching = ref.watch(continueWatchingProvider);
    final watchlist = ref.watch(watchlistProvider);
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
                  final visibleRows = _rowsForSection(
                    data,
                    widget.section,
                    watchlist,
                  );
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
                  final isHomeSection =
                      widget.section == null || widget.section == 'home';
                  _publishNativeHomeChannels(
                    continueWatching: continueWatching,
                    rows: data,
                    watchlist: watchlist,
                  );
                  final hero = isHomeSection
                      ? (_hero ??
                            (visibleRows.isNotEmpty &&
                                    visibleRows.first.items.isNotEmpty
                                ? visibleRows.first.items.first
                                : null))
                      : null;
                  return LayoutBuilder(
                    builder: (context, constraints) {
                      final viewportSize = Size(
                        constraints.maxWidth,
                        constraints.maxHeight,
                      );
                      final contentInset = _contentInset(viewportSize);
                      assert(() {
                        debugPrint(
                          'TV Home size=$viewportSize dpr=${MediaQuery.devicePixelRatioOf(context)} '
                          'scale=${TvLayout.tvScale(viewportSize)} inset=$contentInset '
                          'hero=${TvLayout.heroHeight(viewportSize)} '
                          'poster=${TvLayout.posterWidthFor(viewportSize)}',
                        );
                        return true;
                      }());
                      return Stack(
                        fit: StackFit.expand,
                        children: [
                          const _HomePlainBackground(),
                          if (isHomeSection && hero != null)
                            RepaintBoundary(
                              child: _HeroBackdrop(
                                item: hero,
                                heroHeight: _homeHeroHeight(viewportSize),
                              ),
                            ),
                          CustomScrollView(
                            controller: _scrollController,
                            // Fix 9: Larger cache so cards above/below viewport
                            // are pre-rendered, preventing jank on TV D-pad nav.
                            cacheExtent: 1400,
                            slivers: [
                              SliverToBoxAdapter(
                                child: SizedBox(
                                  height: isHomeSection
                                      ? _homeRowsTopOffset(viewportSize)
                                      : _sectionTopOffset(viewportSize),
                                ),
                              ),
                              if (isHomeSection && continueWatching.isNotEmpty)
                                SliverToBoxAdapter(
                                  child: _ContinueWatchingRow(
                                    entries: continueWatching,
                                    contentInset: contentInset,
                                    onOpen: (entry) => context.push(
                                      '/player',
                                      extra: entry.toPlayerPayload(),
                                    ),
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
                                child: SizedBox(height: 22),
                              ),
                            ],
                          ),
                          if (isHomeSection && hero != null)
                            _HeroContent(
                              item: hero,
                              scrollOffset: _scrollOffset,
                              contentInset: contentInset,
                              viewportSize: viewportSize,
                            ),
                          if (updatingHome)
                            Positioned(
                              top: 18,
                              right: contentInset,
                              child: const _HomeUpdatingBadge(),
                            ),
                          if (_isOffline)
                            const Positioned(
                              top: 24,
                              left: 0,
                              right: 0,
                              child: _OfflineBanner(),
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

  void _publishNativeHomeChannels({
    required List<ContinueWatchingEntry> continueWatching,
    required List<HomeRow> rows,
    required List<MediaItem> watchlist,
  }) {
    final key = [
      continueWatching.map((entry) => entry.key).join(','),
      rows
          .map(
            (row) =>
                '${row.title}:${row.items.take(8).map((item) => '${item.kind.name}:${item.id}').join(',')}',
          )
          .join('|'),
      watchlist.map((item) => '${item.kind.name}:${item.id}').join(','),
    ].join('::');
    if (_lastPublishedChannelsKey == key) return;
    _lastPublishedChannelsKey = key;
    unawaited(
      NativeTvIntegrationService.publishHomeChannels(
        continueWatching: continueWatching,
        homeRows: rows,
        watchlist: watchlist,
      ),
    );
  }
}

class _OfflineBanner extends StatelessWidget {
  const _OfflineBanner();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: WenaTheme.red,
          borderRadius: BorderRadius.circular(999),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: .4),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.wifi_off, color: Colors.white, size: 16),
            SizedBox(width: 8),
            Text(
              'No Internet Connection',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

double _contentInset(Size size) {
  return TvLayout.horizontalInset(size);
}

double _homeHeroHeight(Size size) {
  return (size.height * .58).clamp(340.0, 455.0).toDouble();
}

double _homeRowsTopOffset(Size size) {
  return _homeHeroHeight(size) + (size.height * .065).clamp(34.0, 62.0);
}

double _sectionTopOffset(Size size) {
  return (size.height * .075).clamp(42.0, 68.0);
}

double _homeRowPosterWidth(Size size, double contentInset) {
  const visibleCards = 10;
  const gap = AppSpacing.sm;
  final availableWidth = size.width - (contentInset * 2);
  final fitWidth = (availableWidth - ((visibleCards - 1) * gap)) / visibleCards;
  return fitWidth.clamp(70.0, 96.0).toDouble();
}

double _homeRowHeightFor(double posterWidth) {
  return (posterWidth * 1.5 + 18).clamp(122.0, 160.0).toDouble();
}

String _shortDuration(Duration value) {
  if (value <= Duration.zero) return '';
  final hours = value.inHours;
  final minutes = value.inMinutes.remainder(60).toString().padLeft(2, '0');
  final seconds = value.inSeconds.remainder(60).toString().padLeft(2, '0');
  return hours > 0 ? '$hours:$minutes:$seconds' : '$minutes:$seconds';
}

class _HomePlainBackground extends StatelessWidget {
  const _HomePlainBackground();

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [WenaTheme.black, Color(0xFF070707), Color(0xFF000000)],
        ),
      ),
    );
  }
}

class _HeroBackdrop extends ConsumerWidget {
  const _HeroBackdrop({required this.item, required this.heroHeight});

  final MediaItem item;
  final double heroHeight;

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
          Positioned(
            left: 0,
            top: 0,
            right: 0,
            height: heroHeight + 120,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (imageUrl.isNotEmpty)
                  CachedNetworkImage(
                    imageUrl: imageUrl,
                    fit: BoxFit.cover,
                    memCacheWidth: 1600,
                  ),
                trailerKey.when(
                  data: (key) => key == null || key.isEmpty
                      ? const SizedBox.shrink()
                      : _HeroTrailerPreview(videoId: key),
                  loading: () => const SizedBox.shrink(),
                  error: (_, __) => const SizedBox.shrink(),
                ),
              ],
            ),
          ),
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [
                  Colors.black,
                  Color(0xEA000000),
                  Color(0x66000000),
                  Color(0x00000000),
                ],
                stops: [0, .22, .46, 1],
              ),
            ),
          ),
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0x26000000), Color(0x88000000), WenaTheme.black],
                stops: [.48, .78, 1],
              ),
            ),
          ),
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            width: 96,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.black.withValues(alpha: .78),
                    Colors.transparent,
                  ],
                ),
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
  YoutubePlayerController? _controller;
  bool _ready = false;
  // Delay instantiating the YouTube WebView by 8 seconds so the home
  // screen can fully settle (images, rows, focus) before adding the expensive
  // embedded player to the tree. On low-end TV hardware this eliminates the
  // most common startup hang.
  bool _timerFired = false;
  Timer? _startTimer;

  @override
  void initState() {
    super.initState();
    _startTimer = Timer(const Duration(seconds: 8), () {
      if (!mounted) return;
      final controller = _createController(widget.videoId);
      setState(() {
        _timerFired = true;
        _controller = controller;
      });
    });
  }

  @override
  void didUpdateWidget(covariant _HeroTrailerPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_timerFired || _controller == null) return;
    if (oldWidget.videoId == widget.videoId) return;
    _controller!.close();
    _ready = false;
    _controller = _createController(widget.videoId);
  }

  YoutubePlayerController _createController(String videoId) {
    return YoutubePlayerController.fromVideoId(
      videoId: videoId,
      autoPlay: true,
      params: const YoutubePlayerParams(
        mute: true,
        loop: true,
        showControls: false,
        showFullscreenButton: false,
        strictRelatedVideos: true,
      ),
    )..listen((event) {
        if (!mounted) return;
        if (!_ready && event.playerState == PlayerState.playing) {
          setState(() => _ready = true);
        }
      });
  }

  @override
  void dispose() {
    _startTimer?.cancel();
    _controller?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Don't build any WebView until the timer has fired
    if (!_timerFired || _controller == null) return const SizedBox.shrink();
    return IgnorePointer(
      child: AnimatedOpacity(
        opacity: _ready ? .88 : 0,
        duration: const Duration(milliseconds: 500),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            final height = constraints.maxHeight;
            final videoWidth = (height * 16 / 9) < width
                ? width
                : height * 16 / 9;
            final videoHeight = videoWidth * 9 / 16;
            return Align(
              alignment: Alignment.centerRight,
              child: SizedBox(
                width: videoWidth,
                height: videoHeight,
                child: YoutubePlayerScaffold(
                  controller: _controller!,
                  builder: (context, player) => player,
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
    'movies' => 'Movies',
    'tv' => 'Series',
    'trending' => 'Trending',
    'watchlist' => 'Watchlist',
    _ => 'Home',
  };
}

List<HomeRow> _rowsForSection(
  List<HomeRow> rows,
  String? section,
  List<MediaItem> watchlist,
) {
  if (section == null || section == 'home') return rows;
  final lower = section.toLowerCase();
  if (lower == 'watchlist') {
    return watchlist.isEmpty ? const [] : [HomeRow('Watchlist', watchlist)];
  }
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
    final collapse = (scrollOffset / 230).clamp(0.0, 1.0);
    final opacity = (1 - collapse).clamp(0.0, 1.0);
    final yOffset = -84 * collapse;
    final scale = TvLayout.tvScale(viewportSize);
    final topAnchor = (_homeHeroHeight(viewportSize) * (compact ? .27 : .31))
        .clamp(compact ? 86.0 : 116.0, compact ? 124.0 : 152.0)
        .toDouble();
    final titleSize = (viewportSize.width * .038)
        .clamp(compact ? 34.0 : 38.0, compact ? 46.0 : 54.0)
        .toDouble();
    return Positioned(
      left: contentInset,
      top: topAnchor + yOffset,
      width: (viewportSize.width - (contentInset * 2))
          .clamp(compact ? 500.0 : 560.0, compact ? 720.0 : 820.0)
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
                    fontSize: 12.5,
                    letterSpacing: 3.2,
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  item.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.displayLarge?.copyWith(
                    fontSize: titleSize,
                    height: .98,
                    shadows: const [
                      Shadow(color: Colors.black87, blurRadius: 20),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 11,
                  runSpacing: 9,
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
                  const SizedBox(height: 16),
                  ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: compact ? 560 : 660),
                    child: Text(
                      item.overview,
                      maxLines: compact ? 2 : 3,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: .82),
                        fontSize: (TvLayout.bodySize(viewportSize) + 1)
                            .clamp(13.5, 17.0)
                            .toDouble(),
                        height: 1.42,
                        fontWeight: FontWeight.w500,
                        shadows: const [
                          Shadow(color: Colors.black87, blurRadius: 10),
                        ],
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 24),
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
                    const SizedBox(width: 16),
                    _HeroActionButton(
                      label: 'Trailer',
                      icon: Icons.movie_outlined,
                      scale: scale,
                      onPressed: () => context.push(
                        '/trailer/${item.kind.name}/${item.id}',
                        extra: item.title,
                      ),
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
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
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
          fontSize: 12.5,
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
        height: (44 * scale).clamp(40.0, 48.0).toDouble(),
        padding: EdgeInsets.symmetric(
          horizontal: (24 * scale).clamp(22.0, 30.0).toDouble(),
        ),
        decoration: BoxDecoration(
          color: primary ? WenaTheme.red : Colors.white.withValues(alpha: .18),
          borderRadius: BorderRadius.circular(999),
          border: primary
              ? null
              : Border.all(color: Colors.white.withValues(alpha: .22)),
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
            Icon(icon, color: Colors.white, size: 19),
            const SizedBox(width: 9),
            Text(
              label,
              style: TextStyle(
                color: Colors.white,
                fontSize: (13.5 * scale).clamp(12.5, 15.0).toDouble(),
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ContinueWatchingRow extends StatelessWidget {
  const _ContinueWatchingRow({
    required this.entries,
    required this.contentInset,
    required this.onOpen,
  });

  final List<ContinueWatchingEntry> entries;
  final double contentInset;
  final ValueChanged<ContinueWatchingEntry> onOpen;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final cardWidth = _homeRowPosterWidth(size, contentInset);
    final rowHeight = _homeRowHeightFor(cardWidth);
    return Padding(
      padding: EdgeInsets.only(
        left: contentInset,
        right: contentInset,
        bottom: AppSpacing.xs,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Continue Watching',
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
              fontSize: TvLayout.sectionTitleSize(size),
            ),
          ),
          const SizedBox(height: 5),
          SizedBox(
            height: rowHeight,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: entries.length,
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (context, index) {
                final entry = entries[index];
                return _ContinueWatchingCard(
                  entry: entry,
                  width: cardWidth,
                  onPressed: () => onOpen(entry),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _ContinueWatchingCard extends ConsumerWidget {
  const _ContinueWatchingCard({
    required this.entry,
    required this.width,
    required this.onPressed,
  });

  final ContinueWatchingEntry entry;
  final double width;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final posterUrl = ref
        .watch(_continuePosterProvider(entry))
        .maybeWhen(data: (url) => url, orElse: () => null);
    final imageUrl = posterUrl ?? entry.artworkUrl ?? '';
    return FocusableScale(
      borderRadius: 7,
      scale: 1.03,
      onPressed: onPressed,
      child: SizedBox(
        width: width,
        child: AspectRatio(
          aspectRatio: 2 / 3,
          child: DecoratedBox(
            decoration: const BoxDecoration(color: Color(0xFF202020)),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(7),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (imageUrl.isNotEmpty)
                    CachedNetworkImage(
                      imageUrl: imageUrl,
                      fit: BoxFit.cover,
                      memCacheWidth: 360,
                    )
                  else
                    Center(
                      child: Padding(
                        padding: const EdgeInsets.all(8),
                        child: Text(entry.title, textAlign: TextAlign.center),
                      ),
                    ),
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          Color(0x22000000),
                          Colors.black87,
                        ],
                        stops: [.45, .72, 1],
                      ),
                    ),
                  ),
                  const Center(
                    child: Icon(
                      Icons.play_circle_fill,
                      color: WenaTheme.red,
                      size: 30,
                    ),
                  ),
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: LinearProgressIndicator(
                      value: entry.progress,
                      minHeight: 4,
                      color: WenaTheme.red,
                      backgroundColor: Colors.white24,
                    ),
                  ),
                  Positioned(
                    left: 7,
                    right: 7,
                    bottom: 8,
                    child: Text(
                      entry.isSeries
                          ? 'S${entry.season ?? 1} E${entry.episode ?? 1}'
                          : _shortDuration(entry.position),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 9.5,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
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
    final posterWidth = _homeRowPosterWidth(size, contentInset);
    final rowHeight = _homeRowHeightFor(posterWidth);
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
              // Fix 9: Higher cacheExtent pre-renders off-screen cards so
              // fast D-pad navigation is jank-free on TV.
              cacheExtent: 1200,
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

class _HomeUpdatingBadge extends StatelessWidget {
  const _HomeUpdatingBadge();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: .58),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: .12)),
      ),
      child: const Padding(
        padding: EdgeInsets.symmetric(horizontal: 11, vertical: 7),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: WenaTheme.red,
              ),
            ),
            SizedBox(width: 8),
            Text(
              'Updating',
              style: TextStyle(
                color: Colors.white70,
                fontSize: 11,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
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
