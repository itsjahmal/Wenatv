import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../../core/network/dio_client.dart';
import '../models/media_item.dart';

final tmdbRepositoryProvider = Provider<TmdbRepository>((ref) {
  return TmdbRepository(ref.watch(dioProvider), Hive.box('wenatv_cache'));
});

class TmdbRepository {
  TmdbRepository(this._dio, this._cache);

  final Dio _dio;
  final Box _cache;

  // ── Cache TTL helpers ────────────────────────────────────────────────────
  static const _listTtl = Duration(hours: 6);
  static const _detailTtl = Duration(hours: 24);

  /// Returns [value] only when the associated timestamp is fresher than [ttl].
  /// The cache entry is expected to be a Map with keys 'ts' (ISO-8601 String)
  /// and 'data' (the actual payload). Legacy bare entries (List/Map without 'ts')
  /// are treated as expired so they get refreshed on next launch.
  Object? _fresh(String key, Duration ttl) {
    final raw = _cache.get(key);
    if (raw is Map && raw.containsKey('ts')) {
      final ts = DateTime.tryParse(raw['ts']?.toString() ?? '');
      if (ts != null && DateTime.now().difference(ts) < ttl) {
        return raw['data'];
      }
      return null; // Expired
    }
    return null; // Legacy bare entry — treat as expired
  }

  Future<void> _put(String key, Object data) =>
      _cache.put(key, {'ts': DateTime.now().toIso8601String(), 'data': data});

  Future<List<MediaItem>> trending(MediaKind kind) {
    final path = kind == MediaKind.movie
        ? '/trending/movie/week'
        : '/trending/tv/week';
    return _list(path, kind, 'trending_${kind.name}');
  }

  Future<List<MediaItem>> popular(MediaKind kind) {
    final path = kind == MediaKind.movie ? '/movie/popular' : '/tv/popular';
    return _list(path, kind, 'popular_${kind.name}');
  }

  Future<List<MediaItem>> topRated(MediaKind kind) {
    final path = kind == MediaKind.movie ? '/movie/top_rated' : '/tv/top_rated';
    return _list(path, kind, 'top_${kind.name}');
  }

  Future<List<MediaItem>> upcoming() =>
      _list('/movie/upcoming', MediaKind.movie, 'upcoming');

  Future<List<MediaItem>> nowPlaying() =>
      _list('/movie/now_playing', MediaKind.movie, 'now_playing');

  Future<List<MediaItem>> genre(int genreId, String label, MediaKind kind) {
    return _list(
      '/discover/${kind == MediaKind.movie ? 'movie' : 'tv'}',
      kind,
      'genre_${kind.name}_$genreId',
      query: {'with_genres': genreId},
    );
  }

  Future<List<MediaItem>> search(String query) {
    if (query.trim().isEmpty) return Future.value([]);
    return _list(
      '/search/multi',
      MediaKind.movie,
      'search_$query',
      query: {'query': query, 'include_adult': false},
    );
  }

  Future<MediaItem?> bestMatch(String title) async {
    final cleaned = title
        .replaceAll(RegExp(r'\([^)]*\)|\[[^\]]*\]'), ' ')
        .replaceAll(
          RegExp(
            r'\b(480p|720p|1080p|2160p|4k|uhd|hdrip|webrip|web-dl|bluray|hindi|english|dual audio)\b',
            caseSensitive: false,
          ),
          ' ',
        )
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (cleaned.isEmpty) return null;
    final results = await search(cleaned);
    return results.isEmpty ? null : results.first;
  }

  Future<MediaItem> details(int id, MediaKind kind) async {
    final path = kind == MediaKind.movie ? '/movie/$id' : '/tv/$id';
    final key = 'details_${kind.name}_$id';
    final cached = _fresh(key, _detailTtl);
    if (cached is Map) {
      return MediaItem.fromJson(Map<String, dynamic>.from(cached), kind);
    }
    final response = await _dio.get<Map<String, dynamic>>(path);
    final data = response.data ?? {};
    await _put(key, data);
    return MediaItem.fromJson(data, kind);
  }

  Future<List<MediaItem>> recommendations(int id, MediaKind kind) {
    final path = kind == MediaKind.movie
        ? '/movie/$id/recommendations'
        : '/tv/$id/recommendations';
    return _list(path, kind, 'recs_${kind.name}_$id');
  }

