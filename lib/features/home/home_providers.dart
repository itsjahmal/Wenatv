import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/media_item.dart';
import '../../data/repositories/tmdb_repository.dart';
import '../providers/provider_js_bridge.dart';
import '../providers/provider_manager_controller.dart';

final homeRowsProvider = FutureProvider<List<HomeRow>>((ref) async {
  return _providerRows(
    ref,
  ).timeout(const Duration(seconds: 28), onTimeout: () => const []);
});

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

Future<List<HomeRow>> _providerRows(Ref ref) async {
  final active = ref.watch(activeProviderProvider);
  if (active == null) return const [];

  final bridge = ref.watch(providerJsBridgeProvider);
  final tmdb = ref.watch(tmdbRepositoryProvider);
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
    final rows = await Future.wait([
      for (final catalog in visibleCatalogs)
        _safeRow(catalog.title, () async {
          final posts = await bridge
              .getPosts(
                sourceUrl: sourceUrl,
                providerValue: providerValue,
                filter: catalog.filter,
              )
              .timeout(const Duration(seconds: 12));
          final enriched = await Future.wait([
            for (final post in posts.take(14))
              _enrichPost(tmdb, post, sourceUrl, providerValue, providerName),
          ]);
          return enriched.nonNulls.toList();
        }),
    ]);
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
