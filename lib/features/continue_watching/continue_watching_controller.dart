import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../player/player_screen.dart';

final continueWatchingProvider =
    NotifierProvider<ContinueWatchingController, List<ContinueWatchingEntry>>(
      ContinueWatchingController.new,
    );

class ContinueWatchingEntry {
  const ContinueWatchingEntry({
    required this.key,
    required this.mediaId,
    required this.kind,
    required this.title,
    required this.position,
    required this.duration,
    required this.lastWatched,
    this.artworkUrl,
    this.overview,
    this.year,
    this.season,
    this.episode,
    this.episodeTitle,
    this.streamUrl,
    this.headers = const {},
    this.providerName,
    this.quality,
    this.format,
  });

  final String key;
  final int mediaId;
  final String kind;
  final String title;
  final Duration position;
  final Duration duration;
  final DateTime lastWatched;
  final String? artworkUrl;
  final String? overview;
  final String? year;
  final int? season;
  final int? episode;
  final String? episodeTitle;
  final String? streamUrl;
  final Map<String, String> headers;
  final String? providerName;
  final String? quality;
  final String? format;

  bool get isSeries => kind == 'tv';

  double get progress {
    if (duration.inMilliseconds <= 0) return 0;
    return (position.inMilliseconds / duration.inMilliseconds).clamp(0, 1);
  }

  PlayerPayload toPlayerPayload() {
    final stream = streamUrl == null || streamUrl!.isEmpty
        ? null
        : PlayerResolvedStream(
            url: streamUrl!,
            headers: headers,
            providerName: providerName,
            quality: quality,
            format: format,
          );
    return PlayerPayload(
      mediaId: mediaId,
      kind: kind,
      title: title,
      episodeTitle: episodeTitle,
      streamUrl: streamUrl,
      headers: headers,
      isSeries: isSeries,
      artworkUrl: artworkUrl,
      overview: overview,
      year: year,
      season: season,
      episode: episode,
      startPosition: position,
      currentStream: stream,
      fallbackStreams: stream == null ? const [] : const [],
    );
  }

  Map<String, dynamic> toJson() => {
    'key': key,
    'mediaId': mediaId,
    'kind': kind,
    'title': title,
    'positionMs': position.inMilliseconds,
    'durationMs': duration.inMilliseconds,
    'lastWatched': lastWatched.toIso8601String(),
    'artworkUrl': artworkUrl,
    'overview': overview,
    'year': year,
    'season': season,
    'episode': episode,
    'episodeTitle': episodeTitle,
    'streamUrl': streamUrl,
    'headers': headers,
    'providerName': providerName,
    'quality': quality,
    'format': format,
  };

  static ContinueWatchingEntry? fromJson(Map<dynamic, dynamic> json) {
    final title = json['title']?.toString() ?? '';
    final key = json['key']?.toString() ?? '';
    if (title.isEmpty || key.isEmpty) return null;
    final rawHeaders = json['headers'];
    final headers = <String, String>{};
    if (rawHeaders is Map) {
      for (final entry in rawHeaders.entries) {
        headers[entry.key.toString()] = entry.value.toString();
      }
    }
    return ContinueWatchingEntry(
      key: key,
      mediaId: (json['mediaId'] as num?)?.toInt() ?? 0,
      kind: json['kind']?.toString() ?? 'movie',
      title: title,
      position: Duration(
        milliseconds: (json['positionMs'] as num?)?.toInt() ?? 0,
      ),
      duration: Duration(
        milliseconds: (json['durationMs'] as num?)?.toInt() ?? 0,
      ),
      lastWatched:
          DateTime.tryParse(json['lastWatched']?.toString() ?? '') ??
          DateTime.now(),
      artworkUrl: json['artworkUrl']?.toString(),
      overview: json['overview']?.toString(),
      year: json['year']?.toString(),
      season: (json['season'] as num?)?.toInt(),
      episode: (json['episode'] as num?)?.toInt(),
      episodeTitle: json['episodeTitle']?.toString(),
      streamUrl: json['streamUrl']?.toString(),
      headers: headers,
      providerName: json['providerName']?.toString(),
      quality: json['quality']?.toString(),
      format: json['format']?.toString(),
    );
  }
}

class ContinueWatchingController extends Notifier<List<ContinueWatchingEntry>> {
  static const _boxKey = 'continue_watching';

  @override
  List<ContinueWatchingEntry> build() => _load();

  Future<void> save(ContinueWatchingEntry entry) async {
    if (entry.position < const Duration(seconds: 15) ||
        entry.duration < const Duration(minutes: 1) ||
        entry.progress >= .90) {
      await remove(entry.key);
      return;
    }
    final entries = [
      entry,
      for (final item in state)
        if (item.key != entry.key) item,
    ]..sort((a, b) => b.lastWatched.compareTo(a.lastWatched));
    state = entries.take(20).toList();
    await _save();
  }

  Future<void> remove(String key) async {
    final next = [
      for (final item in state)
        if (item.key != key) item,
    ];
    if (next.length == state.length) return;
    state = next;
    await _save();
  }

  List<ContinueWatchingEntry> _load() {
    if (!Hive.isBoxOpen('wenatv_user')) return const [];
    final raw = Hive.box('wenatv_user').get(_boxKey);
    if (raw is! List) return const [];
    final entries = [
      for (final item in raw)
        if (item is Map) ContinueWatchingEntry.fromJson(item),
    ].nonNulls.toList()..sort((a, b) => b.lastWatched.compareTo(a.lastWatched));
    return entries;
  }

  Future<void> _save() async {
    if (!Hive.isBoxOpen('wenatv_user')) return;
    await Hive.box(
      'wenatv_user',
    ).put(_boxKey, [for (final entry in state) entry.toJson()]);
  }
}
