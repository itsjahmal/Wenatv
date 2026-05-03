import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/config/api_config.dart';
import '../../core/theme/app_theme.dart';
import '../../data/models/media_item.dart';
import '../../data/repositories/tmdb_repository.dart';
import '../../features/player/player_screen.dart';
import '../../features/providers/provider_interface.dart';
import '../../features/providers/provider_js_bridge.dart';
import '../../features/providers/provider_manager_controller.dart';
import '../../features/providers/provider_stream_resolver.dart';
import '../../features/providers/unified_availability_service.dart';
import '../../features/watchlist/watchlist_controller.dart';
import '../../shared/widgets/focusable_scale.dart';
import '../../shared/widgets/poster_card.dart';
import '../../shared/widgets/wena_button.dart';
import '../../widgets/focusable_card.dart';

final detailsProvider =
    FutureProvider.family<MediaItem, ({int id, MediaKind kind})>((ref, args) {
      return ref.watch(tmdbRepositoryProvider).details(args.id, args.kind);
    });

final recommendationsProvider =
    FutureProvider.family<List<MediaItem>, ({int id, MediaKind kind})>((
      ref,
      args,
    ) {
      return ref
          .watch(tmdbRepositoryProvider)
          .recommendations(args.id, args.kind);
    });

final castProvider =
    FutureProvider.family<List<CastMember>, ({int id, MediaKind kind})>((
      ref,
      args,
    ) {
      return ref.watch(tmdbRepositoryProvider).cast(args.id, args.kind);
    });

final episodesProvider =
    FutureProvider.family<List<EpisodeItem>, ({int tvId, int season})>((
      ref,
      args,
    ) {
      return ref
          .watch(tmdbRepositoryProvider)
          .seasonEpisodes(args.tvId, args.season);
    });

final availableStreamsProvider =
    FutureProvider.family<List<StreamSource>, StreamLookup>((ref, lookup) {
      return _resolveStreams(ref, lookup);
    });

class StreamLookup {
  const StreamLookup({required this.item, this.season = 1, this.episode = 1});

  final MediaItem item;
  final int season;
  final int episode;

  @override
  bool operator ==(Object other) {
    return other is StreamLookup &&
        other.item.id == item.id &&
        other.item.kind == item.kind &&
        other.item.sourceProvider == item.sourceProvider &&
        other.item.sourceLink == item.sourceLink &&
        other.season == season &&
        other.episode == episode;
  }

  @override
  int get hashCode => Object.hash(
    item.id,
    item.kind,
    item.sourceProvider,
    item.sourceLink,
    season,
    episode,
  );
}

Future<List<StreamSource>> _resolveStreams(Ref ref, StreamLookup lookup) async {
  final providers = ref.watch(providerFallbackOrderProvider);
  final found = <String, StreamSource>{};
  final ordered = providers.isEmpty
      ? const [
          ActiveProviderSelection(
            sourceUrl: 'autoEmbed',
            value: 'autoEmbed',
            displayName: 'MultiStream',
            type: 'global',
          ),
        ]
      : providers;
  for (final selection in ordered) {
    final provider = _InstalledProvider(
      sourceUrl: selection.sourceUrl,
      value: selection.value,
      displayName: selection.displayName,
    );
    final streams = await _resolveProviderStreams(ref, provider, lookup)
        .timeout(const Duration(seconds: 45), onTimeout: () => const [])
        .catchError((_) => const <StreamSource>[]);
    for (final stream in streams) {
      if (stream.url.isEmpty) continue;
      final isSeries = lookup.item.kind == MediaKind.tv;
      found[stream.url] = stream.copyWith(
        providerName: stream.providerName ?? provider.displayName,
        season: isSeries ? stream.season ?? lookup.season : null,
        episode: isSeries ? stream.episode ?? lookup.episode : null,
      );
    }
  }
  return found.values.toList();
}

Future<List<StreamSource>> _resolveProviderStreams(
  Ref ref,
  _InstalledProvider provider,
  StreamLookup lookup,
) async {
  final item = lookup.item;
  if (provider.value == 'autoEmbed') {
    return ref
        .read(providerStreamResolverProvider)
        .resolve(
          providerValue: provider.value,
          providerName: provider.displayName,
          item: item,
          season: lookup.season,
          episode: lookup.episode,
        );
  }

  final bridge = ref.read(providerJsBridgeProvider);
  final providerLink =
      item.sourceProvider == provider.value &&
          (item.sourceUrl == null || item.sourceUrl == provider.sourceUrl)
      ? item.sourceLink
      : null;
  final contentLink = providerLink == null || providerLink.isEmpty
      ? await _searchProviderLink(bridge, provider, item)
      : providerLink;
  if (contentLink == null || contentLink.isEmpty) return const [];

  if (provider.value == 'vega') {
    final nativeStreams = await bridge
        .resolveNativeVegaStreams(
          contentLink: contentLink,
          title: item.title,
          type: item.kind == MediaKind.tv ? 'series' : 'movie',
        )
        .timeout(const Duration(seconds: 45), onTimeout: () => const []);
    if (nativeStreams.isNotEmpty) return nativeStreams;
  }

  final meta = await bridge
      .getMeta(
        sourceUrl: provider.sourceUrl,
        providerValue: provider.value,
        link: contentLink,
      )
      .timeout(const Duration(seconds: 35), onTimeout: () => null);
  if (meta == null) return const [];

  var directLinks = meta.linkList
      .expand((link) => link.directLinks)
      .where((link) => link.link.isNotEmpty)
      .toList();

  if (directLinks.isEmpty) {
    final episodesLink = meta.linkList
        .map((link) => link.episodesLink)
        .where((link) => link.isNotEmpty)
        .firstOrNull;
    if (episodesLink != null) {
      final episodes = await bridge
          .getEpisodes(
            sourceUrl: provider.sourceUrl,
            providerValue: provider.value,
            episodesLink: episodesLink,
          )
          .timeout(const Duration(seconds: 35), onTimeout: () => const []);
      directLinks = episodes;
    }
  }

  if (directLinks.isEmpty) return const [];
  final selectedLinks = lookup.item.kind == MediaKind.tv
      ? directLinks.skip((lookup.episode - 1).clamp(0, directLinks.length - 1))
      : directLinks;
  final links = selectedLinks.take(4).toList();
  final type = item.kind == MediaKind.tv ? 'series' : 'movie';
  final resolved = await Future.wait([
    for (final direct in links)
      bridge
          .getStreams(
            sourceUrl: provider.sourceUrl,
            providerValue: provider.value,
            link: direct.link,
            type: type,
          )
          .timeout(const Duration(seconds: 45), onTimeout: () => const []),
  ]);

  return resolved
      .expand((streams) => streams)
      .map(
        (stream) => stream.copyWith(
          providerName: provider.displayName,
          label: stream.label,
        ),
      )
      .toList();
}

Future<String?> _searchProviderLink(
  ProviderJsBridge bridge,
  _InstalledProvider provider,
  MediaItem item,
) async {
  final posts = await bridge
      .searchPosts(
        sourceUrl: provider.sourceUrl,
        providerValue: provider.value,
        query: item.title,
      )
      .timeout(const Duration(seconds: 35), onTimeout: () => const []);
  if (posts.isEmpty) return null;
  final match = _bestProviderPostMatch(posts, item.title, item.year, item.kind);
  return match?.link;
}