  Future<List<CastMember>> cast(int id, MediaKind kind) async {
    final key = 'cast_${kind.name}_$id';
    final cached = _fresh(key, _detailTtl);
    if (cached is List && cached.isNotEmpty) {
      return cached
          .map((item) => CastMember.fromJson(Map<String, dynamic>.from(item)))
          .toList();
    }
    final path = kind == MediaKind.movie
        ? '/movie/$id/credits'
        : '/tv/$id/credits';
    final response = await _dio.get<Map<String, dynamic>>(path);
    final cast = ((response.data?['cast'] as List?) ?? const [])
        .cast<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .where((item) => (item['name'] ?? '').toString().isNotEmpty)
        .take(12)
        .toList();
    await _put(key, cast);
    return cast.map(CastMember.fromJson).toList();
  }

  Future<List<EpisodeItem>> seasonEpisodes(int tvId, int season) async {
    final key = 'season_${tvId}_$season';
    final cached = _cache.get(key);
    if (cached is List) {
      return cached
          .map(
            (item) =>
                EpisodeItem.fromJson(Map<String, dynamic>.from(item), season),
          )
          .toList();
    }
    final response = await _dio.get<Map<String, dynamic>>(
      '/tv/$tvId/season/$season',
    );
    final episodes = ((response.data?['episodes'] as List?) ?? const [])
        .cast<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
    await _cache.put(key, episodes);
    return episodes.map((item) => EpisodeItem.fromJson(item, season)).toList();
  }

  Future<Uri?> trailerUri(int id, MediaKind kind) async {
    final key = 'trailer_${kind.name}_$id';
    final cached = _fresh(key, _detailTtl);
    if (cached is String && cached.isNotEmpty) return Uri.tryParse(cached);
    final path = kind == MediaKind.movie
        ? '/movie/$id/videos'
        : '/tv/$id/videos';
    final response = await _dio.get<Map<String, dynamic>>(path);
    final results = ((response.data?['results'] as List?) ?? const [])
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
    final trailer = _bestTrailer(results);
    final keyValue = trailer['key']?.toString();
    if (keyValue == null || keyValue.isEmpty) return null;
    final uri = Uri.parse('https://www.youtube.com/watch?v=$keyValue');
    await _put(key, uri.toString());
    return uri;
  }

  Future<String?> trailerKey(int id, MediaKind kind) async {
    final uri = await trailerUri(id, kind);
    if (uri == null) return null;
    if (uri.host.contains('youtu.be')) {
      final videoId = uri.pathSegments.isEmpty ? null : uri.pathSegments.first;
      return videoId == null || videoId.isEmpty ? null : videoId;
    }
    final videoId = uri.queryParameters['v'];
    if (videoId != null && videoId.isNotEmpty) return videoId;
    final embedIndex = uri.pathSegments.indexOf('embed');
    if (embedIndex >= 0 && uri.pathSegments.length > embedIndex + 1) {
      return uri.pathSegments[embedIndex + 1];
    }
    return null;
  }

  Future<List<MediaItem>> _list(
    String path,
    MediaKind kind,
    String cacheKey, {
    Map<String, dynamic>? query,
  }) async {
    final cached = _fresh(cacheKey, _listTtl);
    if (cached is List && cached.isNotEmpty) {
      return cached
          .map(
            (item) => MediaItem.fromJson(Map<String, dynamic>.from(item), kind),
          )
          .where((item) => item.posterPath != null || item.backdropPath != null)
          .toList();
    }
    final response = await _dio.get<Map<String, dynamic>>(
      path,
      queryParameters: query,
    );
    final results = ((response.data?['results'] as List?) ?? const [])
        .cast<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .where((item) => item['media_type'] != 'person')
        .toList();
    await _put(cacheKey, results);
    return results
        .map((item) => MediaItem.fromJson(item, kind))
        .where((item) => item.posterPath != null || item.backdropPath != null)
        .toList();
  }
}

Map<String, dynamic> _bestTrailer(List<Map<String, dynamic>> results) {
  final youtube = results
      .where((item) => item['site']?.toString().toLowerCase() == 'youtube')
      .toList();
  if (youtube.isEmpty) return const {};
  int score(Map<String, dynamic> item) {
    final type = item['type']?.toString().toLowerCase() ?? '';
    final name = item['name']?.toString().toLowerCase() ?? '';
    final official = item['official'] == true || name.contains('official');
    if (official && type == 'trailer') return 0;
    if (type == 'trailer') return 1;
    if (type == 'teaser') return 2;
    return 3;
  }

  youtube.sort((a, b) => score(a).compareTo(score(b)));
  return youtube.first;
}
