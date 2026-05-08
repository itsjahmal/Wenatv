import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../../data/models/media_item.dart';
import '../../data/repositories/tmdb_repository.dart';
import '../providers/provider_js_bridge.dart';
import '../providers/provider_manager_controller.dart';

final homeRefreshingProvider = NotifierProvider<HomeRefreshingController, bool>(
  HomeRefreshingController.new,
);

class HomeRefreshingController extends Notifier<bool> {
  @override
  bool build() => false;

  void setRefreshing(bool value) => state = value;
}

final homeRowsProvider =
    NotifierProvider<HomeRowsController, AsyncValue<List<HomeRow>>>(
      HomeRowsController.new,
    );

class HomeRowsController extends Notifier<AsyncValue<List<HomeRow>>> {
  static const _boxKey = 'home_content_cache';
  static const _minRefreshInterval = Duration(minutes: 5);
  String? _activeCacheKey;
  DateTime? _lastRefreshed;

  @override
  AsyncValue<List<HomeRow>> build() {
    final active = ref.watch(activeProviderProvider);
    _activeCacheKey = _cacheKey(active);
    final cached = _loadCachedRows(_activeCacheKey);
    unawaited(Future<void>.microtask(refresh));
    return cached == null ? const AsyncLoading() : AsyncData(cached);
  }

  Future<void> refresh() async {
    final active = ref.read(activeProviderProvider);
    final cacheKey = _cacheKey(active);
    if (active == null || cacheKey == null) {
      state = const AsyncData([]);
      return;
    }
    // Guard: skip if a refresh ran less than 5 minutes ago to avoid
    // redundant fetches every time the user navigates back to home.
    final now = DateTime.now();
    if (_lastRefreshed != null &&
        now.difference(_lastRefreshed!) < _minRefreshInterval) {
      return;
    }

    final hadData = state.asData?.value.isNotEmpty == true;
    if (!hadData) state = const AsyncLoading();
    ref.read(homeRefreshingProvider.notifier).setRefreshing(true);
    try {
      final rows = await _providerRowsForActive(
        active: active,
        bridge: ref.read(providerJsBridgeProvider),
        tmdb: ref.read(tmdbRepositoryProvider),
      ).timeout(const Duration(seconds: 28), onTimeout: () => const []);
      if (_activeCacheKey != cacheKey) return;
      final cleanRows = _dedupeRows(rows);
      if (cleanRows.isNotEmpty) {
        _lastRefreshed = DateTime.now();
        state = AsyncData(cleanRows);
        await _saveCachedRows(cacheKey, cleanRows);
      } else if (!hadData) {
        state = const AsyncData([]);
      }
    } catch (error, stack) {
      if (!hadData) state = AsyncError(error, stack);
    } finally {
      ref.read(homeRefreshingProvider.notifier).setRefreshing(false);
    }
  }
}

final homeProviderStatusProvider = Provider<HomeProviderStatus>((ref) {
  final active = ref.watch(activeProviderProvider);
  if (active == null) {
    final installed = ref
        .read(providerManagerProvider.notifier)
        .installedProviderSelections();
    return HomeProviderStatus(
      title: installed.isEmpty
          ? 'No default provider selected'
          : 'Provider not ready',
      message: installed.isEmpty
          ? 'Install a catalog provider in Settings, then select it as default.'
          : 'Select one installed provider as default in Settings.',
    );
  }
  return HomeProviderStatus(
    title: 'No catalog items from ${active.displayName}',
    message:
        'WenaTV is using ${active.displayName} as the active provider, but it did not return playable catalog posts for Home. Try Refresh in Provider Manager or set a different default provider.',
  );
});

Future<List<HomeRow>> _providerRowsForActive({
  required ActiveProviderSelection active,
  required ProviderJsBridge bridge,
  required TmdbRepository tmdb,
}) async {
  return _rowsForProvider(
    bridge: bridge,
    tmdb: tmdb,
    sourceUrl: active.sourceUrl,
    providerValue: active.value,
    providerName: active.displayName,
  );
}