ProviderPost? _bestProviderPostMatch(
  List<ProviderPost> posts,
  String title,
  String year,
  MediaKind kind,
) {
  final target = _normalizeProviderMatchTitle(title);
  ProviderPost? best;
  var bestScore = 0.0;
  for (final post in posts) {
    final raw = post.title;
    final candidate = _normalizeProviderMatchTitle(raw);
    if (candidate.isEmpty) continue;
    var score = _titleSimilarity(target, candidate);
    if (year.isNotEmpty && raw.contains(year)) score += .14;
    if (candidate == target) score += .25;
    if (kind == MediaKind.movie && _looksLikeSeriesRelease(raw)) score -= .35;
    if (kind == MediaKind.tv && _looksLikeSeriesRelease(raw)) score += .08;
    if (score > bestScore) {
      bestScore = score;
      best = post;
    }
  }
  final requiredScore = kind == MediaKind.movie ? .72 : .58;
  return bestScore >= requiredScore ? best : null;
}

String _normalizeProviderMatchTitle(String value) {
  return value
      .toLowerCase()
      .replaceFirst(RegExp(r'^download\s+', caseSensitive: false), '')
      .replaceAll(RegExp(r'\[[^\]]*\]|\([^)]*\)|\{[^}]*\}'), ' ')
      .replaceAll(RegExp(r'\b(19|20)\d{2}\b'), ' ')
      .replaceAll(
        RegExp(
          r'\b(480p|720p|1080p|2160p|4k|uhd|hdr|sdr|hevc|x264|x265|10bit|web[- ]?dl|webrip|bluray|brrip|hdrip|dual audio|multi audio|hindi|english|esub|nf|amzn)\b',
          caseSensitive: false,
        ),
        ' ',
      )
      .replaceAll(
        RegExp(
          r'\b(S\d{1,2}\s*E\d{1,3}(?:\s*-\s*\d{1,3})?|Season\s*\d+|Episode\s*\d+|Ep\s*\d+)\b',
          caseSensitive: false,
        ),
        ' ',
      )
      .replaceAll(
        RegExp(
          r'\b(Prime Video|Amazon Prime Video|Amazon Prime|Netflix|Disney\+|Hotstar|HBO Max|Apple TV|Hulu)\b',
          caseSensitive: false,
        ),
        ' ',
      )
      .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

double _titleSimilarity(String a, String b) {
  if (a.isEmpty || b.isEmpty) return 0;
  if (a == b) return 1;
  if (a.contains(b) || b.contains(a)) return .82;
  final left = a.split(' ').where((word) => word.length > 1).toSet();
  final right = b.split(' ').where((word) => word.length > 1).toSet();
  if (left.isEmpty || right.isEmpty) return 0;
  return left.intersection(right).length / left.union(right).length;
}

bool _looksLikeSeriesRelease(String value) {
  return RegExp(
    r'\b(S\d{1,2}\s*E\d{1,3}|Season\s*\d+|Episode\s*\d+|Ep\s*\d+)\b',
    caseSensitive: false,
  ).hasMatch(value);
}

class _InstalledProvider {
  const _InstalledProvider({
    required this.sourceUrl,
    required this.value,
    required this.displayName,
  });

  final String sourceUrl;
  final String value;
  final String displayName;
}

class DetailsScreen extends ConsumerWidget {
  const DetailsScreen({
    super.key,
    required this.id,
    required this.kind,
    this.initialItem,
  });

  final int id;
  final MediaKind kind;
  final MediaItem? initialItem;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final details = ref.watch(detailsProvider((id: id, kind: kind)));
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (context.canPop()) {
          context.pop();
        } else {
          context.go('/');
        }
      },
      child: Scaffold(
        body: details.when(
          data: (item) =>
              _DetailsBody(item: _mergeInitialDetails(item, initialItem)),
          loading: () => initialItem == null
              ? const Center(
                  child: CircularProgressIndicator(color: WenaTheme.red),
                )
              : _DetailsBody(item: initialItem!),
          error: (_, __) => Center(
            child: WenaButton(
              label: 'Back',
              icon: Icons.arrow_back,
              primary: true,
              onPressed: () => context.pop(),
            ),
          ),
        ),
      ),
    );
  }
}

MediaItem _mergeInitialDetails(MediaItem details, MediaItem? initial) {
  if (initial == null) return details;
  return details.copyWith(
    externalPosterUrl: details.externalPosterUrl ?? initial.externalPosterUrl,
    externalBackdropUrl:
        details.externalBackdropUrl ?? initial.externalBackdropUrl,
    sourceUrl: initial.sourceUrl,
    sourceProvider: initial.sourceProvider,
    sourceProviderName: initial.sourceProviderName,
    sourceLink: initial.sourceLink,
    sourceTitle: initial.sourceTitle,
  );
}

class _DetailsBody extends ConsumerStatefulWidget {
  const _DetailsBody({required this.item});

  final MediaItem item;

  @override
  ConsumerState<_DetailsBody> createState() => _DetailsBodyState();
}

class _DetailsBodyState extends ConsumerState<_DetailsBody> {
  int _selectedSeason = 1;
  int _selectedEpisode = 1;
  int _selectedSeriesTab = 1;
  int _selectedMovieTab = 0;
  String? _selectedStreamUrl;

  MediaItem get item => widget.item;

  @override
  Widget build(BuildContext context) {
    final recs = ref.watch(
      recommendationsProvider((id: item.id, kind: item.kind)),
    );
    final watchlisted = ref.watch(
      watchlistProvider.select(
        (items) => items.any(
          (saved) => saved.id == item.id && saved.kind == item.kind,
        ),
      ),
    );
    final cast = item.kind == MediaKind.movie
        ? ref.watch(castProvider((id: item.id, kind: item.kind)))
        : const AsyncValue<List<CastMember>>.data(<CastMember>[]);
    final episodes = item.kind == MediaKind.tv
        ? ref.watch(episodesProvider((tvId: item.id, season: _selectedSeason)))
        : null;
    final episodeItems =
        episodes?.whenOrNull(data: (items) => items) ?? const <EpisodeItem>[];
    if (item.kind == MediaKind.tv && episodeItems.isNotEmpty) {
      ref.watch(
        unifiedAvailabilityProvider(
          UnifiedAvailabilityRequest(
            tmdbShowId: item.id,
            showTitle: item.title,
            firstAirYear: int.tryParse(item.year),
            episodes: episodeItems,
          ),
        ),
      );
    }
    final selectedEpisode = episodeItems.firstWhere(
      (episode) => episode.number == _selectedEpisode,
      orElse: () => episodeItems.isEmpty
          ? EpisodeItem(
              id: 0,
              season: _selectedSeason,
              number: _selectedEpisode,
              title: 'Episode $_selectedEpisode',
              overview: item.overview,
              stillPath: item.backdropPath,
              runtime: item.runtime,
            )
          : episodeItems.first,
    );
    if (episodeItems.isNotEmpty &&
        !episodeItems.any((episode) => episode.number == _selectedEpisode)) {
      _selectedEpisode = episodeItems.first.number;
    }
    final streamLookup = StreamLookup(
      item: item,
      season: _selectedSeason,
      episode: item.kind == MediaKind.tv ? _selectedEpisode : 1,
    );
    final streams = ref.watch(availableStreamsProvider(streamLookup));
    final sortedStreams =
        streams.whenOrNull(data: _playbackSortedStreams) ??
        const <StreamSource>[];
    final selectedStream = _selectedStream(sortedStreams);
    if (item.kind == MediaKind.tv) {
      return _SeriesDetailsScreen(
        item: item,
        selectedSeason: _selectedSeason,
        selectedEpisode: _selectedEpisode,
        selectedTab: _selectedSeriesTab,
        episodes: episodeItems,
        loadingEpisodes: episodes?.isLoading == true,
        recommendations: recs,
        selectedStream: selectedStream,
        watchlisted: watchlisted,
        onPlay: () => _openEpisode(selectedEpisode, episodeItems),
        onTrailer: () => _openTrailer(context, ref),
        onWatchlist: _toggleWatchlist,
        onTab: (index) => setState(() => _selectedSeriesTab = index),
        onSeason: (season) {
          setState(() {
            _selectedSeason = season;
            _selectedEpisode = 1;
            _selectedStreamUrl = null;
          });
        },
        onEpisode: (episode) {
          setState(() {
            _selectedSeason = episode.season;
            _selectedEpisode = episode.number;
            _selectedStreamUrl = null;
          });
          _openEpisode(episode, episodeItems);
        },
      );
    }
    return _MovieDetailsScreen(
      item: item,
      selectedTab: _selectedMovieTab,
      cast: cast,
      recommendations: recs,
      onPlay: _openMovie,
      onTrailer: () => _openTrailer(context, ref),
      watchlisted: watchlisted,
      onWatchlist: _toggleWatchlist,
      onTab: (index) => setState(() => _selectedMovieTab = index),
    );
  }

