import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_js/flutter_js.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:html/parser.dart' as html_parser;

import 'provider_interface.dart';

final providerJsBridgeProvider = Provider<ProviderJsBridge>((ref) {
  return ProviderJsBridge(Hive.box('wenatv_cache'));
});

class ProviderJsBridge {
  ProviderJsBridge(this._cache);

  static const _moduleBoxKey = 'provider_modules';
  final Box _cache;
  final _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 7),
      receiveTimeout: const Duration(seconds: 10),
    ),
  );

  Future<List<ProviderCatalog>> getCatalog({
    required String sourceUrl,
    required String providerValue,
  }) async {
    final modules = await _modules(sourceUrl, providerValue);
    final catalog = modules['catalog'];
    if (catalog == null) return _nativeCatalog(providerValue);
    try {
      final result = await _runJson('''
        const moduleExports = (function() {
          const module = { exports: {} };
          const exports = module.exports;
          $catalog
          return module.exports;
        })();
        const provider = moduleExports.default || moduleExports;
        JSON.stringify(provider.catalog || provider.Catalog || []);
        ''');
      final parsed = result
          .whereType<Map>()
          .map(
            (item) => ProviderCatalog.fromJson(Map<String, dynamic>.from(item)),
          )
          .toList();
      return parsed.isEmpty ? _nativeCatalog(providerValue) : parsed;
    } catch (_) {
      return _nativeCatalog(providerValue);
    }
  }

  Future<List<ProviderPost>> getPosts({
    required String sourceUrl,
    required String providerValue,
    required String filter,
    int page = 1,
  }) async {
    final modules = await _modules(sourceUrl, providerValue);
    final posts = modules['posts'];
    final context = await _providerContext(sourceUrl, providerValue);
    if (posts == null || context == null) {
      return _nativePosts(
        providerValue: providerValue,
        filter: filter,
        page: page,
      );
    }
    try {
      final result = await _runJsonAsync('''
        ${_bootstrapContext(context)}
        const moduleExports = (function() {
          const module = { exports: {} };
          const exports = module.exports;
          $posts
          return module.exports;
        })();
        const provider = moduleExports.default || moduleExports;
        const getPosts = provider.getPosts || provider.GetHomePosts;
        if (!getPosts) throw new Error('Provider does not expose posts');
        getPosts({
          filter: ${jsonEncode(filter)},
          page: $page,
          providerValue: ${jsonEncode(providerValue)},
          signal: { aborted: false },
          providerContext
        }).then(value => JSON.stringify(value || []));
        ''');
      final parsed = result
          .whereType<Map>()
          .map((item) => ProviderPost.fromJson(Map<String, dynamic>.from(item)))
          .where((post) => post.title.isNotEmpty && post.link.isNotEmpty)
          .toList();
      return parsed.isEmpty
          ? _nativePosts(
              providerValue: providerValue,
              filter: filter,
              page: page,
            )
          : parsed;
    } catch (_) {
      return _nativePosts(
        providerValue: providerValue,
        filter: filter,
        page: page,
      );
    }
  }

  Future<List<ProviderPost>> searchPosts({
    required String sourceUrl,
    required String providerValue,
    required String query,
    int page = 1,
  }) async {
    final modules = await _modules(sourceUrl, providerValue);
    final posts = modules['posts'];
    final context = await _providerContext(sourceUrl, providerValue);
    if (posts == null || context == null) {
      return _nativeSearchPosts(
        providerValue: providerValue,
        query: query,
        page: page,
      );
    }
    try {
      final result = await _runJsonAsync('''
        ${_bootstrapContext(context)}
        const moduleExports = (function() {
          const module = { exports: {} };
          const exports = module.exports;
          $posts
          return module.exports;
        })();
        const provider = moduleExports.default || moduleExports;
        const search =
          provider.getSearchPosts ||
          provider.GetSearchPosts ||
          provider.getPosts ||
          provider.GetHomePosts;
        if (!search) throw new Error('Provider does not expose search/posts');
        search({
          searchQuery: ${jsonEncode(query)},
          filter: ${jsonEncode(query)},
          page: $page,
          providerValue: ${jsonEncode(providerValue)},
          signal: { aborted: false },
          providerContext
        }).then(value => JSON.stringify(value || []));
        ''');
      final parsed = result
          .whereType<Map>()
          .map((item) => ProviderPost.fromJson(Map<String, dynamic>.from(item)))
          .where((post) => post.title.isNotEmpty && post.link.isNotEmpty)
          .toList();
      return parsed.isEmpty
          ? _nativeSearchPosts(
              providerValue: providerValue,
              query: query,
              page: page,
            )
          : parsed;
    } catch (_) {
      return _nativeSearchPosts(
        providerValue: providerValue,
        query: query,
        page: page,
      );
    }
  }

  Future<ProviderMeta?> getMeta({
    required String sourceUrl,
    required String providerValue,
    required String link,
  }) async {
    final modules = await _modules(sourceUrl, providerValue);
    final meta = modules['meta'];
    final context = await _providerContext(sourceUrl, providerValue);
    if (meta == null || context == null) {
      return _nativeMeta(providerValue: providerValue, link: link);
    }
    try {
      final result = await _runJsonObjectAsync('''
        ${_bootstrapContext(context)}
        const moduleExports = (function() {
          const module = { exports: {} };
          const exports = module.exports;
          $meta
          return module.exports;
        })();
        const provider = moduleExports.default || moduleExports;
        const getMeta = provider.getMeta || provider.GetMetaData;
        if (!getMeta) throw new Error('Provider does not expose metadata');
        getMeta({
          link: ${jsonEncode(link)},
          provider: ${jsonEncode(providerValue)},
          providerContext
        }).then(value => JSON.stringify(value || {}));
        ''');
      if (result.isEmpty) {
        return _nativeMeta(providerValue: providerValue, link: link);
      }
      final parsed = ProviderMeta.fromJson(result);
      return parsed.linkList.isEmpty
          ? _nativeMeta(providerValue: providerValue, link: link)
          : parsed;
    } catch (_) {
      return _nativeMeta(providerValue: providerValue, link: link);
    }
  }

  Future<List<StreamSource>> getStreams({
    required String sourceUrl,
    required String providerValue,
    required String link,
    required String type,
  }) async {
    final modules = await _modules(sourceUrl, providerValue);
    final stream = modules['stream'];
    final context = await _providerContext(sourceUrl, providerValue);
    if (stream == null || context == null) {
      return _nativeStreams(
        providerValue: providerValue,
        link: link,
        type: type,
      );
    }
    try {
      final result = await _runJsonAsync('''
        ${_bootstrapContext(context)}
        const moduleExports = (function() {
          const module = { exports: {} };
          const exports = module.exports;
          $stream
          return module.exports;
        })();
        const provider = moduleExports.default || moduleExports;
        const getStream = provider.getStream || provider.GetStream;
        if (!getStream) throw new Error('Provider does not expose streams');
        getStream({
          link: ${jsonEncode(link)},
          type: ${jsonEncode(type)},
          signal: { aborted: false },
          providerContext
        }).then(value => JSON.stringify(value || []));
        ''');
      final parsed = result
          .whereType<Map>()
          .map((item) {
            final map = Map<String, dynamic>.from(item);
            final headers = (map['headers'] as Map?) ?? const {};
            return StreamSource(
              url: (map['link'] ?? map['url'] ?? '').toString(),
              quality: (map['quality'] ?? map['server'] ?? 'auto').toString(),
              format: (map['type'] ?? 'mp4').toString(),
              headers: headers.map(
                (key, value) => MapEntry(key.toString(), value.toString()),
              ),
              language: (map['language'] ?? map['lang'])?.toString(),
              fileSize: (map['fileSize'] ?? map['size'])?.toString(),
              label: (map['server'] ?? map['title'] ?? map['name'])?.toString(),
              subtitles: _subtitleTracksFromJson(map),
            );
          })
          .where((stream) => stream.url.isNotEmpty)
          .toList();
      return parsed.isEmpty
          ? _nativeStreams(providerValue: providerValue, link: link, type: type)
          : parsed;
    } catch (_) {
      return _nativeStreams(
        providerValue: providerValue,
        link: link,
        type: type,
      );
    }
  }

  Future<List<ProviderDirectLink>> getEpisodes({
    required String sourceUrl,
    required String providerValue,
    required String episodesLink,
  }) async {
    final modules = await _modules(sourceUrl, providerValue);
    final episodes = modules['episodes'];
    final context = await _providerContext(sourceUrl, providerValue);
    if (episodes == null || context == null || episodesLink.isEmpty) {
      return const [];
    }
    final result = await _runJsonAsync('''
      ${_bootstrapContext(context)}
      const moduleExports = (function() {
        const module = { exports: {} };
        const exports = module.exports;
        $episodes
        return module.exports;
      })();
      const provider = moduleExports.default || moduleExports;
      const getEpisodes = provider.getEpisodes || provider.GetEpisodeLinks;
      if (!getEpisodes) throw new Error('Provider does not expose episodes');
      getEpisodes({
        url: ${jsonEncode(episodesLink)},
        providerContext
      }).then(value => JSON.stringify(value || []));
      ''');
    return result
        .whereType<Map>()
        .map(
          (item) =>
              ProviderDirectLink.fromJson(Map<String, dynamic>.from(item)),
        )
        .where((item) => item.link.isNotEmpty)
        .toList();
  }

  Future<List<StreamSource>> resolveNativeVegaStreams({
    required String contentLink,
    required String title,
    required String type,
  }) async {
    final links = <String>{};
    if (contentLink.isNotEmpty) links.add(contentLink);

    final search = await _nativeSearchPosts(
      providerValue: 'vega',
      query: title,
      page: 1,
    );
    for (final post in search.take(4)) {
      if (post.link.isNotEmpty) links.add(post.link);
    }

    final streams = <String, StreamSource>{};
    for (final link in links) {
      final meta = await _nativeMeta(providerValue: 'vega', link: link);
      final directLinks = <ProviderDirectLink>[
        if (meta != null)
          for (final metaLink in meta.linkList)
            ...metaLink.directLinks.where((direct) => direct.link.isNotEmpty),
      ];
      if (directLinks.isEmpty) {
        final direct = await _nativeStreams(
          providerValue: 'vega',
          link: link,
          type: type,
        );
        for (final stream in direct) {
          streams[stream.url] = stream;
        }
        continue;
      }
      final resolvedGroups = await Future.wait([
        for (final direct in directLinks.take(8))
          _nativeStreams(
            providerValue: 'vega',
            link: direct.link,
            type: type,
          ).timeout(const Duration(seconds: 24), onTimeout: () => const []),
      ]);
      for (final resolved in resolvedGroups) {
        for (final stream in resolved) {
          streams[stream.url] = stream;
        }
      }
      if (streams.isNotEmpty) break;
    }
    return streams.values.toList();
  }

  Future<Map<String, String>> _modules(
    String sourceUrl,
    String providerValue,
  ) async {
    final cache = Map<String, dynamic>.from(
      (_cache.get(_moduleBoxKey) as Map?) ?? const {},
    );
    final provider = Map<String, dynamic>.from(
      (cache['$sourceUrl::$providerValue'] as Map?) ?? const {},
    );
    return Map<String, String>.from(
      (provider['modules'] as Map?) ?? const <String, String>{},
    );
  }

  List<ProviderCatalog> _nativeCatalog(String providerValue) {
    if (providerValue != 'vega') return const [];
    return const [
      ProviderCatalog(title: 'New', filter: ''),
      ProviderCatalog(title: 'Netflix', filter: 'category/web-series/netflix'),
      ProviderCatalog(
        title: 'Amazon Prime',
        filter: 'category/web-series/amazon-prime-video',
      ),
      ProviderCatalog(title: '4K Movies', filter: 'movies-by-quality/2160p'),
    ];
  }

  Future<List<ProviderPost>> _nativePosts({
    required String providerValue,
    required String filter,
    required int page,
  }) async {
    if (providerValue != 'vega') return const [];
    final baseUrl = await _providerBaseUrl('Vega');
    if (baseUrl.isEmpty) return const [];
    final url = filter.isEmpty
        ? '$baseUrl/page/$page/'
        : '$baseUrl/genre/$filter/page/$page/';
    try {
      final response = await _dio.get<String>(
        url,
        options: Options(
          responseType: ResponseType.plain,
          headers: {
            'Accept':
                'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
            'User-Agent':
                'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
            'Referer': baseUrl,
          },
        ),
      );
      final document = html_parser.parse(response.data ?? '');
      final posts = <ProviderPost>[];
      final containers = document.querySelectorAll(
        '.blog-items, .post-list, #archive-container, .movies-grid',
      );
      final elements = containers.isEmpty
          ? document.querySelectorAll('article, .entry-list-item')
          : containers
                .expand(
                  (container) => container.querySelectorAll(
                    'article, .entry-list-item, a',
                  ),
                )
                .toList();
      for (final element in elements) {
        final anchor = element.localName == 'a'
            ? element
            : element.querySelector('a');
        final rawLink = anchor?.attributes['href'] ?? '';
        final link = _absoluteUrl(baseUrl, rawLink);
        final titleText =
            element
                .querySelector('.entry-title, .poster-title, .post-title')
                ?.text ??
            anchor?.attributes['title'] ??
            '';
        final title = titleText
            .replaceFirst(RegExp(r'^Download\s*', caseSensitive: false), '')
            .trim();
        final imageElement = element.querySelector('img');
        final image = _absoluteUrl(
          baseUrl,
          imageElement?.attributes['data-lazy-src'] ??
              imageElement?.attributes['data-src'] ??
              imageElement?.attributes['src'] ??
              '',
        );
        if (title.isNotEmpty && link.isNotEmpty) {
          posts.add(ProviderPost(title: title, link: link, image: image));
        }
      }
      return posts.take(40).toList();
    } catch (_) {
      return const [];
    }
  }

  Future<List<ProviderPost>> _nativeSearchPosts({
    required String providerValue,
    required String query,
    required int page,
  }) async {
    if (providerValue != 'vega') return const [];
    final baseUrl = await _providerBaseUrl('Vega');
    if (baseUrl.isEmpty) return const [];
    final normalizedQuery = _normalizeSearch(query);
    if (normalizedQuery.isEmpty) return const [];
    final searchUrl =
        '$baseUrl/search.php?q=${Uri.encodeQueryComponent(query)}&page=$page';
    try {
      final response = await _dio.get(
        searchUrl,
        options: Options(
          headers: {
            'Accept': 'application/json,text/plain,*/*',
            'User-Agent':
                'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
            'Referer': baseUrl,
          },
        ),
      );
      final data = response.data;
      final hits = data is Map ? (data['hits'] as List?) : null;
      final posts = <ProviderPost>[];
      if (hits != null) {
        for (final hit in hits.whereType<Map>()) {
          final doc = hit['document'];
          if (doc is! Map) continue;
          final rawTitle = (doc['post_title'] ?? doc['title'] ?? '').toString();
          final link = _absoluteUrl(
            baseUrl,
            (doc['permalink'] ?? doc['link'] ?? '').toString(),
          );
          final image = _absoluteUrl(
            baseUrl,
            (doc['post_thumbnail'] ?? doc['image'] ?? '').toString(),
          );
          final title = rawTitle
              .replaceFirst(RegExp(r'^Download\s*', caseSensitive: false), '')
              .trim();
          if (title.isNotEmpty && link.isNotEmpty) {
            posts.add(ProviderPost(title: title, link: link, image: image));
          }
        }
      }
      if (posts.isNotEmpty) return posts;
    } catch (_) {}

    final recent = await _nativePosts(
      providerValue: providerValue,
      filter: '',
      page: page,
    );
    return recent
        .where((post) => _normalizeSearch(post.title).contains(normalizedQuery))
        .toList();
  }

  Future<ProviderMeta?> _nativeMeta({
    required String providerValue,
    required String link,
  }) async {
    if (providerValue != 'vega' || link.isEmpty) return null;
    try {
      final baseUrl = Uri.parse(link).origin;
      final response = await _dio.get<String>(
        link,
        options: Options(
          responseType: ResponseType.plain,
          headers: {
            'Accept':
                'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
            'User-Agent':
                'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
            'Referer': baseUrl,
          },
        ),
      );
      final document = html_parser.parse(response.data ?? '');
      final content =
          document.querySelector(
            '.entry-content, .post-inner, .post-content, .page-body',
          ) ??
          document.body;
      final title =
          (document.querySelector('h1.post-title')?.text ??
                  document.querySelector('h1, h2')?.text ??
                  '')
              .trim();
      final bodyText = content?.text ?? '';
      final type =
          RegExp(
            r'\b(Series Name|Season\s*\d+|Episode\s*\d+)\b',
            caseSensitive: false,
          ).hasMatch(bodyText)
          ? 'series'
          : 'movie';
      final links = <ProviderMetaLink>[];
      final anchors = content?.querySelectorAll('a[href]') ?? const [];
      for (final anchor in anchors) {
        final text = anchor.text.trim();
        final href = _absoluteUrl(baseUrl, anchor.attributes['href'] ?? '');
        if (href.isEmpty) continue;
        final isCandidate =
            RegExp(
              r'(download|episode|v-cloud|vcloud|hubcloud|cloud|g-direct)',
              caseSensitive: false,
            ).hasMatch(text) ||
            RegExp(
              r'(hubcloud|v-cloud|vcloud|cloud|filepress|techy|drive|nexdrive|hubrouting|vglist)',
              caseSensitive: false,
            ).hasMatch(href);
        if (!isCandidate) continue;
        final label = text.isEmpty ? 'Provider Link' : text;
        final quality =
            RegExp(
              r'\b(480p|720p|1080p|2160p|4k)\b',
              caseSensitive: false,
            ).firstMatch(label)?.group(0) ??
            '';
        links.add(
          ProviderMetaLink(
            title: label,
            quality: quality,
            episodesLink: type == 'series' ? href : '',
            directLinks: [ProviderDirectLink(title: label, link: href)],
          ),
        );
      }
      final unique = <String, ProviderMetaLink>{};
      for (final item in links) {
        final key = item.episodesLink.isNotEmpty
            ? item.episodesLink
            : item.directLinks.map((link) => link.link).join('|');
        if (key.isNotEmpty) unique[key] = item;
      }
      return ProviderMeta(
        title: title,
        type: type,
        linkList: unique.values.toList(),
      );
    } catch (_) {
      return null;
    }
  }

  Future<List<StreamSource>> _nativeStreams({
    required String providerValue,
    required String link,
    required String type,
  }) async {
    if (providerValue != 'vega' || link.isEmpty) return const [];
    try {
      var target = link;
      final headers = {
        'Accept':
            'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
        'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
        'Referer': Uri.parse(link).origin,
        'Cookie': 'ext_name=ojplmecpdpgccookcobabopnaifgidhf; xla=s4t',
      };
      if (type == 'movie') {
        final page = await _dio.get<String>(
          target,
          options: Options(responseType: ResponseType.plain, headers: headers),
        );
        final html = page.data ?? '';
        final cloudMatch = RegExp(
          r'<a\s+href="([^"]*cloud\.[^"]*)"',
          caseSensitive: false,
        ).firstMatch(html);
        if (cloudMatch != null) target = cloudMatch.group(1) ?? target;
      }
      return _extractHubCloud(target, headers);
    } catch (_) {
      return const [];
    }
  }

  Future<List<StreamSource>> _extractHubCloud(
    String link,
    Map<String, String> headers,
  ) async {
    try {
      final initialDirect = await _resolveDownloadLink(link, headers);
      if (initialDirect != null && _isPlayableLink(initialDirect)) {
        return [_streamFromDirectUrl(initialDirect)];
      }
      final baseUrl = Uri.parse(link).origin;
      final first = await _dio.get<String>(
        link,
        options: Options(responseType: ResponseType.plain, headers: headers),
      );
      final firstHtml = first.data ?? '';
      final redirectMatch = RegExp(
        r"var\s+url\s*=\s*'([^']+)';",
        caseSensitive: false,
      ).firstMatch(firstHtml);
      var cloudLink = link;
      final redirect = redirectMatch?.group(1);
      if (redirect != null && redirect.isNotEmpty) {
        final encoded = Uri.tryParse(redirect)?.queryParameters['r'];
        if (encoded != null && encoded.isNotEmpty) {
          try {
            cloudLink = utf8.decode(base64.decode(encoded));
          } catch (_) {
            cloudLink = redirect;
          }
        } else {
          cloudLink = redirect;
        }
      } else {
        final doc = html_parser.parse(firstHtml);
        cloudLink =
            doc
                .querySelector('.fa-file-download.fa-lg')
                ?.parent
                ?.attributes['href'] ??
            link;
      }
      if (cloudLink.startsWith('/')) cloudLink = '$baseUrl$cloudLink';
      if (_isPlayableLink(cloudLink)) {
        return [_streamFromDirectUrl(cloudLink)];
      }

      var cloud = await _dio.get<String>(
        cloudLink,
        options: Options(
          responseType: ResponseType.plain,
          headers: headers,
          followRedirects: true,
        ),
      );
      var cloudHtml = cloud.data ?? '';
      final hubRouting = RegExp(
        r"var\s+url\s*=\s*'([^']+)';",
        caseSensitive: false,
      ).firstMatch(cloudHtml)?.group(1);
      if (hubRouting != null && hubRouting.isNotEmpty) {
        if (_isPlayableLink(hubRouting)) {
          return [_streamFromDirectUrl(hubRouting)];
        }
        cloud = await _dio.get<String>(
          hubRouting,
          options: Options(
            responseType: ResponseType.plain,
            headers: {...headers, 'Referer': cloudLink},
            followRedirects: true,
          ),
        );
        cloudHtml = cloud.data ?? cloudHtml;
        cloudLink = hubRouting;
      }
      final document = html_parser.parse(cloudHtml);
      final nestedLinks = document
          .querySelectorAll('a[href]')
          .map((anchor) => anchor.attributes['href'] ?? '')
          .where((href) {
            final value = href.toLowerCase();
            return value.contains('vcloud') ||
                value.contains('hubrouting') ||
                value.contains('hubcloud') ||
                value.contains('hubcdn') ||
                value.contains('pixeldrain') ||
                value.contains('cloudflarestorage');
          })
          .map((href) => _absoluteUrl(Uri.parse(cloudLink).origin, href))
          .where((href) => href.isNotEmpty && href != link && href != cloudLink)
          .take(6)
          .toList();
      final buttons = document.querySelectorAll(
        '.btn-success.btn-lg.h6, .btn-danger, .btn-secondary, a.btn-success, a.btn-danger, a.btn-secondary',
      );
      final streams = <StreamSource>[];
      final nestedGroups = await Future.wait([
        for (final nested in nestedLinks)
          _resolveNestedStream(
            nested,
            headers,
          ).timeout(const Duration(seconds: 18), onTimeout: () => const []),
      ]);
      for (final group in nestedGroups) {
        streams.addAll(group);
      }
      for (final button in buttons) {
        final href = button.attributes['href'] ?? '';
        if (href.isEmpty) continue;
        final resolved = _absoluteUrl(Uri.parse(cloudLink).origin, href);
        final direct = await _resolveDownloadLink(resolved, headers);
        if (direct == null || direct.isEmpty) continue;
        streams.add(_streamFromDirectUrl(direct, fallbackText: button.text));
      }
      return streams;
    } catch (_) {
      return const [];
    }
  }

  Future<List<StreamSource>> _resolveNestedStream(
    String nested,
    Map<String, String> headers,
  ) async {
    final direct = await _resolveDownloadLink(nested, headers);
    if (direct != null && direct.isNotEmpty && _isPlayableLink(direct)) {
      return [_streamFromDirectUrl(direct, fallbackText: nested)];
    }
    if (nested.contains('vcloud') ||
        nested.contains('hubrouting') ||
        nested.contains('hubcloud')) {
      return _extractHubCloud(nested, headers);
    }
    return const [];
  }

  Future<String?> _resolveDownloadLink(
    String link,
    Map<String, String> headers,
  ) async {
    if (link.contains('/re.php')) {
      final encoded = Uri.tryParse(link)?.queryParameters['l'];
      if (encoded != null && encoded.isNotEmpty) {
        try {
          return utf8.decode(base64.decode(encoded));
        } catch (_) {}
      }
    }
    if (link.contains('pixeld') && !link.contains('/api/')) {
      final token = Uri.parse(link).pathSegments.last;
      final base = link.split('/').take(link.split('/').length - 2).join('/');
      return '$base/api/file/$token';
    }
    if (link.contains('.dev') ||
        link.contains('cloudflarestorage') ||
        link.contains('fastdl') ||
        link.contains('fsl.') ||
        link.contains('hubcdn') ||
        link.contains('.mkv') ||
        link.contains('.mp4') ||
        link.contains('.m3u8') ||
        link.contains('?token=')) {
      return link;
    }
    if (link.contains('hubcloud') || link.contains('/?id=')) {
      try {
        final first = await _dio.headUri(
          Uri.parse(link),
          options: Options(
            headers: headers,
            followRedirects: false,
            validateStatus: (_) => true,
          ),
        );
        var location = first.headers.value('location') ?? link;
        if (location.contains('googleusercontent')) {
          return Uri.tryParse(location)?.queryParameters['link'] ?? location;
        }
        final second = await _dio.headUri(
          Uri.parse(location),
          options: Options(
            headers: headers,
            followRedirects: false,
            validateStatus: (_) => true,
          ),
        );
        location = second.headers.value('location') ?? location;
        return Uri.tryParse(location)?.queryParameters['link'] ?? location;
      } catch (_) {
        return link;
      }
    }
    return null;
  }

  bool _isPlayableLink(String link) {
    final value = link.toLowerCase();
    return value.contains('cloudflarestorage') ||
        value.contains('pixeldrain') ||
        value.contains('fastdl') ||
        value.contains('fsl.') ||
        value.contains('hubcdn') ||
        value.contains('.dev') ||
        value.contains('.m3u8') ||
        value.contains('.mp4') ||
        value.contains('.mkv') ||
        value.contains('?token=');
  }

  StreamSource _streamFromDirectUrl(String url, {String fallbackText = ''}) {
    final filename = _fileNameFromUrl(url);
    final episode = _episodeFromText('$filename $fallbackText');
    return StreamSource(
      url: url,
      quality: _qualityFromText('$filename $fallbackText $url'),
      format: url.contains('.m3u8')
          ? 'hls'
          : url.contains('.mp4')
          ? 'mp4'
          : 'mkv',
      headers: const {},
      label: _serverName(url),
      displayTitle: filename.isEmpty ? null : filename,
      season: episode.$1,
      episode: episode.$2,
    );
  }

  String _fileNameFromUrl(String value) {
    final path = Uri.tryParse(value)?.pathSegments.lastOrNull ?? '';
    if (path.isEmpty) return '';
    return Uri.decodeComponent(path)
        .replaceAll(RegExp(r'\.(mkv|mp4|m3u8)$', caseSensitive: false), '')
        .replaceAll(RegExp(r'[._]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  (int?, int?) _episodeFromText(String value) {
    final match = RegExp(
      r'\bS(?:eason)?\s*(\d{1,2})\s*E(?:p(?:isode)?)?\s*(\d{1,3})\b',
      caseSensitive: false,
    ).firstMatch(value);
    if (match == null) return (null, null);
    return (
      int.tryParse(match.group(1) ?? ''),
      int.tryParse(match.group(2) ?? ''),
    );
  }

  String _qualityFromText(String value) {
    return RegExp(
          r'\b(480p|720p|1080p|2160p|4k)\b',
          caseSensitive: false,
        ).firstMatch(value)?.group(0) ??
        'auto';
  }

  String _serverName(String value) {
    final host = Uri.tryParse(value)?.host;
    if (host == null || host.isEmpty) return 'Provider';
    return host.replaceAll('.', ' ');
  }

  String _normalizeSearch(String value) {
    return value
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  Future<String> _providerBaseUrl(String providerValue) async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        'https://himanshu8443.github.io/providers/modflix.json',
      );
      final item = response.data?[providerValue];
      if (item is Map && item['url'] != null) return item['url'].toString();
    } catch (_) {}
    return '';
  }

  String _absoluteUrl(String baseUrl, String value) {
    if (value.isEmpty) return '';
    if (value.startsWith('//')) return 'https:$value';
    final uri = Uri.tryParse(value);
    if (uri != null && uri.hasScheme) return value;
    return Uri.parse(baseUrl).resolve(value).toString();
  }

  Future<String?> _providerContext(
    String sourceUrl,
    String providerValue,
  ) async {
    final cache = Map<String, dynamic>.from(
      (_cache.get(_moduleBoxKey) as Map?) ?? const {},
    );
    final key = '$sourceUrl::$providerValue';
    final provider = Map<String, dynamic>.from(
      (cache[key] as Map?) ?? const {},
    );
    final cached = provider['provider_context']?.toString();
    if (cached != null && cached.isNotEmpty) return cached;
    try {
      final response = await _dio.get<String>(
        '$sourceUrl/dist/providerContext.js',
        options: Options(responseType: ResponseType.plain),
      );
      final data = response.data;
      if (data == null || data.isEmpty) return null;
      provider['provider_context'] = data;
      cache[key] = provider;
      await _cache.put(_moduleBoxKey, cache);
      return data;
    } catch (_) {
      return null;
    }
  }

  String _bootstrapContext(String contextCode) {
    return '''
      if (typeof process === 'undefined') {
        globalThis.process = { env: {} };
      }
      if (typeof require === 'undefined') {
        globalThis.require = function() { return {}; };
      }
      if (typeof globalThis.axios === 'undefined') {
        const axiosRequest = function(method, url, config) {
          config = config || {};
          const headers = config.headers || {};
          const body = config.data || config.body || null;
          return fetch(url, { method, headers, body }).then(function(response) {
            return response.text().then(function(text) {
              let data = text;
              try { data = JSON.parse(text); } catch (_) {}
              return {
                data,
                status: response.status,
                headers: { get: function(name) { return response.headers.get(name); } },
                request: { responseURL: response.url }
              };
            });
          });
        };
        globalThis.axios = {
          get: function(url, config) { return axiosRequest('GET', url, config); },
          post: function(url, data, config) {
            config = config || {};
            config.data = data;
            return axiosRequest('POST', url, config);
          },
          request: function(config) {
            config = config || {};
            return axiosRequest(config.method || 'GET', config.url, config);
          }
        };
      }
      if (typeof atob === 'undefined') {
        globalThis.atob = function(input) {
          const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/=';
          let str = String(input).replace(/=+\$/, '');
          let output = '';
          if (str.length % 4 === 1) throw new Error('Invalid base64');
          for (let bc = 0, bs = 0, buffer, i = 0; buffer = str.charAt(i++); ~buffer && (bs = bc % 4 ? bs * 64 + buffer : buffer, bc++ % 4) ? output += String.fromCharCode(255 & bs >> (-2 * bc & 6)) : 0) {
            buffer = chars.indexOf(buffer);
          }
          return output;
        };
      }
      if (typeof btoa === 'undefined') {
        globalThis.btoa = function(input) {
          const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/=';
          let str = String(input);
          let output = '';
          for (let block = 0, charCode, i = 0, map = chars; str.charAt(i | 0) || (map = '=', i % 1); output += map.charAt(63 & block >> 8 - i % 1 * 8)) {
            charCode = str.charCodeAt(i += 3 / 4);
            if (charCode > 0xFF) throw new Error('Invalid character');
            block = block << 8 | charCode;
          }
          return output;
        };
      }
      if (typeof FormData === 'undefined') {
        globalThis.FormData = function() { this._pairs = []; };
        globalThis.FormData.prototype.append = function(key, value) {
          this._pairs.push([String(key), String(value == null ? '' : value)]);
        };
        globalThis.FormData.prototype.toString = function() {
          return this._pairs.map(function(pair) {
            return encodeURIComponent(pair[0]) + '=' + encodeURIComponent(pair[1]);
          }).join('&');
        };
      }
      if (typeof fetch === 'undefined' && typeof XMLHttpRequest !== 'undefined') {
        globalThis.fetch = function(url, init) {
          init = init || {};
          return new Promise(function(resolve, reject) {
            const xhr = new XMLHttpRequest();
            const method = init.method || 'GET';
            xhr.open(method, String(url), true);
            const headers = init.headers || {};
            Object.keys(headers).forEach(function(key) {
              try { xhr.setRequestHeader(key, headers[key]); } catch (_) {}
            });
            let body = init.body;
            if (body && body._pairs) {
              if (!headers['content-type'] && !headers['Content-Type']) {
                xhr.setRequestHeader('content-type', 'application/x-www-form-urlencoded;charset=UTF-8');
              }
              body = body.toString();
            }
            xhr.onload = function() {
              const rawHeaders = xhr.getAllResponseHeaders ? xhr.getAllResponseHeaders() : '';
              const headerMap = {};
              rawHeaders.trim().split(/[\\r\\n]+/).forEach(function(line) {
                const index = line.indexOf(':');
                if (index > 0) headerMap[line.slice(0, index).toLowerCase()] = line.slice(index + 1).trim();
              });
              resolve({
                ok: xhr.status >= 200 && xhr.status < 300,
                status: xhr.status,
                url: xhr.responseURL || String(url),
                headers: { get: function(name) { return headerMap[String(name).toLowerCase()] || null; } },
                text: function() { return Promise.resolve(xhr.responseText || ''); },
                json: function() {
                  try { return Promise.resolve(JSON.parse(xhr.responseText || 'null')); }
                  catch (error) { return Promise.reject(error); }
                }
              });
            };
            xhr.onerror = function() { reject(new Error('Network request failed')); };
            xhr.ontimeout = function() { reject(new Error('Network request timed out')); };
            xhr.timeout = init.timeout || 30000;
            xhr.send(body || null);
          });
        };
      }
      const providerContext = (function() {
        const module = { exports: {} };
        const exports = module.exports;
        const require = globalThis.require;
        $contextCode
        return module.exports.providerContext || globalThis.providerContext || {
          axios: globalThis.axios,
          Aes: null,
          getBaseUrl: function(providerValue) {
            return fetch('https://himanshu8443.github.io/providers/modflix.json')
              .then(function(response) { return response.json(); })
              .then(function(data) { return data && data[providerValue] ? data[providerValue].url || '' : ''; })
              .catch(function() { return ''; });
          },
          commonHeaders: {
            'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36'
          },
          cheerio: globalThis.cheerio || {}
        };
      })();
    ''';
  }

  Future<List<dynamic>> _runJson(String code) async {
    final runtime = getJavascriptRuntime(
      xhr: true,
      extraArgs: {'stackSize': 8 * 1024 * 1024},
    );
    try {
      final result = await runtime.evaluateAsync(code);
      final decoded = jsonDecode(result.stringResult);
      return decoded is List ? decoded : const [];
    } finally {
      runtime.dispose();
    }
  }

  Future<List<dynamic>> _runJsonAsync(String code) async {
    final runtime = getJavascriptRuntime(
      xhr: true,
      extraArgs: {'stackSize': 8 * 1024 * 1024},
    );
    try {
      final result = await runtime.evaluateAsync(code);
      runtime.executePendingJob();
      final resolved = await runtime
          .handlePromise(result)
          .timeout(const Duration(seconds: 35));
      final decoded = jsonDecode(resolved.stringResult);
      return decoded is List ? decoded : const [];
    } finally {
      runtime.dispose();
    }
  }

  Future<Map<String, dynamic>> _runJsonObjectAsync(String code) async {
    final runtime = getJavascriptRuntime(
      xhr: true,
      extraArgs: {'stackSize': 8 * 1024 * 1024},
    );
    try {
      final result = await runtime.evaluateAsync(code);
      runtime.executePendingJob();
      final resolved = await runtime
          .handlePromise(result)
          .timeout(const Duration(seconds: 35));
      final decoded = jsonDecode(resolved.stringResult);
      return decoded is Map ? Map<String, dynamic>.from(decoded) : const {};
    } finally {
      runtime.dispose();
    }
  }

  List<SubtitleTrack> _subtitleTracksFromJson(Map<String, dynamic> map) {
    final raw =
        map['subtitles'] ??
        map['subtitle'] ??
        map['captions'] ??
        map['tracks'] ??
        map['subs'];
    if (raw is! List) return const [];
    return raw
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
          return SubtitleTrack(
            label: label.isEmpty ? language : label,
            language: language,
            url: (url ?? '').toString(),
          );
        })
        .where((track) => track.url.isNotEmpty)
        .toList();
  }
}

