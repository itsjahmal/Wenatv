import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/api_config.dart';
import '../../data/models/media_item.dart';
import 'provider_interface.dart';

final providerStreamResolverProvider = Provider<ProviderStreamResolver>((ref) {
  return ProviderStreamResolver();
});

class ProviderStreamResolver {
  ProviderStreamResolver()
    : _dio = Dio(
        BaseOptions(
          connectTimeout: const Duration(seconds: 8),
          receiveTimeout: const Duration(seconds: 12),
          headers: const {
            'user-agent':
                'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
          },
        ),
      );

  final Dio _dio;

  Future<List<StreamSource>> resolve({
    required String providerValue,
    required MediaItem item,
    String? providerName,
    int? season,
    int? episode,
  }) async {
    if (providerValue != 'autoEmbed') {
      throw UnsupportedError(
        'Install MultiStream for direct playback. $providerValue needs the full Vega JavaScript runtime bridge.',
      );
    }
    return _resolveAutoEmbed(
      tmdbId: item.id,
      type: item.kind == MediaKind.tv ? 'series' : 'movie',
      season: item.kind == MediaKind.tv ? season ?? 1 : null,
      episode: item.kind == MediaKind.tv ? episode ?? 1 : null,
      providerName: providerName ?? 'MultiStream',
    );
  }

  Future<List<StreamSource>> _resolveAutoEmbed({
    required int tmdbId,
    required String type,
    int? season,
    int? episode,
    required String providerName,
  }) async {
    final baseUrl = await _getRiveBaseUrl();
    final streams = <StreamSource>[];
    final imdbId = await _getImdbId(tmdbId, type);
    streams.addAll(
      await _resolveWebstreamer(
        imdbId: imdbId,
        type: type,
        season: season,
        episode: episode,
        providerName: providerName,
      ),
    );
    if (baseUrl.isEmpty) return _unique(streams);

    final secret = _generateSecretKey(tmdbId.toString());
    final servers = [
      'flowcast',
      'asiacloud',
      'humpy',
      'primevids',
      'shadow',
      'hindicast',
      'animez',
      'aqua',
      'yggdrasil',
      'putafilme',
      'ophim',
    ];

    await Future.wait([
      for (final server in servers)
        _dio
            .get<Map<String, dynamic>>(
              '$baseUrl/api/backendfetch',
              queryParameters: _riveQuery(
                tmdbId: tmdbId,
                type: type,
                season: season,
                episode: episode,
                secret: secret,
                server: server,
              ),
            )
            .then((response) {
              final sources =
                  ((response.data?['data'] as Map?)?['sources'] as List?) ??
                  const [];
              for (final raw in sources.whereType<Map>()) {
                final url = raw['url']?.toString() ?? '';
                if (url.isEmpty) continue;
                final format = raw['format']?.toString() == 'hls'
                    ? 'm3u8'
                    : 'mp4';
                final quality = raw['quality']?.toString() ?? 'auto';
                final source = raw['source']?.toString() ?? server;
                streams.add(
                  StreamSource(
                    url: url,
                    quality: quality,
                    format: format,
                    headers: {
                      'referer': baseUrl,
                      'origin': baseUrl,
                      'accept': '*/*',
                      'user-agent':
                          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
                      'x-wenatv-server': source,
                    },
                    providerName: providerName,
                    label: source,
                    subtitles: _subtitleTracksFromJson(raw),
                  ),
                );
              }
            })
            .catchError((_) {}),
    ]);

    return _unique(streams);
  }

  Map<String, dynamic> _riveQuery({
    required int tmdbId,
    required String type,
    required int? season,
    required int? episode,
    required String secret,
    required String server,
  }) {
    final query = <String, dynamic>{
      'requestID': type == 'series' ? 'tvVideoProvider' : 'movieVideoProvider',
      'id': tmdbId,
      'secretKey': secret,
      'service': server,
      'proxyMode': '',
    };
    if (season != null) query['season'] = season;
    if (episode != null) query['episode'] = episode;
    return query;
  }