  StreamSource? _selectedStream(List<StreamSource> streams) {
    if (streams.isEmpty) return null;
    if (_selectedStreamUrl != null) {
      for (final stream in streams) {
        if (stream.url == _selectedStreamUrl) return stream;
      }
      final preferred = _preferredStream(streams, streams.first);
      return preferred;
    }
    return streams.first;
  }

  void _openSelectedStream(
    StreamSource stream,
    List<StreamSource> allStreams,
    List<EpisodeItem> episodes, {
    EpisodeItem? currentEpisode,
  }) {
    _openStream(
      context,
      ref,
      item,
      stream,
      allStreams: allStreams,
      episodes: episodes,
      currentEpisode: currentEpisode,
      preferredStream: stream,
    );
  }

  Future<void> _openEpisode(
    EpisodeItem episode,
    List<EpisodeItem> seasonEpisodes,
  ) async {
    final lookup = StreamLookup(
      item: item,
      season: episode.season,
      episode: episode.number,
    );
    final streams = await ref
        .read(availableStreamsProvider(lookup).future)
        .catchError((_) => const <StreamSource>[]);
    final sorted = _playbackSortedStreams(streams);
    final selected = _selectedStream(sorted);
    if (!mounted) return;
    if (selected == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("We couldn't find a working stream for this episode."),
        ),
      );
      return;
    }
    setState(() {
      _selectedSeason = episode.season;
      _selectedEpisode = episode.number;
      _selectedStreamUrl = selected.url;
    });
    _openSelectedStream(
      selected,
      sorted,
      seasonEpisodes,
      currentEpisode: episode,
    );
  }

  Future<void> _openMovie() async {
    final lookup = StreamLookup(item: item, season: 1, episode: 1);
    final streams = await ref
        .read(availableStreamsProvider(lookup).future)
        .catchError((_) => const <StreamSource>[]);
    final sorted = _playbackSortedStreams(streams);
    final selected = _selectedStream(sorted);
    if (!mounted) return;
    if (selected == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("We couldn't find a working stream for this movie."),
        ),
      );
      return;
    }
    setState(() => _selectedStreamUrl = selected.url);
    _openSelectedStream(selected, sorted, const []);
  }

  void _openTrailer(BuildContext context, WidgetRef ref) {
    context.push('/trailer/${item.kind.name}/${item.id}', extra: item.title);
  }

  Future<void> _toggleWatchlist() async {
    final added = await ref.read(watchlistProvider.notifier).toggle(item);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(added ? 'Added to Watchlist' : 'Removed from Watchlist'),
        duration: const Duration(milliseconds: 1300),
      ),
    );
  }
}

class _MovieDetailsScreen extends StatelessWidget {
  const _MovieDetailsScreen({
    required this.item,
    required this.selectedTab,
    required this.cast,
    required this.recommendations,
    required this.onPlay,
    required this.onTrailer,
    required this.watchlisted,
    required this.onWatchlist,
    required this.onTab,
  });

  final MediaItem item;
  final int selectedTab;
  final AsyncValue<List<CastMember>> cast;
  final AsyncValue<List<MediaItem>> recommendations;
  final VoidCallback onPlay;
  final VoidCallback onTrailer;
  final bool watchlisted;
  final VoidCallback onWatchlist;
  final ValueChanged<int> onTab;

  @override
  Widget build(BuildContext context) {
    final backdrop =
        item.externalBackdropUrl ?? ApiConfig.backdrop(item.backdropPath);
    final size = MediaQuery.sizeOf(context);
    final horizontalInset = TvLayout.horizontalInset(size);
    final heroHeight = TvLayout.movieHeroHeight(size);
    assert(() {
      debugPrint(
        'TV MovieDetails size=$size dpr=${MediaQuery.devicePixelRatioOf(context)} '
        'scale=${TvLayout.tvScale(size)} inset=$horizontalInset hero=$heroHeight',
      );
      return true;
    }());
    return Stack(
      fit: StackFit.expand,
      children: [
        if (backdrop.isNotEmpty)
          CachedNetworkImage(
            imageUrl: backdrop,
            fit: BoxFit.cover,
            memCacheWidth: 1600,
          ),
        Container(color: Colors.black.withValues(alpha: .22)),
        Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: [
                Colors.black,
                Color(0xF0000000),
                Color(0xAA000000),
                Color(0x10000000),
              ],
              stops: [0, .34, .58, 1],
            ),
          ),
        ),
        Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0x11000000), Color(0xDD000000), Colors.black],
              stops: [0, .62, 1],
            ),
          ),
        ),
        SafeArea(
          child: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: heroHeight),
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(
                      horizontalInset,
                      (size.height * .024).clamp(12.0, 18.0).toDouble(),
                      horizontalInset,
                      8,
                    ),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 740),
                        child: _MovieHeroInfo(
                          size: size,
                          item: item,
                          onPlay: onPlay,
                          onTrailer: onTrailer,
                          watchlisted: watchlisted,
                          onWatchlist: onWatchlist,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    horizontalInset,
                    0,
                    horizontalInset,
                    0,
                  ),
                  child: _MovieTabBar(selected: selectedTab, onSelected: onTab),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    horizontalInset,
                    14,
                    horizontalInset,
                    24,
                  ),
                  child: _MovieTabContent(
                    selectedTab: selectedTab,
                    item: item,
                    cast: cast,
                    recommendations: recommendations,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _MovieHeroInfo extends StatelessWidget {
  const _MovieHeroInfo({
    required this.size,
    required this.item,
    required this.onPlay,
    required this.onTrailer,
    required this.watchlisted,
    required this.onWatchlist,
  });

  final Size size;
  final MediaItem item;
  final VoidCallback onPlay;
  final VoidCallback onTrailer;
  final bool watchlisted;
  final VoidCallback onWatchlist;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          item.title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.displayLarge?.copyWith(
            fontSize: TvLayout.detailTitleSize(size),
            height: .98,
            shadows: const [Shadow(color: Colors.black, blurRadius: 18)],
          ),
        ),
        const SizedBox(height: 7),
        Wrap(
          spacing: 8,
          runSpacing: 5,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            _RatingBadge(rating: item.rating),
            if (item.year.isNotEmpty) Text(item.year),
            if (item.runtime != null) Text(_runtimeLabel(item.runtime!)),
            const Text('PG-13', style: TextStyle(color: Colors.white70)),
            if (item.genres.isNotEmpty)
              Text(
                item.genres.take(3).join(' | '),
                style: const TextStyle(color: Colors.white70),
              ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          item.overview,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
            color: Colors.white.withValues(alpha: .84),
            fontSize: (TvLayout.bodySize(size) - .8).clamp(11.5, 14.2),
            height: 1.32,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 5,
          children: [
            _MovieActionButton(
              label: 'Play',
              icon: Icons.play_arrow,
              autofocus: true,
              scale: TvLayout.tvScale(size),
              onPressed: onPlay,
            ),
            _MovieActionButton(
              label: 'Watch Trailer',
              icon: Icons.movie_outlined,
              scale: TvLayout.tvScale(size),
              onPressed: onTrailer,
            ),
            _MovieActionButton(
              label: watchlisted ? 'In Watchlist' : 'Watchlist',
              icon: watchlisted
                  ? Icons.check_circle_outline
                  : Icons.add_circle_outline,
              scale: TvLayout.tvScale(size),
              onPressed: onWatchlist,
            ),
          ],
        ),
      ],
    );
  }
}