Future<List<HomeRow>> _rowsForProvider({
  required ProviderJsBridge bridge,
  required TmdbRepository tmdb,
  required String sourceUrl,
  required String providerValue,
  required String providerName,
}) async {
  try {
    final catalogs = await bridge
        .getCatalog(sourceUrl: sourceUrl, providerValue: providerValue)
        .timeout(const Duration(seconds: 8));
    final visibleCatalogs = _homeCatalogs(catalogs);

    // Fix 2: Process catalogs in batches of 4 instead of all-at-once.
    // Firing 10+ simultaneous HTTP fetches on Android TV’s weaker network
    // stack caused hangs. Batching limits concurrency while keeping total
    // load time acceptable.
    final rows = <HomeRow?>[];
    for (final batch in _batched(visibleCatalogs, 4)) {
      final batchResults = await Future.wait([
        for (final catalog in batch)
          _safeRow(catalog.title, () async {
            final posts = await bridge
                .getPosts(
                  sourceUrl: sourceUrl,
                  providerValue: providerValue,
                  filter: catalog.filter,
                )
                .timeout(const Duration(seconds: 12));
            // Cap enrichment at 8 posts (was 14) to halve TMDB calls.
            final enriched = await Future.wait([
              for (final post in posts.take(8))
                _enrichPost(tmdb, post, sourceUrl, providerValue, providerName),
            ]);
            return enriched.nonNulls.toList();
          }),
      ]);
      rows.addAll(batchResults);
    }

    final providerRows = rows.nonNulls
        .where((row) => row.items.isNotEmpty)
        .fold<List<HomeRow>>([], (unique, row) {
          final seenTitles = unique.expand((item) => item.items).map((item) {
            return '${item.kind.name}:${item.title.toLowerCase()}';
          }).toSet();
          final items = row.items.where((item) {
            return !seenTitles.contains(
              '${item.kind.name}:${item.title.toLowerCase()}',
            );
          }).toList();
          if (items.isNotEmpty) unique.add(HomeRow(row.title, items));
          return unique;
        })
        .toList();
    final tmdbRows = await _tmdbDiscoveryRows(
      tmdb,
      sourceUrl: sourceUrl,
      providerValue: providerValue,
      providerName: providerName,
      existing: providerRows,
    );
    return _dedupeRows([...providerRows, ...tmdbRows]);
  } catch (_) {
    return _tmdbDiscoveryRows(
      tmdb,
      sourceUrl: sourceUrl,
      providerValue: providerValue,
      providerName: providerName,
      existing: const [],
    );
  }
}

/// Splits [items] into successive sublists of at most [size] elements.
List<List<T>> _batched<T>(List<T> items, int size) {
  final result = <List<T>>[];
  for (var i = 0; i < items.length; i += size) {
    result.add(items.sublist(i, (i + size).clamp(0, items.length)));
  }
  return result;
}

Future<List<HomeRow>> _tmdbDiscoveryRows(
  TmdbRepository tmdb, {
  required String sourceUrl,
  required String providerValue,
  required String providerName,
  required List<HomeRow> existing,
}) async {
  final rows = await Future.wait([
    _safeRow('TMDB Trending Movies', () async {
      final items = await tmdb.trending(MediaKind.movie);
      return _tagTmdbItems(items, sourceUrl, providerValue, providerName);
    }),
    _safeRow('TMDB Trending Series', () async {
      final items = await tmdb.trending(MediaKind.tv);
      return _tagTmdbItems(items, sourceUrl, providerValue, providerName);
    }),
    _safeRow('Popular Movies', () async {
      final items = await tmdb.popular(MediaKind.movie);
      return _tagTmdbItems(items, sourceUrl, providerValue, providerName);
    }),
    _safeRow('Popular Series', () async {
      final items = await tmdb.popular(MediaKind.tv);
      return _tagTmdbItems(items, sourceUrl, providerValue, providerName);
    }),
    _safeRow('Top Rated Movies', () async {
      final items = await tmdb.topRated(MediaKind.movie);
      return _tagTmdbItems(items, sourceUrl, providerValue, providerName);
    }),
  ]);
  final existingKeys = existing
      .expand((row) => row.items)
      .map((item) => '${item.kind.name}:${item.title.toLowerCase()}')
      .toSet();
  return rows.nonNulls
      .map((row) {
        final items = row.items.where((item) {
          return !existingKeys.contains(
            '${item.kind.name}:${item.title.toLowerCase()}',
          );
        }).toList();
        return HomeRow(row.title, items);
      })
      .where((row) => row.items.isNotEmpty)
      .toList();
}