  Future<List<StreamSource>> _resolveWebstreamer({
    required String imdbId,
    required String type,
    int? season,
    int? episode,
    required String providerName,
  }) async {
    if (imdbId.isEmpty || imdbId == 'undefined') return const [];
    final seriesSuffix = type == 'series' ? ':$season:$episode' : '';
    final rawUrl =
        'https://webstreamr.hayd.uk/{"multi":"on","al":"on","de":"on","es":"on","fr":"on","hi":"on","it":"on","mx":"on","mediaFlowProxyUrl":"","mediaFlowProxyPassword":""}/stream/$type/$imdbId$seriesSuffix.json';
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        Uri.encodeFull(rawUrl),
        options: Options(
          headers: const {'referer': 'https://webstreamr.hayd.uk/'},
        ),
      );
      final rawStreams = ((response.data?['streams'] as List?) ?? const [])
          .whereType<Map>();
      return rawStreams
          .map((raw) {
            final url = raw['url']?.toString() ?? '';
            if (url.isEmpty) return null;
            final name = raw['name']?.toString() ?? 'WebStreamer';
            final qualityMatch = RegExp(r'(\d{3,4})p').firstMatch(name);
            return StreamSource(
              url: url,
              quality: qualityMatch?.group(1) ?? name,
              format: url.contains('.m3u8') ? 'm3u8' : 'mp4',
              headers: const {
                'referer': 'https://webstreamr.hayd.uk/',
                'origin': 'https://webstreamr.hayd.uk',
                'accept': '*/*',
                'user-agent':
                    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
              },
              providerName: providerName,
              label: name,
              subtitles: _subtitleTracksFromJson(raw),
            );
          })
          .whereType<StreamSource>()
          .toList();
    } catch (_) {
      return const [];
    }
  }

  List<StreamSource> _unique(List<StreamSource> streams) {
    final unique = <String, StreamSource>{};
    for (final stream in streams) {
      unique[stream.url] = stream;
    }
    return unique.values.toList();
  }

  List<SubtitleTrack> _subtitleTracksFromJson(Map raw) {
    final value =
        raw['subtitles'] ??
        raw['subtitle'] ??
        raw['captions'] ??
        raw['tracks'] ??
        raw['subs'];
    if (value is! List) return const [];
    return value
        .whereType<Map>()
        .map((item) {
          final url =
              item['url'] ??
              item['link'] ??
              item['file'] ??
              item['src'] ??
              item['href'];
          final language = (item['language'] ?? item['lang'] ?? '').toString();
          final label = (item['label'] ?? item['title'] ?? item['name'] ?? '')
              .toString();
          final format = (item['type'] ?? item['format'] ?? item['mime'] ?? '')
              .toString();
          return SubtitleTrack(
            label: label.isEmpty ? language : label,
            language: language,
            url: (url ?? '').toString(),
            format: format.isEmpty ? null : format,
          );
        })
        .where((track) => track.url.isNotEmpty)
        .toList();
  }

  Future<String> _getRiveBaseUrl() async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        'https://himanshu8443.github.io/providers/modflix.json',
      );
      return ((response.data?['rive'] as Map?)?['url'] ?? '').toString();
    } catch (_) {
      return '';
    }
  }

  Future<String> _getImdbId(int tmdbId, String type) async {
    try {
      final kind = type == 'series' ? 'tv' : 'movie';
      final response = await _dio.get<Map<String, dynamic>>(
        '${ApiConfig.tmdbBaseUrl}/$kind/$tmdbId/external_ids',
        options: Options(
          headers: const {
            'Authorization': 'Bearer ${ApiConfig.tmdbReadAccessToken}',
            'accept': 'application/json',
          },
        ),
      );
      return response.data?['imdb_id']?.toString() ?? '';
    } catch (_) {
      return '';
    }
  }

  String _generateSecretKey(String id) {
    const seeds = [
      '4Z7lUo',
      'gwIVSMD',
      'PLmz2elE2v',
      'Z4OFV0',
      'SZ6RZq6Zc',
      'zhJEFYxrz8',
      'FOm7b0',
      'axHS3q4KDq',
      'o9zuXQ',
      '4Aebt',
      'wgjjWwKKx',
      'rY4VIxqSN',
      'kfjbnSo',
      '2DyrFA1M',
      'YUixDM9B',
      'JQvgEj0',
      'mcuFx6JIek',
      'eoTKe26gL',
      'qaI9EVO1rB',
      '0xl33btZL',
      '1fszuAU',
      'a7jnHzst6P',
      'wQuJkX',
      'cBNhTJlEOf',
      'KNcFWhDvgT',
      'XipDGjST',
      'PCZJlbHoyt',
      '2AYnMZkqd',
      'HIpJh',
      'KH0C3iztrG',
      'W81hjts92',
      'rJhAT',
      'NON7LKoMQ',
      'NMdY3nsKzI',
      't4En5v',
      'Qq5cOQ9H',
      'Y9nwrp',
      'VX5FYVfsf',
      'cE5SJG',
      'x1vj1',
      'HegbLe',
      'zJ3nmt4OA',
      'gt7rxW57dq',
      'clIE9b',
      'jyJ9g',
      'B5jXjMCSx',
      'cOzZBZTV',
      'FTXGy',
      'Dfh1q1',
      'ny9jqZ2POI',
      'X2NnMn',
      'MBtoyD',
      'qz4Ilys7wB',
      '68lbOMye',
      '3YUJnmxp',
      '1fv5Imona',
      'PlfvvXD7mA',
      'ZarKfHCaPR',
      'owORnX',
      'dQP1YU',
      'dVdkx',
      'qgiK0E',
      'cx9wQ',
      '5F9bGa',
      '7UjkKrp',
      'Yvhrj',
      'wYXez5Dg3',
      'pG4GMU',
      'MwMAu',
      'rFRD5wlM',
    ];
    final numeric = int.tryParse(id);
    final sum = numeric ?? id.codeUnits.fold<int>(0, (sum, code) => sum + code);
    final seed = seeds[sum % seeds.length];
    final cut = id.isEmpty ? 0 : ((sum % id.length) / 2).floor();
    final mixed = '${id.substring(0, cut)}$seed${id.substring(cut)}';
    final hash = _outerHash(_innerHash(mixed));
    return base64.encode(utf8.encode(hash));
  }

  String _innerHash(String value) {
    var hash = 0;
    for (var i = 0; i < value.length; i++) {
      final code = value.codeUnitAt(i);
      hash = _u32(code + (hash << 6) + (hash << 16) - hash);
      final rotated = _u32((hash << (i % 5)) | _ushr(hash, 32 - (i % 5)));
      hash = _u32(
        hash ^ rotated ^ _u32((code << (i % 7)) | _ushr(code, 8 - (i % 7))),
      );
      hash = _u32(hash + (_ushr(hash, 11) ^ (hash << 3)));
    }
    hash ^= _ushr(hash, 15);
    hash = _imul(hash, 49842);
    hash ^= _ushr(hash, 13);
    hash = _imul(hash, 40503);
    hash ^= _ushr(hash, 16);
    return _jsSignedHex(hash);
  }

  String _outerHash(String value) {
    var hash = _u32(0xDEADBEEF ^ value.length);
    for (var i = 0; i < value.length; i++) {
      var code = value.codeUnitAt(i);
      code ^= 0xff & (131 * i + 89 ^ (code << (i % 5)));
      hash = _u32(_u32((hash << 7) | _ushr(hash, 25)) ^ code);
      hash = _imul(hash, 60205);
      hash ^= _ushr(hash, 11);
    }
    hash ^= _ushr(hash, 15);
    hash = _imul(hash, 49842);
    hash ^= _ushr(hash, 13);
    hash = _imul(hash, 40503);
    hash ^= _ushr(hash, 16);
    hash = _imul(hash, 10196);
    hash ^= _ushr(hash, 15);
    return _jsSignedHex(hash);
  }

  int _imul(int value, int factor) {
    return _u32(
      factor * (value & 0xffff) +
          (((factor * _ushr(value, 16)) & 0xffff) << 16),
    );
  }

  int _ushr(int value, int shift) => value.toUnsigned(32) >> (shift & 31);

  int _u32(int value) => value.toUnsigned(32);

  String _jsSignedHex(int value) =>
      value.toSigned(32).toRadixString(16).padLeft(8, '0');
}