class ProviderCatalog {
  const ProviderCatalog({required this.title, required this.filter});

  final String title;
  final String filter;

  factory ProviderCatalog.fromJson(Map<String, dynamic> json) {
    return ProviderCatalog(
      title: (json['title'] ?? 'Browse').toString(),
      filter: (json['filter'] ?? '').toString(),
    );
  }
}

class ProviderPost {
  const ProviderPost({
    required this.title,
    required this.link,
    required this.image,
  });

  final String title;
  final String link;
  final String image;

  factory ProviderPost.fromJson(Map<String, dynamic> json) {
    return ProviderPost(
      title: (json['title'] ?? 'Untitled').toString(),
      link: (json['link'] ?? '').toString(),
      image: (json['image'] ?? '').toString(),
    );
  }
}

class ProviderMeta {
  const ProviderMeta({
    required this.title,
    required this.type,
    required this.linkList,
  });

  final String title;
  final String type;
  final List<ProviderMetaLink> linkList;

  factory ProviderMeta.fromJson(Map<String, dynamic> json) {
    return ProviderMeta(
      title: (json['title'] ?? '').toString(),
      type: (json['type'] ?? 'movie').toString(),
      linkList: ((json['linkList'] as List?) ?? const [])
          .whereType<Map>()
          .map(
            (item) =>
                ProviderMetaLink.fromJson(Map<String, dynamic>.from(item)),
          )
          .toList(),
    );
  }
}

class ProviderMetaLink {
  const ProviderMetaLink({
    required this.title,
    required this.quality,
    required this.episodesLink,
    required this.directLinks,
  });

  final String title;
  final String quality;
  final String episodesLink;
  final List<ProviderDirectLink> directLinks;

  factory ProviderMetaLink.fromJson(Map<String, dynamic> json) {
    return ProviderMetaLink(
      title: (json['title'] ?? '').toString(),
      quality: (json['quality'] ?? '').toString(),
      episodesLink: (json['episodesLink'] ?? '').toString(),
      directLinks: ((json['directLinks'] as List?) ?? const [])
          .whereType<Map>()
          .map(
            (item) =>
                ProviderDirectLink.fromJson(Map<String, dynamic>.from(item)),
          )
          .toList(),
    );
  }
}

class ProviderDirectLink {
  const ProviderDirectLink({required this.title, required this.link});

  final String title;
  final String link;

  factory ProviderDirectLink.fromJson(Map<String, dynamic> json) {
    return ProviderDirectLink(
      title: (json['title'] ?? '').toString(),
      link: (json['link'] ?? '').toString(),
    );
  }
}