class _MovieActionButton extends StatefulWidget {
  const _MovieActionButton({
    required this.label,
    required this.icon,
    required this.onPressed,
    this.autofocus = false,
    this.scale = 1,
  });

  final String label;
  final IconData icon;
  final VoidCallback onPressed;
  final bool autofocus;
  final double scale;

  @override
  State<_MovieActionButton> createState() => _MovieActionButtonState();
}

class _MovieActionButtonState extends State<_MovieActionButton> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final scale = widget.scale;
    return FocusableActionDetector(
      autofocus: widget.autofocus,
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.select): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
      },
      actions: {
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) {
            widget.onPressed();
            return null;
          },
        ),
      },
      onFocusChange: (value) => setState(() => _focused = value),
      child: GestureDetector(
        onTap: widget.onPressed,
        child: AnimatedScale(
          scale: _focused ? 1.018 : 1,
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            height: (34 * scale).clamp(31.0, 38.0).toDouble(),
            padding: EdgeInsets.symmetric(
              horizontal: (14 * scale).clamp(12.0, 17.0).toDouble(),
            ),
            decoration: BoxDecoration(
              color: _focused
                  ? WenaTheme.red
                  : Colors.white.withValues(alpha: .92),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: _focused
                    ? WenaTheme.red
                    : Colors.white.withValues(alpha: .22),
              ),
              boxShadow: _focused
                  ? [
                      BoxShadow(
                        color: WenaTheme.red.withValues(alpha: .30),
                        blurRadius: 16,
                      ),
                    ]
                  : null,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  widget.icon,
                  size: (15 * scale).clamp(13.0, 17.0).toDouble(),
                  color: _focused ? Colors.white : Colors.black,
                ),
                SizedBox(width: (7 * scale).clamp(5.0, 8.0).toDouble()),
                Text(
                  widget.label,
                  style: TextStyle(
                    color: _focused ? Colors.white : Colors.black,
                    fontSize: (11.4 * scale).clamp(10.2, 12.4).toDouble(),
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MovieTabBar extends StatelessWidget {
  const _MovieTabBar({required this.selected, required this.onSelected});

  final int selected;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    const labels = ['Overview', 'Cast', 'More Like This'];
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Colors.white.withValues(alpha: .14)),
        ),
      ),
      child: Row(
        children: [
          for (var index = 0; index < labels.length; index++)
            _MovieTab(
              label: labels[index],
              selected: selected == index,
              onPressed: () => onSelected(index),
            ),
        ],
      ),
    );
  }
}

class _MovieTab extends StatefulWidget {
  const _MovieTab({
    required this.label,
    required this.selected,
    required this.onPressed,
  });

  final String label;
  final bool selected;
  final VoidCallback onPressed;

  @override
  State<_MovieTab> createState() => _MovieTabState();
}

class _MovieTabState extends State<_MovieTab> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    return FocusableActionDetector(
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.select): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
      },
      actions: {
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) {
            widget.onPressed();
            return null;
          },
        ),
      },
      onFocusChange: (value) => setState(() => _focused = value),
      child: GestureDetector(
        onTap: widget.onPressed,
        child: AnimatedScale(
          scale: _focused ? 1.012 : 1,
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: widget.label == 'More Like This' ? 120 : 78,
            padding: const EdgeInsets.symmetric(vertical: 6),
            alignment: Alignment.centerLeft,
            decoration: BoxDecoration(
              color: _focused
                  ? Colors.white.withValues(alpha: .055)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(7),
              border: Border(
                bottom: BorderSide(
                  color: _focused
                      ? WenaTheme.red
                      : widget.selected
                      ? Colors.white.withValues(alpha: .36)
                      : Colors.transparent,
                  width: _focused ? 2.5 : 1.2,
                ),
              ),
            ),
            child: Text(
              widget.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: widget.selected ? Colors.white : Colors.white60,
                fontSize: 10.8,
                fontWeight: widget.selected ? FontWeight.w900 : FontWeight.w700,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MovieTabContent extends StatelessWidget {
  const _MovieTabContent({
    required this.selectedTab,
    required this.item,
    required this.cast,
    required this.recommendations,
  });

  final int selectedTab;
  final MediaItem item;
  final AsyncValue<List<CastMember>> cast;
  final AsyncValue<List<MediaItem>> recommendations;

  @override
  Widget build(BuildContext context) {
    if (selectedTab == 1) {
      return cast.when(
        data: (items) => _MovieCastSection(items: _castItems(items)),
        loading: () => const _DetailsLoadingStrip(),
        error: (_, __) => _MovieCastSection(items: _fallbackCast()),
      );
    }
    if (selectedTab == 2) {
      return recommendations.when(
        data: (items) => _MoviePosterRecommendations(items: items),
        loading: () => const _DetailsLoadingStrip(),
        error: (_, __) => const SizedBox.shrink(),
      );
    }
    return _MovieOverviewPanel(item: item);
  }
}

class _MovieOverviewPanel extends StatelessWidget {
  const _MovieOverviewPanel({required this.item});

  final MediaItem item;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: (size.width * .62).clamp(560, 760)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Overview',
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontSize: 16),
          ),
          const SizedBox(height: 6),
          Text(
            item.overview.isEmpty
                ? 'No overview is available for this movie yet.'
                : item.overview,
            style: TextStyle(
              color: Colors.white.withValues(alpha: .78),
              fontSize: (TvLayout.bodySize(size) - 1).clamp(11.5, 14.0),
              height: 1.38,
            ),
          ),
        ],
      ),
    );
  }
}

class _MoviePosterRecommendations extends StatelessWidget {
  const _MoviePosterRecommendations({required this.items});

  final List<MediaItem> items;

  @override
  Widget build(BuildContext context) {
    final displayItems = items.isEmpty ? _fallbackRecommendations() : items;
    final size = MediaQuery.sizeOf(context);
    final cardWidth = TvLayout.posterWidthFor(size);
    final rowHeight = (cardWidth * 1.5) + 8;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'More Like This',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(fontSize: 16),
        ),
        const SizedBox(height: 6),
        SizedBox(
          height: rowHeight,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: displayItems.take(10).length,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (context, index) {
              final item = displayItems[index];
              return PosterCard(
                item: item,
                width: cardWidth,
                onPressed: () => item.id <= 0
                    ? null
                    : context.push('/details/${item.kind.name}/${item.id}'),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _MovieCastSection extends StatelessWidget {
  const _MovieCastSection({required this.items});

  final List<CastMember> items;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    final size = MediaQuery.sizeOf(context);
    final rowHeight = (size.height * .078).clamp(50.0, 62.0).toDouble();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Top Cast',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(fontSize: 16),
        ),
        const SizedBox(height: 6),
        SizedBox(
          height: rowHeight,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: items.take(8).length,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (context, index) {
              final member = items[index];
              return _CastCard(member: member);
            },
          ),
        ),
      ],
    );
  }
}

class _CastCard extends StatelessWidget {
  const _CastCard({required this.member});

  final CastMember member;