List<MediaItem> _tagTmdbItems(
  List<MediaItem> items,
  String sourceUrl,
  String providerValue,
  String providerName,
) {
  return [
    for (final item in items.take(14))
      item.copyWith(
        sourceUrl: sourceUrl,
        sourceProvider: providerValue,
        sourceProviderName: providerName,
        sourceLink: null,
        sourceTitle: item.title,
      ),
  ];
}

List<HomeRow> _dedupeRows(List<HomeRow> rows) {
  final seen = <String>{};
  final result = <HomeRow>[];
  for (final row in rows) {
    final items = <MediaItem>[];
    for (final item in row.items) {
      final key = '${item.kind.name}:${item.title.toLowerCase()}';
      if (seen.add(key)) items.add(item);
    }
    if (items.isNotEmpty) result.add(HomeRow(row.title, items));
  }
  return result;
}

List<ProviderCatalog> _homeCatalogs(List<ProviderCatalog> catalogs) {
  final byTitle = <String, ProviderCatalog>{};
  for (final catalog in catalogs) {
    final title = _cleanRowTitle(catalog.title);
    if (title.isEmpty) continue;
    byTitle.putIfAbsent(
      title.toLowerCase(),
      () => ProviderCatalog(title: title, filter: catalog.filter),
    );
  }
  const fallback = [
    ProviderCatalog(title: 'New', filter: ''),
    ProviderCatalog(title: 'Movies', filter: 'movies'),
    ProviderCatalog(title: 'TV Shows', filter: 'series'),
    ProviderCatalog(title: 'Netflix', filter: 'category/web-series/netflix'),
    ProviderCatalog(
      title: 'Amazon Prime',
      filter: 'category/web-series/amazon-prime-video',
    ),
    ProviderCatalog(title: '4K Movies', filter: 'movies-by-quality/2160p'),
    ProviderCatalog(title: 'Hindi Dubbed', filter: 'category/hindi-dubbed'),
    ProviderCatalog(title: 'Anime', filter: 'category/anime'),
  ];
  for (final catalog in fallback) {
    byTitle.putIfAbsent(catalog.title.toLowerCase(), () => catalog);
  }
  return byTitle.values.take(10).toList();
}

