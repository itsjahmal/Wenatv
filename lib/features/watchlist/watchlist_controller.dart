import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../../data/models/media_item.dart';

final watchlistProvider =
    NotifierProvider<WatchlistController, List<MediaItem>>(
      WatchlistController.new,
    );

class WatchlistController extends Notifier<List<MediaItem>> {
  static const _boxName = 'wenatv_user';
  static const _boxKey = 'watchlist';

  @override
  List<MediaItem> build() {
    if (!Hive.isBoxOpen(_boxName)) return const [];
    final raw = Hive.box(_boxName).get(_boxKey);
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((json) => _mediaItemFromJson(json))
        .where((item) => item.id != 0)
        .toList(growable: false);
  }

  bool contains(MediaItem item) {
    return state.any((saved) => _key(saved) == _key(item));
  }

  Future<bool> toggle(MediaItem item) async {
    final key = _key(item);
    final exists = state.any((saved) => _key(saved) == key);
    if (exists) {
      state = state.where((saved) => _key(saved) != key).toList();
    } else {
      state = [item, ...state.where((saved) => _key(saved) != key)];
    }
    await _persist();
    return !exists;
  }

  Future<void> remove(MediaItem item) async {
    final key = _key(item);
    state = state.where((saved) => _key(saved) != key).toList();
    await _persist();
  }

  Future<void> _persist() async {
    if (!Hive.isBoxOpen(_boxName)) return;
    await Hive.box(
      _boxName,
    ).put(_boxKey, [for (final item in state) _mediaItemToJson(item)]);
  }

  String _key(MediaItem item) => '${item.kind.name}:${item.id}';
}

Map<String, dynamic> _mediaItemToJson(MediaItem item) {
  return {
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
}

MediaItem _mediaItemFromJson(Map<dynamic, dynamic> json) {
  final kindName = json['kind']?.toString();
  return MediaItem(
    id: (json['id'] as num?)?.toInt() ?? 0,
    kind: kindName == 'tv' ? MediaKind.tv : MediaKind.movie,
    title: json['title']?.toString() ?? 'Untitled',
    overview: json['overview']?.toString() ?? '',
    posterPath: json['posterPath']?.toString(),
    backdropPath: json['backdropPath']?.toString(),
    rating: (json['rating'] as num?)?.toDouble() ?? 0,
    releaseDate: json['releaseDate']?.toString() ?? '',
    genres: ((json['genres'] as List?) ?? const [])
        .map((genre) => genre.toString())
        .toList(),
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