  @override
  Widget build(BuildContext context) {
    final imageUrl = ApiConfig.poster(member.profilePath, size: 'w185');
    final size = MediaQuery.sizeOf(context);
    final cardWidth = (size.width * .145).clamp(138.0, 174.0).toDouble();
    final cardHeight = (size.height * .078).clamp(50.0, 62.0).toDouble();
    final imageWidth = (cardHeight * .82).clamp(42.0, 52.0).toDouble();
    return SizedBox(
      width: cardWidth,
      child: FocusableScale(
        borderRadius: 9,
        scale: 1.02,
        onPressed: () {},
        child: Container(
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: .42),
            borderRadius: BorderRadius.circular(9),
            border: Border.all(color: Colors.white.withValues(alpha: .14)),
          ),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: const BorderRadius.horizontal(
                  left: Radius.circular(8),
                ),
                child: imageUrl.isEmpty
                    ? Container(
                        width: imageWidth,
                        height: cardHeight,
                        color: WenaTheme.soft,
                      )
                    : CachedNetworkImage(
                        imageUrl: imageUrl,
                        width: imageWidth,
                        height: cardHeight,
                        fit: BoxFit.cover,
                      ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      member.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11.2,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      member.character.isEmpty ? 'Cast' : member.character,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white60,
                        fontSize: 10.2,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
            ],
          ),
        ),
      ),
    );
  }
}

class _DetailsLoadingStrip extends StatelessWidget {
  const _DetailsLoadingStrip();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      height: 92,
      child: Center(child: CircularProgressIndicator(color: WenaTheme.red)),
    );
  }
}

List<CastMember> _castItems(List<CastMember> items) {
  return items.isEmpty ? _fallbackCast() : items;
}

List<CastMember> _fallbackCast() {
  return const [
    CastMember(name: 'Maya Cole', character: 'Nova', profilePath: null),
    CastMember(name: 'Daniel Cross', character: 'Orin', profilePath: null),
    CastMember(name: 'Lena Hart', character: 'Vale', profilePath: null),
    CastMember(name: 'Marcus Reed', character: 'Kade', profilePath: null),
  ];
}

List<MediaItem> _fallbackRecommendations() {
  return const [
    MediaItem(
      id: 0,
      kind: MediaKind.movie,
      title: 'Neon Fall',
      overview: '',
      posterPath: null,
      backdropPath: null,
      rating: 0,
      releaseDate: '',
    ),
    MediaItem(
      id: 0,
      kind: MediaKind.movie,
      title: 'Dark Orbit',
      overview: '',
      posterPath: null,
      backdropPath: null,
      rating: 0,
      releaseDate: '',
    ),
    MediaItem(
      id: 0,
      kind: MediaKind.movie,
      title: 'Velocity Line',
      overview: '',
      posterPath: null,
      backdropPath: null,
      rating: 0,
      releaseDate: '',
    ),
    MediaItem(
      id: 0,
      kind: MediaKind.movie,
      title: 'Red Shift',
      overview: '',
      posterPath: null,
      backdropPath: null,
      rating: 0,
      releaseDate: '',
    ),
    MediaItem(
      id: 0,
      kind: MediaKind.movie,
      title: 'Zero Signal',
      overview: '',
      posterPath: null,
      backdropPath: null,
      rating: 0,
      releaseDate: '',
    ),
  ];
}

class _RatingBadge extends StatelessWidget {
  const _RatingBadge({required this.rating});

  final double rating;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.star, color: Color(0xFFFFC400), size: 18),
        const SizedBox(width: 5),
        Text('${rating.toStringAsFixed(1)}/10'),
      ],
    );
  }
}

class _SeriesDetailsScreen extends StatelessWidget {
  const _SeriesDetailsScreen({
    required this.item,
    required this.selectedSeason,
    required this.selectedEpisode,
    required this.selectedTab,
    required this.episodes,
    required this.loadingEpisodes,
    required this.recommendations,
    required this.selectedStream,
    required this.watchlisted,
    required this.onPlay,
    required this.onTrailer,
    required this.onWatchlist,
    required this.onTab,
    required this.onSeason,
    required this.onEpisode,
  });

  final MediaItem item;
  final int selectedSeason;
  final int selectedEpisode;
  final int selectedTab;
  final List<EpisodeItem> episodes;
  final bool loadingEpisodes;
  final AsyncValue<List<MediaItem>> recommendations;
  final StreamSource? selectedStream;
  final bool watchlisted;
  final VoidCallback onPlay;
  final VoidCallback onTrailer;
  final VoidCallback onWatchlist;
  final ValueChanged<int> onTab;
  final ValueChanged<int> onSeason;
  final ValueChanged<EpisodeItem> onEpisode;

  @override
  Widget build(BuildContext context) {
    final backdrop =
        item.externalBackdropUrl ?? ApiConfig.backdrop(item.backdropPath);
    final size = MediaQuery.sizeOf(context);
    final horizontalInset = TvLayout.horizontalInset(size);
    final heroHeight = (TvLayout.seriesHeroHeight(size) * .88)
        .clamp(185.0, 238.0)
        .toDouble();
    assert(() {
      debugPrint(
        'TV SeriesDetails size=$size dpr=${MediaQuery.devicePixelRatioOf(context)} '
        'scale=${TvLayout.tvScale(size)} inset=$horizontalInset hero=$heroHeight',
      );
      return true;
    }());
    return Stack(
      fit: StackFit.expand,
      children: [
        if (backdrop.isNotEmpty)
          CachedNetworkImage(
            imageUrl: backdrop,
            fit: BoxFit.cover,
            memCacheWidth: 1600,
          ),
        Container(color: Colors.black.withValues(alpha: .28)),
        Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: [
                Colors.black,
                Color(0xEA000000),
                Color(0xA0000000),
                Color(0x18000000),
              ],
              stops: [0, .34, .62, 1],
            ),
          ),
        ),
        Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0x22000000), Color(0xF2000000), Colors.black],
              stops: [0, .55, 1],
            ),
          ),
        ),
        SafeArea(
          child: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: heroHeight),
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(
                      horizontalInset,
                      (size.height * .020).clamp(10.0, 17.0).toDouble(),
                      horizontalInset,
                      8,
                    ),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 700),
                        child: _SeriesHeroInfo(
                          size: size,
                          item: item,
                          stream: selectedStream,
                          watchlisted: watchlisted,
                          onPlay: onPlay,
                          onTrailer: onTrailer,
                          onWatchlist: onWatchlist,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    horizontalInset,
                    0,
                    horizontalInset,
                    0,
                  ),
                  child: _SeriesTabBar(
                    selected: selectedTab,
                    onSelected: onTab,
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    horizontalInset,
                    12,
                    horizontalInset,
                    24,
                  ),
                  child: selectedTab == 0
                      ? _SeriesOverviewPanel(item: item)
                      : selectedTab == 2
                      ? recommendations.when(
                          data: (items) => _SeriesRecommendations(items: items),
                          loading: () => const SizedBox(
                            height: 120,
                            child: Center(
                              child: CircularProgressIndicator(
                                color: WenaTheme.red,
                              ),
                            ),
                          ),
                          error: (_, __) => const SizedBox.shrink(),
                        )
                      : _SeriesEpisodeList(
                          item: item,
                          selectedSeason: selectedSeason,
                          selectedEpisode: selectedEpisode,
                          episodes: episodes,
                          loading: loadingEpisodes,
                          onSeason: onSeason,
                          onEpisode: onEpisode,
                        ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SeriesHeroInfo extends StatelessWidget {
  const _SeriesHeroInfo({
    required this.size,
    required this.item,
    required this.stream,
    required this.watchlisted,
    required this.onPlay,
    required this.onTrailer,
    required this.onWatchlist,
  });

  final Size size;
  final MediaItem item;
  final StreamSource? stream;
  final bool watchlisted;
  final VoidCallback onPlay;
  final VoidCallback onTrailer;
  final VoidCallback onWatchlist;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          item.title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.displayLarge?.copyWith(
            fontSize: TvLayout.detailTitleSize(size),
            height: 1,
            shadows: const [Shadow(color: Colors.black, blurRadius: 18)],
          ),
        ),
        const SizedBox(height: 5),
        Wrap(
          spacing: 8,
          runSpacing: 5,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            _RatingBadge(rating: item.rating),
            if (item.year.isNotEmpty) Text(item.year),
            Text(_seasonCountLabel(item.totalSeasons)),
            if (item.genres.isNotEmpty)
              Text(
                item.genres.take(3).join(' • '),
                style: const TextStyle(color: Colors.white70),
              ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          item.overview,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
            color: Colors.white.withValues(alpha: .82),
            fontSize: (TvLayout.bodySize(size) - .8).clamp(11.5, 14.2),
            height: 1.32,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 5,
          children: [
            _SeriesActionButton(
              label: 'Play',
              icon: Icons.play_arrow,
              autofocus: true,
              onPressed: onPlay,
            ),
            _SeriesActionButton(
              label: 'Trailer',
              icon: Icons.movie_outlined,
              onPressed: onTrailer,
            ),
            _SeriesActionButton(
              label: watchlisted ? 'In Watchlist' : 'Watchlist',
              icon: watchlisted ? Icons.check : Icons.add,
              onPressed: onWatchlist,
            ),
          ],
        ),
        if (stream != null) ...[
          const SizedBox(height: 6),
          Text(
            '${_cleanQuality(stream!.quality, stream!.url)} • ${_cleanContainer(stream!.format, stream!.url)}',
            style: const TextStyle(color: Colors.white54, fontSize: 11.5),
          ),
        ],
      ],
    );
  }
}