String _cleanRowTitle(String value) {
  return value
      .replaceAll(RegExp(r'[-_]+'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

Future<MediaItem?> _enrichPost(
  TmdbRepository tmdb,
  ProviderPost post,
  String sourceUrl,
  String providerValue,
  String providerName,
) async {
  final cleanTitle = _cleanProviderTitle(post.title);
  final base = await tmdb
      .bestMatch(cleanTitle)
      .timeout(const Duration(milliseconds: 900), onTimeout: () => null);
  if (base != null) {
    return base.copyWith(
      kind: base.kind,
      sourceProvider: providerValue,
      sourceProviderName: providerName,
      sourceUrl: sourceUrl,
      sourceLink: post.link,
      sourceTitle: post.title,
      externalPosterUrl: base.posterPath == null ? post.image : null,
      externalBackdropUrl: base.backdropPath == null ? post.image : null,
    );
  }
  return MediaItem(
    id: post.link.hashCode.abs(),
    kind: _providerKind(post.title, MediaKind.movie),
    title: cleanTitle.isEmpty ? post.title : cleanTitle,
    overview: '',
    posterPath: null,
    backdropPath: null,
    rating: 0,
    releaseDate: '',
    externalPosterUrl: post.image,
    externalBackdropUrl: post.image,
    sourceUrl: sourceUrl,
    sourceProvider: providerValue,
    sourceProviderName: providerName,
    sourceLink: post.link,
    sourceTitle: post.title,
  );
}

String _cleanProviderTitle(String value) {
  var cleaned = value
      .replaceFirst(RegExp(r'^Download\s*', caseSensitive: false), '')
      .replaceAll(RegExp(r'\[[^\]]*\]|\([^)]*\)|\{[^}]*\}'), ' ')
      .replaceAll(
        RegExp(
          r'\b(Prime Video|Amazon Prime Video|Amazon Prime|Netflix|NetFlix-Series|Disney\+|Hotstar|HBO Max|Apple TV|Hulu)\b.*$',
          caseSensitive: false,
        ),
        ' ',
      )
      .replaceAll(
        RegExp(
          r'\b(Dual Audio|Multi Audio|Hindi Dubbed|English Full Movie|Full Movie|Series|Anime Series)\b.*$',
          caseSensitive: false,
        ),
        ' ',
      )
      .replaceAll(
        RegExp(
          r'\b(480p|720p|1080p|2160p|4k|uhd|sdr|hdr|hevc|x264|x265|10bit|web[- ]?dl|webrip|hdrip|bluray|brrip|dvdrip|multi audio|dual audio|hindi|english|proper|repack|esub|nf|amzn)\b',
          caseSensitive: false,
        ),
        ' ',
      )
      .replaceAll(
        RegExp(
          r'\bS\d{1,2}\s*E\d{1,3}(?:\s*-\s*\d{1,3})?\b',
          caseSensitive: false,
        ),
        ' ',
      )
      .replaceAll(RegExp(r'\bSeason\s*\d+\b', caseSensitive: false), ' ')
      .replaceAll(RegExp(r'\bAdded\b', caseSensitive: false), ' ')
      .replaceAll(RegExp(r'[:\-_|–—]+'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  cleaned = cleaned.replaceAll(RegExp(r'\s+\d{4}$'), '').trim();
  return cleaned;
}

MediaKind _providerKind(String title, MediaKind fallback) {
  return RegExp(
        r'\b(S\d{1,2}|Season\s*\d+|Episode\s*\d+)\b',
        caseSensitive: false,
      ).hasMatch(title)
      ? MediaKind.tv
      : fallback;
}

Future<HomeRow?> _safeRow(
  String title,
  Future<List<MediaItem>> Function() loader,
) async {
  try {
    final items = await loader().timeout(const Duration(seconds: 12));
    return HomeRow(title, items);
  } catch (_) {
    return null;
  }
}

class HomeRow {
  const HomeRow(this.title, this.items);
  final String title;
  final List<MediaItem> items;
}

class HomeProviderStatus {
  const HomeProviderStatus({required this.title, required this.message});

  final String title;
  final String message;
}

String? _cacheKey(ActiveProviderSelection? active) {
  if (active == null) return null;
  return '${active.sourceUrl}::${active.value}';
}

List<HomeRow>? _loadCachedRows(String? key) {
  if (key == null || !Hive.isBoxOpen('wenatv_cache')) return null;
  try {
    final raw = Hive.box('wenatv_cache').get(_homeCacheKey(key));
    if (raw is! Map) return null;
    // Fix 7: Enforce a 15-minute TTL on cached home rows. Without this, stale
    // data from hours/days ago was served indefinitely while the app silently
    // re-fetched in the background, leading to confusing double-redraws.
    const cacheTtl = Duration(minutes: 15);
    final timestampRaw = raw['timestamp']?.toString();
    if (timestampRaw != null) {
      final timestamp = DateTime.tryParse(timestampRaw);
      if (timestamp != null &&
          DateTime.now().difference(timestamp) > cacheTtl) {
        return null; // Expired — force a fresh network fetch
      }
    }
    final rows = raw['rows'];
    if (rows is! List) return null;
    final parsed = [
      for (final row in rows)
        if (row is Map) _homeRowFromJson(row),
    ].nonNulls.toList();
    return parsed.isEmpty ? null : _dedupeRows(parsed);
  } catch (_) {
    return null;
  }
}

Future<void> _saveCachedRows(String key, List<HomeRow> rows) async {
  if (!Hive.isBoxOpen('wenatv_cache') || rows.isEmpty) return;
  await Hive.box('wenatv_cache').put(_homeCacheKey(key), {
    'timestamp': DateTime.now().toIso8601String(),
    'rows': [for (final row in rows) _homeRowToJson(row)],
  });
}

String _homeCacheKey(String key) => '${HomeRowsController._boxKey}:$key';

Map<String, dynamic> _homeRowToJson(HomeRow row) => {
  'title': row.title,
  'items': [for (final item in row.items) _mediaItemToJson(item)],
};

HomeRow? _homeRowFromJson(Map<dynamic, dynamic> json) {
  final title = json['title']?.toString() ?? '';
  final rawItems = json['items'];
  if (title.isEmpty || rawItems is! List) return null;
  final items = [
    for (final item in rawItems)
      if (item is Map) _mediaItemFromJson(item),
  ].nonNulls.toList();
  return items.isEmpty ? null : HomeRow(title, items);
}

Map<String, dynamic> _mediaItemToJson(MediaItem item) => {
  'id': item.id,
  'kind': item.kind.name,
  'title': item.title,
  'overview': item.overview,
  'posterPath': item.posterPath,
  'backdropPath': item.backdropPath,
  'rating': item.rating,
  'releaseDate': item.releaseDate,
  'genres': item.genres,
  'runtime': item.runtime,
  'totalSeasons': item.totalSeasons,
  'externalPosterUrl': item.externalPosterUrl,
  'externalBackdropUrl': item.externalBackdropUrl,
  'sourceUrl': item.sourceUrl,
  'sourceProvider': item.sourceProvider,
  'sourceProviderName': item.sourceProviderName,
  'sourceLink': item.sourceLink,
  'sourceTitle': item.sourceTitle,
};

MediaItem? _mediaItemFromJson(Map<dynamic, dynamic> json) {
  final title = json['title']?.toString() ?? '';
  if (title.isEmpty) return null;
  final kind = json['kind']?.toString() == 'tv'
      ? MediaKind.tv
      : MediaKind.movie;
  return MediaItem(
    id: (json['id'] as num?)?.toInt() ?? 0,
    kind: kind,
    title: title,
    overview: json['overview']?.toString() ?? '',
    posterPath: json['posterPath']?.toString(),
    backdropPath: json['backdropPath']?.toString(),
    rating: (json['rating'] as num?)?.toDouble() ?? 0,
    releaseDate: json['releaseDate']?.toString() ?? '',
    genres: [
      for (final genre in (json['genres'] as List?) ?? const [])
        genre.toString(),
    ],
    runtime: (json['runtime'] as num?)?.toInt(),
    totalSeasons: (json['totalSeasons'] as num?)?.toInt(),
    externalPosterUrl: json['externalPosterUrl']?.toString(),
    externalBackdropUrl: json['externalBackdropUrl']?.toString(),
    sourceUrl: json['sourceUrl']?.toString(),
    sourceProvider: json['sourceProvider']?.toString(),
    sourceProviderName: json['sourceProviderName']?.toString(),
    sourceLink: json['sourceLink']?.toString(),
    sourceTitle: json['sourceTitle']?.toString(),
  );
}
