import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';
import '../../data/models/media_item.dart';
import '../../shared/widgets/focusable_scale.dart';
import '../../shared/widgets/wena_button.dart';
import '../player/player_screen.dart';
import 'provider_interface.dart';
import 'provider_js_bridge.dart';
import 'provider_manager_controller.dart';
import 'provider_stream_resolver.dart';

class SourcePickerScreen extends ConsumerStatefulWidget {
  const SourcePickerScreen({super.key, required this.item});

  final MediaItem? item;

  @override
  ConsumerState<SourcePickerScreen> createState() => _SourcePickerScreenState();
}

class _SourcePickerScreenState extends ConsumerState<SourcePickerScreen> {
  bool _loading = false;
  bool _autoStarted = false;
  String? _message;
  List<StreamSource> _streams = const [];

  Future<void> _installMultiStream() async {
    setState(() {
      _loading = true;
      _message = 'Preparing MultiStream...';
      _streams = const [];
    });
    try {
      final controller = ref.read(providerManagerProvider.notifier);
      var repos = ref.read(providerManagerProvider);
      if (!repos.any(
        (repo) => repo.availableProviders.any(
          (provider) => provider.value == 'autoEmbed',
        ),
      )) {
        await controller.addRepository('vega-org');
        repos = ref.read(providerManagerProvider);
      }

      final repo = repos.firstWhere(
        (repo) => repo.availableProviders.any(
          (provider) => provider.value == 'autoEmbed',
        ),
      );
      final multiStream = repo.availableProviders.firstWhere(
        (provider) => provider.value == 'autoEmbed',
      );
      if (!multiStream.installed) {
        await controller.installProvider(repo.sourceUrl, multiStream.value);
      }
      if (!mounted) return;
      await _resolve(multiStream.value, multiStream.displayName);
    } catch (error) {
      if (!mounted) return;
      setState(
        () => _message =
            'Could not install MultiStream. Open Provider Manager and refresh vega-org.',
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _resolve(String providerValue, String providerName) async {
    final item = widget.item;
    if (item == null) return;
    setState(() {
      _loading = true;
      _message = 'Checking $providerName...';
      _streams = const [];
    });
    try {
      final streams = await ref
          .read(providerStreamResolverProvider)
          .resolve(providerValue: providerValue, item: item);
      _applyStreams(streams, providerName);
    } catch (error) {
      setState(
        () => _message = error.toString().replaceFirst(
          'Unsupported operation: ',
          '',
        ),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _resolveInstalled(_InstalledProvider installed) async {
    final item = widget.item;
    if (item == null) return;
    setState(() {
      _loading = true;
      _message = 'Checking ${installed.displayName}...';
      _streams = const [];
    });
    try {
      final providerLink = item.sourceProvider == installed.value
          ? item.sourceLink
          : null;
      final streams = providerLink == null || providerLink.isEmpty
          ? await _resolveByProviderSearch(installed, item)
          : await ref
                .read(providerJsBridgeProvider)
                .getStreams(
                  sourceUrl: installed.sourceUrl,
                  providerValue: installed.value,
                  link: providerLink,
                  type: item.kind == MediaKind.tv ? 'series' : 'movie',
                );
      _applyStreams(streams, installed.displayName);
    } catch (error) {
      setState(
        () => _message = error.toString().replaceFirst(
          'Unsupported operation: ',
          '',
        ),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _autoResolveAll(List<_InstalledProvider> installed) async {
    final item = widget.item;
    if (item == null || installed.isEmpty || _loading) return;
    setState(() {
      _loading = true;
      _message = 'Searching installed providers...';
      _streams = const [];
    });

    final found = <String, StreamSource>{};
    var checked = 0;
    for (final provider in installed) {
      if (!mounted) return;
      checked += 1;
      setState(
        () => _message =
            'Searching ${provider.displayName} ($checked/${installed.length})...',
      );
      try {
        final providerLink = item.sourceProvider == provider.value
            ? item.sourceLink
            : null;
        final streams = providerLink == null || providerLink.isEmpty
            ? await _resolveByProviderSearch(provider, item)
            : await ref
                  .read(providerJsBridgeProvider)
                  .getStreams(
                    sourceUrl: provider.sourceUrl,
                    providerValue: provider.value,
                    link: providerLink,
                    type: item.kind == MediaKind.tv ? 'series' : 'movie',
                  )
                  .timeout(
                    const Duration(seconds: 45),
                    onTimeout: () => const [],
                  );
        for (final stream in streams) {
          found[stream.url] = stream;
        }
        if (found.isNotEmpty && mounted) {
          setState(() => _streams = found.values.toList());
        }
      } catch (_) {
        // Broken providers should not block the rest of the installed list.
      }
    }

    if (!mounted) return;
    setState(() {
      _loading = false;
      _streams = found.values.toList();
      _message = found.isEmpty
          ? 'No playable streams found from installed providers.'
          : '${found.length} playable streams found.';
    });
  }

  Future<List<StreamSource>> _resolveByProviderSearch(
    _InstalledProvider installed,
    MediaItem item,
  ) async {
    if (installed.value == 'autoEmbed') {
      return ref
          .read(providerStreamResolverProvider)
          .resolve(providerValue: installed.value, item: item);
    }

    final bridge = ref.read(providerJsBridgeProvider);
    setState(() => _message = 'Searching ${installed.displayName}...');
    final posts = await bridge
        .searchPosts(
          sourceUrl: installed.sourceUrl,
          providerValue: installed.value,
          query: item.title,
        )
        .timeout(const Duration(seconds: 40));
    if (posts.isEmpty) return const [];

    final candidate = _bestPostMatch(posts, item.title);
    setState(() => _message = 'Reading source links...');
    final meta = await bridge
        .getMeta(
          sourceUrl: installed.sourceUrl,
          providerValue: installed.value,
          link: candidate.link,
        )
        .timeout(const Duration(seconds: 40));
    if (meta == null) return const [];

    var directLinks = meta.linkList
        .expand((link) => link.directLinks)
        .where((link) => link.link.isNotEmpty)
        .take(4)
        .toList();
    if (directLinks.isEmpty) {
      final firstEpisodesLink = meta.linkList
          .map((link) => link.episodesLink)
          .where((link) => link.isNotEmpty)
          .firstOrNull;
      if (firstEpisodesLink != null) {
        setState(() => _message = 'Loading episodes...');
        directLinks = await bridge
            .getEpisodes(
              sourceUrl: installed.sourceUrl,
              providerValue: installed.value,
              episodesLink: firstEpisodesLink,
            )
            .timeout(const Duration(seconds: 40), onTimeout: () => const [])
            .then((items) => items.take(4).toList());
      }
    }
    if (directLinks.isEmpty) return const [];

    setState(() => _message = 'Resolving HLS/MP4 streams...');
    final resolved = await Future.wait([
      for (final direct in directLinks)
        bridge
            .getStreams(
              sourceUrl: installed.sourceUrl,
              providerValue: installed.value,
              link: direct.link,
              type: meta.type.isEmpty ? 'movie' : meta.type,
            )
            .timeout(const Duration(seconds: 45), onTimeout: () => const []),
    ]);
    final unique = <String, StreamSource>{};
    for (final stream in resolved.expand((items) => items)) {
      unique[stream.url] = stream;
    }
    return unique.values.toList();
  }

  ProviderPost _bestPostMatch(List<ProviderPost> posts, String title) {
    final normalized = _normalize(title);
    return posts.firstWhere(
      (post) => _normalize(post.title).contains(normalized),
      orElse: () => posts.first,
    );
  }

  String _normalize(String value) {
    return value
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  void _applyStreams(List<StreamSource> streams, String providerName) {
    setState(() {
      _streams = streams;
      _message = streams.isEmpty
          ? 'No playable streams found from $providerName.'
          : '${streams.length} streams found from $providerName.';
    });
  }

  @override
  Widget build(BuildContext context) {
    final repos = ref.watch(providerManagerProvider);
    final installed = repos
        .where((repo) => repo.enabled)
        .expand(
          (repo) => repo.availableProviders
              .where((provider) => provider.installed)
              .map(
                (provider) => _InstalledProvider(
                  sourceUrl: repo.sourceUrl,
                  value: provider.value,
                  displayName: provider.displayName,
                  type: provider.type,
                ),
              ),
        )
        .toList();
    final hasDirectProvider = installed.any(
      (provider) => provider.value == 'autoEmbed',
    );
    final item = widget.item;
    if (!_autoStarted && installed.isNotEmpty && item != null) {
      _autoStarted = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _autoResolveAll(installed);
      });
    }

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(54, 34, 54, 30),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              WenaButton(
                label: 'Back',
                icon: Icons.arrow_back,
                onPressed: () => context.pop(),
              ),
              const SizedBox(height: 24),
              Text(
                item == null
                    ? 'Choose Source'
                    : 'Choose Source for ${item.title}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.headlineLarge,
              ),
              const SizedBox(height: 8),
              const Text(
                'Searching installed providers automatically. Select a stream below when results appear.',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: Colors.white70, fontSize: 16),
              ),
              if (_message != null) ...[
                const SizedBox(height: 14),
                Text(
                  _message!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white),
                ),
              ],
              if (!hasDirectProvider) ...[
                const SizedBox(height: 16),
                WenaButton(
                  label: 'Install MultiStream',
                  icon: Icons.download,
                  primary: true,
                  onPressed: _loading ? () {} : _installMultiStream,
                ),
              ],
              const SizedBox(height: 20),
              Expanded(
                child: installed.isEmpty
                    ? _EmptyProviders(
                        onOpenSettings: () => context.go('/settings'),
                      )
                    : Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            width: 350,
                            child: ListView.separated(
                              itemCount: installed.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 12),
                              itemBuilder: (context, index) {
                                final provider = installed[index];
                                final supported = provider.value == 'autoEmbed';
                                return FocusableScale(
                                  onPressed: _loading
                                      ? () {}
                                      : () => _resolveInstalled(provider),
                                  child: Container(
                                    height: 78,
                                    padding: const EdgeInsets.all(14),
                                    color: WenaTheme.surface,
                                    child: Row(
                                      children: [
                                        Icon(
                                          supported
                                              ? Icons.play_circle
                                              : Icons.extension,
                                          color: supported
                                              ? WenaTheme.red
                                              : Colors.white54,
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            mainAxisAlignment:
                                                MainAxisAlignment.center,
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                provider.displayName,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.w800,
                                                ),
                                              ),
                                              Text(
                                                supported
                                                    ? 'direct resolver'
                                                    : '${provider.type} | JS runtime',
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(
                                                  color: Colors.white60,
                                                  fontSize: 12,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                          const SizedBox(width: 24),
                          Expanded(
                            child: _loading
                                ? _SearchingStreams(
                                    streams: _streams,
                                    item: item,
                                  )
                                : _StreamList(item: item, streams: _streams),
                          ),
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InstalledProvider {
  const _InstalledProvider({
    required this.sourceUrl,
    required this.value,
    required this.displayName,
    required this.type,
  });

  final String sourceUrl;
  final String value;
  final String displayName;
  final String type;
}

class _SearchingStreams extends StatelessWidget {
  const _SearchingStreams({required this.streams, required this.item});

  final List<StreamSource> streams;
  final MediaItem? item;

  @override
  Widget build(BuildContext context) {
    if (streams.isNotEmpty) return _StreamList(item: item, streams: streams);
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(color: WenaTheme.red),
          SizedBox(height: 16),
          Text(
            'Searching for HLS, MP4, and MKV streams...',
            style: TextStyle(color: Colors.white70),
          ),
        ],
      ),
    );
  }
}

class _StreamList extends StatelessWidget {
  const _StreamList({required this.item, required this.streams});

  final MediaItem? item;
  final List<StreamSource> streams;

  @override
  Widget build(BuildContext context) {
    if (streams.isEmpty) {
      return const Center(
        child: Text(
          'Streams will appear here as providers respond.',
          style: TextStyle(color: Colors.white70),
        ),
      );
    }

    return ListView.separated(
      itemCount: streams.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final stream = streams[index];
        return FocusableScale(
          onPressed: () => context.push(
            '/player',
            extra: PlayerPayload(
              title: item?.title ?? 'WenaTV',
              streamUrl: stream.url,
              headers: stream.headers,
            ),
          ),
          child: Container(
            height: 72,
            padding: const EdgeInsets.symmetric(horizontal: 18),
            color: WenaTheme.surface,
            child: Row(
              children: [
                const Icon(Icons.play_arrow, color: WenaTheme.red),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    '${stream.quality} | ${stream.format.toUpperCase()}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
                const Icon(Icons.chevron_right),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _EmptyProviders extends StatelessWidget {
  const _EmptyProviders({required this.onOpenSettings});

  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.extension_off, size: 48, color: Colors.white54),
          const SizedBox(height: 16),
          const Text('No downloaded providers are installed.'),
          const SizedBox(height: 18),
          WenaButton(
            label: 'Provider Manager',
            icon: Icons.settings,
            primary: true,
            onPressed: onOpenSettings,
          ),
        ],
      ),
    );
  }
}