class _SeriesTabBar extends StatelessWidget {
  const _SeriesTabBar({required this.selected, required this.onSelected});

  final int selected;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    const labels = ['Overview', 'Episodes', 'More Like This'];
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Colors.white.withValues(alpha: .14)),
        ),
      ),
      child: Row(
        children: [
          for (var index = 0; index < labels.length; index++)
            _SeriesTab(
              label: labels[index],
              selected: selected == index,
              onPressed: () => onSelected(index),
            ),
        ],
      ),
    );
  }
}

class _SeriesTab extends StatelessWidget {
  const _SeriesTab({
    required this.label,
    required this.selected,
    required this.onPressed,
  });

  final String label;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return FocusableCard(
      borderRadius: 7,
      scale: 1.012,
      onPressed: onPressed,
      decorationBuilder: (focused, _) => BoxDecoration(
        color: focused
            ? Colors.white.withValues(alpha: .055)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(7),
      ),
      child: SizedBox(
        width: label == 'More Like This' ? 128 : 92,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 7),
          alignment: Alignment.centerLeft,
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: selected ? WenaTheme.red : Colors.transparent,
                width: 2.5,
              ),
            ),
          ),
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: selected ? Colors.white : Colors.white60,
              fontSize: 11.4,
              fontWeight: selected ? FontWeight.w900 : FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}

class _SeriesActionButton extends StatefulWidget {
  const _SeriesActionButton({
    required this.label,
    required this.icon,
    required this.onPressed,
    this.autofocus = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback onPressed;
  final bool autofocus;

  @override
  State<_SeriesActionButton> createState() => _SeriesActionButtonState();
}

class _SeriesActionButtonState extends State<_SeriesActionButton> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    return FocusableActionDetector(
      autofocus: widget.autofocus,
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.select): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
      },
      actions: {
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) {
            widget.onPressed();
            return null;
          },
        ),
      },
      onFocusChange: (value) => setState(() => _focused = value),
      child: GestureDetector(
        onTap: widget.onPressed,
        child: AnimatedScale(
          scale: _focused ? 1.018 : 1,
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            decoration: BoxDecoration(
              color: _focused
                  ? WenaTheme.red
                  : Colors.white.withValues(alpha: .92),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: _focused
                    ? WenaTheme.red
                    : Colors.white.withValues(alpha: .22),
              ),
              boxShadow: _focused
                  ? [
                      BoxShadow(
                        color: WenaTheme.red.withValues(alpha: .30),
                        blurRadius: 16,
                      ),
                    ]
                  : null,
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 7),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    widget.icon,
                    size: 16,
                    color: _focused ? Colors.white : Colors.black,
                  ),
                  const SizedBox(width: 7),
                  Text(
                    widget.label,
                    style: TextStyle(
                      color: _focused ? Colors.white : Colors.black,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w900,
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

class _SeriesEpisodeList extends StatelessWidget {
  const _SeriesEpisodeList({
    required this.item,
    required this.selectedSeason,
    required this.selectedEpisode,
    required this.episodes,
    required this.loading,
    required this.onSeason,
    required this.onEpisode,
  });

  final MediaItem item;
  final int selectedSeason;
  final int selectedEpisode;
  final List<EpisodeItem> episodes;
  final bool loading;
  final ValueChanged<int> onSeason;
  final ValueChanged<EpisodeItem> onEpisode;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final seasonHeight = (size.height * .048).clamp(28.0, 32.0).toDouble();
    final seasons = List.generate(
      (item.totalSeasons ?? selectedSeason).clamp(1, 30),
      (index) => index + 1,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: seasonHeight,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: seasons.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (context, index) {
              final season = seasons[index];
              return _SeriesSeasonButton(
                label: 'Season $season',
                selected: season == selectedSeason,
                onPressed: () => onSeason(season),
              );
            },
          ),
        ),
        const SizedBox(height: 6),
        if (loading)
          SizedBox(
            height: (size.height * .18).clamp(100.0, 140.0).toDouble(),
            child: Center(
              child: CircularProgressIndicator(color: WenaTheme.red),
            ),
          )
        else if (episodes.isEmpty)
          const _InlineStatus(
            icon: Icons.playlist_remove,
            message: 'No TMDB episodes loaded for this season yet.',
          )
        else
          Column(
            children: [
              for (final episode in episodes.take(24)) ...[
                _SeriesEpisodeRow(
                  episode: episode,
                  selected: episode.number == selectedEpisode,
                  onPressed: () => onEpisode(episode),
                ),
                const SizedBox(height: 5),
              ],
            ],
          ),
      ],
    );
  }
}

class _SeriesSeasonButton extends StatelessWidget {
  const _SeriesSeasonButton({
    required this.label,
    required this.selected,
    required this.onPressed,
  });

  final String label;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final scale = TvLayout.tvScale(size);
    return FocusableScale(
      borderRadius: 8,
      scale: 1.018,
      onPressed: onPressed,
      child: Container(
        width: (92 * scale).clamp(82.0, 102.0).toDouble(),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? WenaTheme.red : Colors.black.withValues(alpha: .28),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected
                ? WenaTheme.red
                : Colors.white.withValues(alpha: .20),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 11),
            ),
            const SizedBox(width: 5),
            const Icon(Icons.keyboard_arrow_down, size: 14),
          ],
        ),
      ),
    );
  }
}

class _SeriesEpisodeRow extends StatelessWidget {
  const _SeriesEpisodeRow({
    required this.episode,
    required this.selected,
    required this.onPressed,
  });

