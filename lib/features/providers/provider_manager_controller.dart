import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../../data/models/provider_repository.dart';

final providerManagerProvider =
    NotifierProvider<ProviderManagerController, List<ProviderRepositoryModel>>(
      ProviderManagerController.new,
    );

final activeProviderProvider = Provider<ActiveProviderSelection?>((ref) {
  ref.watch(providerManagerProvider);
  return ref.read(providerManagerProvider.notifier).activeProvider();
});

final providerFallbackOrderProvider = Provider<List<ActiveProviderSelection>>((
  ref,
) {
  ref.watch(providerManagerProvider);
  return ref.read(providerManagerProvider.notifier).providerFallbackOrder();
});

class ActiveProviderSelection {
  const ActiveProviderSelection({
    required this.sourceUrl,
    required this.value,
    required this.displayName,
    required this.type,
  });

  final String sourceUrl;
  final String value;
  final String displayName;
  final String type;

  String get key => '$sourceUrl::$value';
}

class ProviderManagerController
    extends Notifier<List<ProviderRepositoryModel>> {
  static const _moduleBoxKey = 'provider_modules';
  static const _repositoryBoxKey = 'provider_repositories';
  static const _activeProviderBoxKey = 'active_provider';

  final _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 5),
      receiveTimeout: const Duration(seconds: 6),
      followRedirects: true,
    ),
  );

  @override
  List<ProviderRepositoryModel> build() => _loadRepositories();

  Future<void> addRepository(String input) async {
    final source = normalizeRepository(input);
    if (source.sourceUrl.isEmpty ||
        state.any((repo) => repo.sourceUrl == source.sourceUrl)) {
      return;
    }
    state = [
      ...state,
      ProviderRepositoryModel(
        url: source.displayUrl,
        sourceUrl: source.sourceUrl,
        name: source.author,
        version: 'checking',
        lastUpdated: DateTime.now(),
        status: ProviderStatus.idle,
      ),
    ];
    await _saveRepositories();
    await refresh(source.sourceUrl);
  }

  Future<void> refresh(String sourceUrl) async {
    state = [
      for (final repo in state)
        if (repo.sourceUrl == sourceUrl)
          repo.copyWith(
            version: 'checking',
            lastUpdated: DateTime.now(),
            status: ProviderStatus.idle,
          )
        else
          repo,
    ];
    await _saveRepositories();
    final validation = await _fetchManifest(sourceUrl);
    state = [
      for (final repo in state)
        if (repo.sourceUrl == sourceUrl)
          repo.copyWith(
            version: validation.$2,
            lastUpdated: DateTime.now(),
            status: validation.$1,
            availableProviders: validation.$3,
            installedCount: validation.$3
                .where((provider) => provider.installed)
                .length,
            enabled: validation.$1 == ProviderStatus.valid,
          )
        else
          repo,
    ];
    await _saveRepositories();
  }

  Future<void> toggle(String url) async {
    state = [
      for (final repo in state)
        repo.url == url ? repo.copyWith(enabled: !repo.enabled) : repo,
    ];
    await _ensureActiveProvider();
    await _saveRepositories();
  }

  Future<void> remove(String url) async {
    state = state
        .where((repo) => repo.url != url && repo.sourceUrl != url)
        .toList();
    final box = Hive.box('wenatv_cache');
    final activeKey = box.get(_activeProviderBoxKey)?.toString();
    if (activeKey != null && activeKey.startsWith('$url::')) {
      await box.delete(_activeProviderBoxKey);
    }
    await _ensureActiveProvider();
    await _saveRepositories();
  }

  ProviderSourceInfo normalizeRepository(String input) {
    final clean = input.trim();
    if (clean.isEmpty) {
      return const ProviderSourceInfo.empty();
    }
    final raw = _parseSource(clean);
    if (raw != null) {
      return raw;
    }
    final author = clean.replaceFirst('@', '');
    return ProviderSourceInfo(
      author: author,
      displayUrl: 'https://github.com/$author/vega-providers',
      sourceUrl:
          'https://raw.githubusercontent.com/$author/vega-providers/refs/heads/main',
    );
  }

  Future<void> installProvider(String sourceUrl, String providerValue) async {
    final repo = state.firstWhere((repo) => repo.sourceUrl == sourceUrl);
    final provider = repo.availableProviders.firstWhere(
      (provider) => provider.value == providerValue,
    );
    final requiredFiles = ['posts', 'meta', 'stream', 'catalog'];
    final optionalFiles = ['episodes'];
    final modules = <String, String>{};

    await Future.wait([
      for (final file in [...requiredFiles, ...optionalFiles])
        _downloadModule(sourceUrl, provider.value, file).then((content) {
          if (content != null && content.isNotEmpty) modules[file] = content;
        }),
    ]);
    final providerContext = await _downloadProviderContext(sourceUrl);

    final missing = requiredFiles
        .where((file) => modules[file] == null)
        .toList();
    if (missing.isNotEmpty) {
      throw StateError('Missing provider modules: ${missing.join(', ')}');
    }
    final compatibility = _compatibilityFor(modules);

    final box = Hive.box('wenatv_cache');
    final cache = Map<String, dynamic>.from(
      (box.get(_moduleBoxKey) as Map?) ?? const {},
    );
    cache['$sourceUrl::${provider.value}'] = {
      'value': provider.value,
      'display_name': provider.displayName,
      'version': provider.version,
      'cached_at': DateTime.now().toIso8601String(),
      'modules': modules,
      if (providerContext != null && providerContext.isNotEmpty)
        'provider_context': providerContext,
    };
    await box.put(_moduleBoxKey, cache);

    state = [
      for (final item in state)
        if (item.sourceUrl == sourceUrl)
          item.copyWith(
            availableProviders: [
              for (final available in item.availableProviders)
                available.value == provider.value
                    ? available.copyWith(
                        installed: true,
                        compatibility: compatibility.$1,
                        compatibilityMessage: compatibility.$2,
                      )
                    : available,
            ],
            installedCount: item.installedCount + 1,
            enabled: true,
          )
        else
          item,
    ];
    await _ensureActiveProvider(preferredKey: '$sourceUrl::${provider.value}');
    await _saveRepositories();
  }

  List<ProviderExtensionModel> installedProviders() {
    return state
        .where((repo) => repo.enabled)
        .expand(
          (repo) =>
              repo.availableProviders.where((provider) => provider.installed),
        )
        .toList();
  }

  List<ActiveProviderSelection> installedProviderSelections() {
    return state
        .where((repo) => repo.enabled)
        .expand(
          (repo) => repo.availableProviders
              .where(
                (provider) =>
                    provider.installed &&
                    !provider.disabled &&
                    provider.value != 'autoEmbed',
              )
              .map(
                (provider) => ActiveProviderSelection(
                  sourceUrl: repo.sourceUrl,
                  value: provider.value,
                  displayName: provider.displayName,
                  type: provider.type,
                ),
              ),
        )
        .toList();
  }

  List<ActiveProviderSelection> providerFallbackOrder({
    List<String> priority = const ['vega', 'autoEmbed', 'flixhq', 'showbox'],
  }) {
    final installed = installedProviderSelections();
    final byValue = {
      for (final provider in installed) provider.value.toLowerCase(): provider,
    };
    final ordered = <ActiveProviderSelection>[];

    void add(String value) {
      final normalized = value.toLowerCase();
      if (ordered.any(
        (provider) => provider.value.toLowerCase() == normalized,
      )) {
        return;
      }
      if (normalized == 'autoembed') {
        ordered.add(
          const ActiveProviderSelection(
            sourceUrl: 'autoEmbed',
            value: 'autoEmbed',
            displayName: 'MultiStream',
            type: 'global',
          ),
        );
        return;
      }
      final installedProvider = byValue[normalized];
      if (installedProvider != null) ordered.add(installedProvider);
    }

    for (final value in priority) {
      add(value);
    }
    for (final provider in installed) {
      add(provider.value);
    }
    return ordered;
  }

  ActiveProviderSelection? activeProvider() {
    final installed = installedProviderSelections();
    if (installed.isEmpty) return null;
    final box = Hive.box('wenatv_cache');
    final activeKey = box.get(_activeProviderBoxKey)?.toString();
    if (activeKey != null) {
      for (final provider in installed) {
        if (provider.key == activeKey) return provider;
      }
    }
    return installed.first;
  }

  Future<void> setActiveProvider(String sourceUrl, String providerValue) async {
    final selection = installedProviderSelections().where(
      (provider) =>
          provider.sourceUrl == sourceUrl && provider.value == providerValue,
    );
    if (selection.isEmpty) return;
    final box = Hive.box('wenatv_cache');
    await box.put(_activeProviderBoxKey, '$sourceUrl::$providerValue');
    state = [...state];
  }

  Future<String?> _downloadModule(
    String sourceUrl,
    String providerValue,
    String file,
  ) async {
    try {
      final response = await _dio.get<String>(
        '$sourceUrl/dist/$providerValue/$file.js',
        options: Options(responseType: ResponseType.plain),
      );
      return response.data;
    } catch (_) {
      return null;
    }
  }

  (String, String) _compatibilityFor(Map<String, String> modules) {
    final catalog = _hasAnyExport(modules['catalog'], ['catalog', 'Catalog']);
    final posts = _hasAnyExport(modules['posts'], [
      'getPosts',
      'GetHomePosts',
      'getSearchPosts',
      'GetSearchPosts',
    ]);
    final meta = _hasAnyExport(modules['meta'], ['getMeta', 'GetMetaData']);
    final stream = _hasAnyExport(modules['stream'], ['getStream', 'GetStream']);
    final episodes =
        modules['episodes'] == null ||
        _hasAnyExport(modules['episodes'], ['getEpisodes', 'GetEpisodeLinks']);
    if (catalog && posts && meta && stream && episodes) {
      return ('playable', 'Catalog, metadata, streams, and episodes ready');
    }
    if (posts && meta && stream) {
      return ('playable', 'Search, metadata, and streams ready');
    }
    if (catalog || posts) {
      return ('catalog', 'Catalog/search ready; stream adapter may be needed');
    }
    return ('needs adapter', 'Installed, but module exports need an adapter');
  }

  bool _hasAnyExport(String? source, List<String> names) {
    if (source == null || source.isEmpty) return false;
    return names.any(
      (name) =>
          source.contains(name) ||
          source.contains('"$name"') ||
          source.contains("'$name'"),
    );
  }

  Future<String?> _downloadProviderContext(String sourceUrl) async {
    try {
      final response = await _dio.get<String>(
        '$sourceUrl/dist/providerContext.js',
        options: Options(responseType: ResponseType.plain),
      );
      return response.data;
    } catch (_) {
      return null;
    }
  }

  Future<(ProviderStatus, String, List<ProviderExtensionModel>)> _fetchManifest(
    String sourceUrl,
  ) async {
    final manifestUrl = '$sourceUrl/manifest.json';
    try {
      final response = await _dio.get<String>(
        manifestUrl,
        options: Options(
          responseType: ResponseType.plain,
          headers: {'Accept': 'application/json,text/plain,*/*'},
        ),
      );
      final decoded = jsonDecode(response.data ?? '[]');
      final manifest = decoded is List
          ? decoded
          : decoded is Map
          ? ((decoded['value'] as List?) ?? const [])
          : const [];
      if (manifest.isEmpty) {
        return (
          ProviderStatus.invalid,
          decoded is Map || decoded is List
              ? 'empty manifest'
              : 'invalid manifest',
          const <ProviderExtensionModel>[],
        );
      }
      final installedKeys = _installedKeys();
      final providers = manifest
          .whereType<Map>()
          .map(
            (item) => ProviderExtensionModel.fromJson(
              Map<String, dynamic>.from(item),
            ),
          )
          .where((provider) => provider.value.isNotEmpty)
          .map(
            (provider) => provider.copyWith(
              installed: installedKeys.contains(
                '$sourceUrl::${provider.value}',
              ),
            ),
          )
          .toList();
      if (providers.isEmpty) {
        return (ProviderStatus.invalid, 'empty manifest', providers);
      }
      return (ProviderStatus.valid, '${providers.length} providers', providers);
    } catch (_) {
      return (
        ProviderStatus.unhealthy,
        'manifest unavailable',
        const <ProviderExtensionModel>[],
      );
    }
  }

  Set<String> _installedKeys() {
    final box = Hive.box('wenatv_cache');
    final cache = Map<String, dynamic>.from(
      (box.get(_moduleBoxKey) as Map?) ?? const {},
    );
    return cache.keys.toSet();
  }

  List<ProviderRepositoryModel> _loadRepositories() {
    final box = Hive.box('wenatv_cache');
    final cache = (box.get(_repositoryBoxKey) as List?) ?? const [];
    return cache
        .whereType<Map>()
        .map(
          (repo) =>
              ProviderRepositoryModel.fromJson(Map<String, dynamic>.from(repo)),
        )
        .where((repo) => repo.sourceUrl.isNotEmpty)
        .toList();
  }

  Future<void> _saveRepositories() async {
    final box = Hive.box('wenatv_cache');
    await box.put(_repositoryBoxKey, [for (final repo in state) repo.toJson()]);
  }

  Future<void> _ensureActiveProvider({String? preferredKey}) async {
    final box = Hive.box('wenatv_cache');
    final installed = installedProviderSelections();
    if (installed.isEmpty) {
      await box.delete(_activeProviderBoxKey);
      return;
    }
    final activeKey = box.get(_activeProviderBoxKey)?.toString();
    final preferred = preferredKey == null
        ? null
        : installed.where((provider) => provider.key == preferredKey);
    if (preferred != null && preferred.isNotEmpty) {
      await box.put(_activeProviderBoxKey, preferred.first.key);
      return;
    }
    if (activeKey != null &&
        installed.any((provider) => provider.key == activeKey)) {
      return;
    }
    await box.put(_activeProviderBoxKey, installed.first.key);
  }

  ProviderSourceInfo? _parseSource(String input) {
    final uri = Uri.tryParse(input);
    if (uri == null || !uri.hasScheme) return null;

    if (uri.host == 'raw.githubusercontent.com' &&
        uri.pathSegments.length >= 4) {
      final author = uri.pathSegments[0];
      final repo = uri.pathSegments[1];
      final branch =
          uri.pathSegments[2] == 'refs' &&
              uri.pathSegments.length >= 5 &&
              uri.pathSegments[3] == 'heads'
          ? uri.pathSegments.sublist(4).join('/')
          : uri.pathSegments[2];
      return ProviderSourceInfo(
        author: author,
        displayUrl: 'https://github.com/$author/$repo',
        sourceUrl:
            'https://raw.githubusercontent.com/$author/$repo/refs/heads/$branch',
      );
    }

    if (uri.host == 'github.com' && uri.pathSegments.length >= 2) {
      final author = uri.pathSegments[0];
      final repo = uri.pathSegments[1];
      final branch =
          uri.pathSegments.length >= 4 && uri.pathSegments[2] == 'tree'
          ? uri.pathSegments.sublist(3).join('/')
          : 'main';
      return ProviderSourceInfo(
        author: author,
        displayUrl: 'https://github.com/$author/$repo',
        sourceUrl:
            'https://raw.githubusercontent.com/$author/$repo/refs/heads/$branch',
      );
    }

    return null;
  }
}

class ProviderSourceInfo {
  const ProviderSourceInfo({
    required this.author,
    required this.displayUrl,
    required this.sourceUrl,
  });

  const ProviderSourceInfo.empty()
    : author = '',
      displayUrl = '',
      sourceUrl = '';

  final String author;
  final String displayUrl;
  final String sourceUrl;
}
