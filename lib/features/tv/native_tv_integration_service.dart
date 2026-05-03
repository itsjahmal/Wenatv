import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/config/api_config.dart';
import '../../data/models/media_item.dart';
import '../continue_watching/continue_watching_controller.dart';
import '../home/home_providers.dart';

class NativeTvIntegrationService {
  NativeTvIntegrationService._();

  static const MethodChannel _channel = MethodChannel('tv.wena.app/native_tv');
  static bool _initialized = false;

  static Future<void> initialize(WidgetRef ref, GoRouter router) async {
    if (_initialized) return;
    _initialized = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'deepLink') {
        await _openDeepLink(call.arguments?.toString(), ref, router);
      }
    });
    final initial = await _safeInvoke<String>('getInitialDeepLink');
    unawaited(_openDeepLink(initial, ref, router));
  }

  static Future<void> publishWatchNext(ContinueWatchingEntry entry) async {
    final map = _watchNextPayload(entry);
    if (map == null) return;
    await _safeInvoke<void>('publishWatchNext', map);
  }

  static Future<void> removeWatchNext(String key) async {
    await _safeInvoke<void>('removeWatchNext', {'id': key});
  }

  static Future<void> publishHomeChannels({
    required List<ContinueWatchingEntry> continueWatching,
    required List<HomeRow> homeRows,
    required List<MediaItem> watchlist,
  }) async {
    final channels = <Map<String, Object?>>[];
    if (continueWatching.isNotEmpty) {
      channels.add({
        'id': 'continue_watching',
        'title': 'Continue Watching',
        'items': continueWatching
            .take(12)
            .map(_continueProgramPayload)
            .toList(),
      });
    }
    final trendingMovies = _rowItems(
      homeRows,
      'trending movies',
      MediaKind.movie,
    );
    if (trendingMovies.isNotEmpty) {
      channels.add(
        _mediaChannel('trending_movies', 'Trending Movies', trendingMovies),
      );
    }
    final trendingSeries = _rowItems(homeRows, 'trending series', MediaKind.tv);
    if (trendingSeries.isNotEmpty) {
      channels.add(
        _mediaChannel('trending_series', 'Trending Series', trendingSeries),
      );
    }
    if (watchlist.isNotEmpty) {
      channels.add(_mediaChannel('watchlist', 'Watchlist', watchlist));
    }
    if (channels.isEmpty) return;
    await _safeInvoke<void>('publishChannels', channels);
  }

  static Map<String, Object?>? _watchNextPayload(ContinueWatchingEntry entry) {
    if (entry.mediaId <= 0 || entry.title.isEmpty) return null;
    return {
      ..._continueProgramPayload(entry),
      'contentId': entry.key,
      'durationMs': entry.duration.inMilliseconds,
      'positionMs': entry.position.inMilliseconds,
    };
  }

  static Map<String, Object?> _continueProgramPayload(
    ContinueWatchingEntry entry,
  ) {
    return {
      'id': entry.key,
      'title': _continueTitle(entry),
      'description': entry.overview ?? '',
      'kind': entry.kind,
      'posterUrl': entry.artworkUrl ?? '',
      'backdropUrl': entry.artworkUrl ?? '',
      'deepLink': 'wenatv://continue/${Uri.encodeComponent(entry.key)}',
    };
  }

  static Map<String, Object?> _mediaProgramPayload(MediaItem item) {
    final posterUrl =
        item.externalPosterUrl ?? ApiConfig.poster(item.posterPath);
    final backdropUrl =
        item.externalBackdropUrl ?? ApiConfig.backdrop(item.backdropPath);
    return {
      'id': '${item.kind.name}:${item.id}',
      'title': item.title,
      'description': item.overview,
      'kind': item.kind.name,
      'posterUrl': posterUrl,
      'backdropUrl': backdropUrl,
      'deepLink': 'wenatv://details/${item.kind.name}/${item.id}',
    };
  }

  static Map<String, Object?> _mediaChannel(
    String id,
    String title,
    List<MediaItem> items,
  ) {
    return {
      'id': id,
      'title': title,
      'items': items.take(20).map(_mediaProgramPayload).toList(),
    };
  }

  static List<MediaItem> _rowItems(
    List<HomeRow> rows,
    String titleNeedle,
    MediaKind kind,
  ) {
    for (final row in rows) {
      final title = row.title.toLowerCase();
      if (title.contains(titleNeedle)) {
        return row.items.where((item) => item.kind == kind).toList();
      }
    }
    return const [];
  }

  static String _continueTitle(ContinueWatchingEntry entry) {
    if (!entry.isSeries) return entry.title;
    final parts = [
      entry.title,
      if (entry.season != null && entry.episode != null)
        'S${entry.season} E${entry.episode}',
      if ((entry.episodeTitle ?? '').isNotEmpty) entry.episodeTitle!,
    ];
    return parts.join(' - ');
  }

  static Future<void> _openDeepLink(
    String? link,
    WidgetRef ref,
    GoRouter router,
  ) async {
    if (link == null || link.isEmpty) return;
    final uri = Uri.tryParse(link);
    if (uri == null || uri.scheme != 'wenatv') return;
    if (uri.host == 'details' && uri.pathSegments.length >= 2) {
      final kind = uri.pathSegments[0] == 'tv' ? 'tv' : 'movie';
      final id = int.tryParse(uri.pathSegments[1]);
      if (id != null) router.go('/details/$kind/$id');
      return;
    }
    if (uri.host == 'continue' && uri.pathSegments.isNotEmpty) {
      final key = Uri.decodeComponent(uri.pathSegments.first);
      final entries = ref.read(continueWatchingProvider);
      for (final entry in entries) {
        if (entry.key == key) {
          router.go('/player', extra: entry.toPlayerPayload());
          return;
        }
      }
      router.go('/');
    }
  }

  static Future<T?> _safeInvoke<T>(String method, [Object? arguments]) async {
    try {
      return await _channel.invokeMethod<T>(method, arguments);
    } catch (_) {
      return null;
    }
  }
}