  final EpisodeItem episode;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final artwork = episode.stillPath == null
        ? ''
        : ApiConfig.backdrop(episode.stillPath, size: 'w500');
    final size = MediaQuery.sizeOf(context);
    final rowHeight = (size.height * .118).clamp(64.0, 78.0).toDouble();
    final thumbWidth = (rowHeight * 1.68).clamp(108.0, 132.0).toDouble();
    final thumbHeight = (thumbWidth * 9 / 16).clamp(60.0, 74.0).toDouble();
    return FocusableScale(
      borderRadius: 10,
      scale: 1.012,
      selected: selected,
      onPressed: onPressed,
      child: Container(
        height: rowHeight,
        padding: const EdgeInsets.all(5),
        decoration: BoxDecoration(
          color: selected
              ? WenaTheme.red.withValues(alpha: .14)
              : Colors.black.withValues(alpha: .36),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected
                ? WenaTheme.red
                : Colors.white.withValues(alpha: .12),
            width: selected ? 1.5 : 1,
          ),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: WenaTheme.red.withValues(alpha: .35),
                    blurRadius: 14,
                  ),
                ]
              : null,
        ),
        child: Row(
          children: [
            SizedBox(
              width: 24,
              child: Text(
                '${episode.number}',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            const SizedBox(width: 7),
            ClipRRect(
              borderRadius: BorderRadius.circular(7),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  artwork.isEmpty
                      ? Container(
                          width: thumbWidth,
                          height: thumbHeight,
                          color: WenaTheme.soft,
                        )
                      : CachedNetworkImage(
                          imageUrl: artwork,
                          width: thumbWidth,
                          height: thumbHeight,
                          fit: BoxFit.cover,
                        ),
                  Container(
                    width: 26,
                    height: 26,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.black.withValues(alpha: .48),
                      border: Border.all(color: Colors.white70),
                    ),
                    child: const Icon(Icons.play_arrow, size: 17),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    episode.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11.8,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    episode.overview,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white60,
                      fontSize: 9.8,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 38,
              child: Text(
                episode.runtime == null ? '' : '${episode.runtime}m',
                textAlign: TextAlign.right,
                style: const TextStyle(color: Colors.white70, fontSize: 10),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SeriesOverviewPanel extends StatelessWidget {
  const _SeriesOverviewPanel({required this.item});

  final MediaItem item;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 860),
      child: Text(
        item.overview,
        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
          color: Colors.white.withValues(alpha: .78),
          height: 1.45,
        ),
      ),
    );
  }
}

class _SeriesRecommendations extends StatelessWidget {
  const _SeriesRecommendations({required this.items});

  final List<MediaItem> items;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final posterWidth = TvLayout.posterWidthFor(size);
    return SizedBox(
      height: TvLayout.posterRowHeightFor(size),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (context, index) {
          final item = items[index];
          return PosterCard(
            item: item,
            width: posterWidth,
            onPressed: () =>
                context.push('/details/${item.kind.name}/${item.id}'),
          );
        },
      ),
    );
  }
}

void _openStream(
  BuildContext context,
  WidgetRef ref,
  MediaItem item,
  StreamSource stream, {
  List<StreamSource> allStreams = const [],
  List<EpisodeItem> episodes = const [],
  EpisodeItem? currentEpisode,
  StreamSource? preferredStream,
}) {
  final preferred = preferredStream ?? stream;
  final artworkUrl = _bestArtworkUrl(item);
  final episodeArtworkUrl = currentEpisode?.stillPath == null
      ? artworkUrl
      : ApiConfig.backdrop(currentEpisode!.stillPath, size: 'w780');
  context.push(
    '/player',
    extra: PlayerPayload(
      mediaId: item.id,
      kind: item.kind.name,
      title: item.title,
      streamUrl: stream.url,
      headers: stream.headers,
      subtitles: _playerSubtitles(stream.subtitles),
      currentStream: _playerStream(stream),
      fallbackStreams: _playerFallbackStreams(
        _preferredSortedStreams(allStreams, preferred),
        selected: stream,
      ),
      isSeries: item.kind == MediaKind.tv,
      artworkUrl: episodeArtworkUrl.isEmpty ? null : episodeArtworkUrl,
      overview: currentEpisode?.overview.isNotEmpty == true
          ? currentEpisode!.overview
          : item.overview,
      year: item.year,
      genres: item.genres,
      runtime: currentEpisode?.runtime ?? item.runtime,
      season: currentEpisode?.season ?? stream.season,
      episode: currentEpisode?.number ?? stream.episode,
      totalSeasons: item.totalSeasons,
      episodeTitle: currentEpisode == null
          ? stream.season != null && stream.episode != null
                ? 'S${stream.season} E${stream.episode}'
                : null
          : 'E${currentEpisode.number} ${currentEpisode.title}',
      episodes: _playerEpisodes(episodes, item),
      episodeStreamResolver: item.kind == MediaKind.tv
          ? (season, episode) async {
              final streams = await ref.read(
                availableStreamsProvider(
                  StreamLookup(item: item, season: season, episode: episode),
                ).future,
              );
              final playableForEpisode = _streamsForEpisode(
                streams,
                season,
                episode,
              );
              final first = _preferredStream(
                playableForEpisode.isEmpty ? streams : playableForEpisode,
                preferred,
              );
              return first == null
                  ? null
                  : PlayerResolvedStream(
                      url: first.url,
                      headers: first.headers,
                      subtitles: _playerSubtitles(first.subtitles),
                      providerName: first.providerName,
                      quality: first.quality,
                      format: first.format,
                      language: first.language,
                      fileSize: first.fileSize,
                      label: first.label,
                      displayTitle: first.displayTitle,
                    );
            }
          : null,
      episodeMetadataResolver: item.kind == MediaKind.tv
          ? (season) async {
              if (item.id <= 0) return const <PlayerEpisodePayload>[];
              final seasonEpisodes = await ref
                  .read(tmdbRepositoryProvider)
                  .seasonEpisodes(item.id, season);
              return _playerEpisodes(seasonEpisodes, item);
            }
          : null,
    ),
  );
}

List<PlayerResolvedStream> _playerFallbackStreams(
  List<StreamSource> streams, {
  required StreamSource selected,
}) {
  final sorted = _playbackSortedStreams(streams);
  return [
    for (final stream in sorted)
      if (stream.url != selected.url) _playerStream(stream),
  ];
}

PlayerResolvedStream _playerStream(StreamSource stream) {
  return PlayerResolvedStream(
    url: stream.url,
    headers: stream.headers,
    subtitles: _playerSubtitles(stream.subtitles),
    providerName: stream.providerName,
    quality: stream.quality,
    format: stream.format,
    language: stream.language,
    fileSize: stream.fileSize,
    label: stream.label,
    displayTitle: stream.displayTitle,
  );
}

List<StreamSource> _playbackSortedStreams(List<StreamSource> streams) {
  final sorted = [...streams];
  sorted.sort((a, b) {
    final rank = _playbackRank(a).compareTo(_playbackRank(b));
    if (rank != 0) return rank;
    return _qualityRank(b).compareTo(_qualityRank(a));
  });
  return sorted;
}

List<StreamSource> _preferredSortedStreams(
  List<StreamSource> streams,
  StreamSource preferred,
) {
  final sorted = _playbackSortedStreams(streams);
  sorted.sort((a, b) {
    final provider = _providerMatchRank(
      b,
      preferred,
    ).compareTo(_providerMatchRank(a, preferred));
    if (provider != 0) return provider;
    final quality = _qualityDistance(
      a,
      preferred,
    ).compareTo(_qualityDistance(b, preferred));
    if (quality != 0) return quality;
    return _playbackRank(a).compareTo(_playbackRank(b));
  });
  return sorted;
}

List<StreamSource> _streamsForEpisode(
  List<StreamSource> streams,
  int season,
  int episode,
) {
  final exact = streams
      .where((stream) => stream.season == season && stream.episode == episode)
      .toList();
  if (exact.isNotEmpty) return exact;
  final episodeOnly = streams
      .where((stream) => stream.season == null && stream.episode == episode)
      .toList();
  return episodeOnly;
}

StreamSource? _preferredStream(
  List<StreamSource> streams,
  StreamSource preferred,
) {
  if (streams.isEmpty) return null;
  return _preferredSortedStreams(streams, preferred).first;
}

int _providerMatchRank(StreamSource stream, StreamSource preferred) {
  final sameProvider =
      (stream.providerName ?? '').toLowerCase() ==
      (preferred.providerName ?? '').toLowerCase();
  if (sameProvider && _qualityRank(stream) == _qualityRank(preferred)) return 3;
  if (sameProvider) return 2;
  if (_qualityRank(stream) == _qualityRank(preferred)) return 1;
  return 0;
}

int _qualityDistance(StreamSource stream, StreamSource preferred) {
  final preferredQuality = _qualityRank(preferred);
  if (preferredQuality == 0) return 0;
  final quality = _qualityRank(stream);
  if (quality == 0) return 9999;
  return (quality - preferredQuality).abs();
}

int _playbackRank(StreamSource stream) {
  final text =
      '${stream.format} ${stream.quality} ${stream.label ?? ''} '
              '${stream.displayTitle ?? ''} ${stream.url}'
          .toLowerCase();
  if (text.contains('hevc') ||
      text.contains('h265') ||
      text.contains('x265') ||
      text.contains('10bit')) {
    return 80;
  }
  if (text.contains('mkv') || text.contains('matroska')) return 70;
  if (text.contains('m3u8') || text.contains('hls')) return 0;
  if (text.contains('mp4')) return 10;
  if (text.contains('x264') || text.contains('h264') || text.contains('avc')) {
    return 12;
  }
  return 30;
}

int _qualityRank(StreamSource stream) {
  final text =
      '${stream.quality} ${stream.label ?? ''} ${stream.displayTitle ?? ''}';
  final match = RegExp(r'(\d{3,4})p?', caseSensitive: false).firstMatch(text);
  if (match != null) return int.tryParse(match.group(1) ?? '') ?? 0;
  if (text.toLowerCase().contains('4k')) return 2160;
  return 0;
}

List<PlayerSubtitlePayload> _playerSubtitles(List<SubtitleTrack> subtitles) {
  return [
    for (var i = 0; i < subtitles.length; i++)
      PlayerSubtitlePayload(
        id: 'subtitle-$i',
        label: subtitles[i].label.isEmpty
            ? (subtitles[i].language.isEmpty
                  ? 'Subtitle ${i + 1}'
                  : subtitles[i].language)
            : subtitles[i].label,
        language: subtitles[i].language,
        url: subtitles[i].url,
      ),
  ];
}

List<PlayerEpisodePayload> _playerEpisodes(
  List<EpisodeItem> episodes,
  MediaItem item,
) {
  return [
    for (final episode in episodes)
      PlayerEpisodePayload(
        season: episode.season,
        episode: episode.number,
        title: episode.title.isEmpty
            ? 'Episode ${episode.number}'
            : episode.title,
        runtime: episode.runtime,
        overview: episode.overview.isEmpty ? item.overview : episode.overview,
        artworkUrl: episode.stillPath == null
            ? _bestArtworkUrl(item)
            : ApiConfig.backdrop(episode.stillPath, size: 'w780'),
      ),
  ];
}

Map<int, List<int>> episodeRangesFromText(String value) {
  if (value.trim().isEmpty) return const {};
  final normalized = value.replaceAll(RegExp(r'[._]+'), ' ');
  final found = <int, Set<int>>{};

  void addRange(int season, int start, int? end) {
    final last = end == null || end < start ? start : end;
    for (var episode = start; episode <= last; episode++) {
      found.putIfAbsent(season, () => <int>{}).add(episode);
    }
  }

  final sxe = RegExp(
    r'\bS(?:eason)?\s*(\d{1,2})\s*E(?:p(?:isode)?)?\s*(\d{1,3})(?:\s*[-–]\s*(?:E)?\s*(\d{1,3}))?',
    caseSensitive: false,
  );
  for (final match in sxe.allMatches(normalized)) {
    final season = int.tryParse(match.group(1) ?? '') ?? 1;
    final start = int.tryParse(match.group(2) ?? '');
    final end = int.tryParse(match.group(3) ?? '');
    if (start != null) addRange(season, start, end);
  }

  final seasonEpisode = RegExp(
    r'\bSeason\s*(\d{1,2}).{0,30}?\bEpisodes?\s*(\d{1,3})(?:\s*[-–]\s*(\d{1,3}))?',
    caseSensitive: false,
  );
  for (final match in seasonEpisode.allMatches(normalized)) {
    final season = int.tryParse(match.group(1) ?? '') ?? 1;
    final start = int.tryParse(match.group(2) ?? '');
    final end = int.tryParse(match.group(3) ?? '');
    if (start != null) addRange(season, start, end);
  }

  return {
    for (final entry in found.entries)
      entry.key: (entry.value.toList()..sort()),
  };
}

String _cleanContainer(String? format, String url) {
  final text = '${format ?? ''} $url'.toLowerCase();
  if (text.contains('m3u8') || text.contains('hls')) return 'HLS';
  if (text.contains('mp4')) return 'MP4';
  if (text.contains('mkv') || text.contains('matroska')) return 'MKV';
  return (format ?? '').trim().toUpperCase();
}

String _cleanQuality(String? quality, String fallback) {
  final raw = (quality ?? '').trim();
  final text = raw.isEmpty || raw.toLowerCase() == 'auto' ? fallback : raw;
  if (text.toLowerCase().contains('4k')) return '2160P';
  final match = RegExp(
    r'\b(4320|3240|2160|1440|1080|720|576|540|480|360|240)p?\b',
    caseSensitive: false,
  ).firstMatch(text);
  if (match != null) return '${match.group(1)}P';
  if (raw.isEmpty || raw.toLowerCase() == 'auto') return 'AUTO';
  return raw.toUpperCase();
}

String providerSeriesLabel(String sourceTitle) {
  final season = RegExp(
    r'\bSeason\s*(\d{1,2})\b|\bS(\d{1,2})\b',
    caseSensitive: false,
  ).firstMatch(sourceTitle);
  final episode = RegExp(
    r'\bEpisode\s*(\d{1,3})(?:\s*[-–]\s*(\d{1,3}))?\b|\bE(\d{1,3})(?:\s*[-–]\s*(\d{1,3}))?\b',
    caseSensitive: false,
  ).firstMatch(sourceTitle);
  final seasonValue = season?.group(1) ?? season?.group(2);
  final episodeStart = episode?.group(1) ?? episode?.group(3);
  final episodeEnd = episode?.group(2) ?? episode?.group(4);
  final parts = <String>[
    if (seasonValue != null) 'Season $seasonValue',
    if (episodeStart != null)
      episodeEnd == null
          ? 'Episode $episodeStart'
          : 'Episodes $episodeStart-$episodeEnd',
  ];
  if (parts.isEmpty) return 'Provider series release';
  return parts.join(' | ');
}

class _InlineStatus extends StatelessWidget {
  const _InlineStatus({required this.icon, required this.message});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 78,
      alignment: Alignment.centerLeft,
      child: Row(
        children: [
          Icon(icon, color: Colors.white54),
          const SizedBox(width: 12),
          Expanded(
            child: Text(message, style: const TextStyle(color: Colors.white70)),
          ),
        ],
      ),
    );
  }
}

String _bestArtworkUrl(MediaItem item) {
  return [
    item.externalBackdropUrl,
    ApiConfig.backdrop(item.backdropPath),
    item.externalPosterUrl,
    ApiConfig.poster(item.posterPath),
  ].whereType<String>().firstWhere((url) => url.isNotEmpty, orElse: () => '');
}

String _runtimeLabel(int minutes) {
  if (minutes < 60) return '$minutes min';
  final hours = minutes ~/ 60;
  final remaining = minutes % 60;
  if (remaining == 0) return '${hours}h';
  return '${hours}h ${remaining}m';
}

String _seasonCountLabel(int? seasons) {
  final count = seasons ?? 1;
  return count == 1 ? '1 Season' : '$count Seasons';
}

class RecommendationStrip extends StatelessWidget {
  const RecommendationStrip({super.key, required this.items});

  final List<MediaItem> items;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        TvLayout.safeHorizontal,
        0,
        0,
        AppSpacing.md,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'More Like This',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: TvLayout.contentRowHeight,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: items.length,
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (context, index) {
                final item = items[index];
                return PosterCard(
                  item: item,
                  onPressed: () =>
                      context.push('/details/${item.kind.name}/${item.id}'),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
