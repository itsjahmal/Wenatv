import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart';

import '../../core/theme/app_theme.dart';
import '../../data/models/media_item.dart';
import '../../data/repositories/tmdb_repository.dart';
import '../../shared/widgets/focusable_scale.dart';

final _trailerKeyProvider =
    FutureProvider.family<String?, ({int id, MediaKind kind})>((ref, args) {
      return ref.watch(tmdbRepositoryProvider).trailerKey(args.id, args.kind);
    });

class TrailerScreen extends ConsumerWidget {
  const TrailerScreen({
    super.key,
    required this.id,
    required this.kind,
    required this.title,
  });

  final int id;
  final MediaKind kind;
  final String title;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final trailer = ref.watch(_trailerKeyProvider((id: id, kind: kind)));
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (context.canPop()) {
          context.pop();
        } else {
          context.go('/');
        }
      },
      child: Scaffold(
        backgroundColor: WenaTheme.black,
        body: trailer.when(
          loading: () => _TrailerShell(
            title: title,
            child: const Center(
              child: CircularProgressIndicator(color: WenaTheme.red),
            ),
          ),
          error: (_, __) => _TrailerMessage(
            title: title,
            message: 'Trailer could not be loaded right now.',
          ),
          data: (videoId) {
            if (videoId == null || videoId.isEmpty) {
              return _TrailerMessage(
                title: title,
                message: 'No playable trailer is available for this title.',
              );
            }
            return _TrailerPlayer(title: title, videoId: videoId);
          },
        ),
      ),
    );
  }
}

class _TrailerPlayer extends StatefulWidget {
  const _TrailerPlayer({required this.title, required this.videoId});

  final String title;
  final String videoId;

  @override
  State<_TrailerPlayer> createState() => _TrailerPlayerState();
}

class _TrailerPlayerState extends State<_TrailerPlayer> {
  late final YoutubePlayerController _controller;
  final _focusNode = FocusNode(debugLabel: 'trailer-root');
  bool _error = false;

  @override
  void initState() {
    super.initState();
    _controller = YoutubePlayerController.fromVideoId(
      videoId: widget.videoId,
      autoPlay: true,
      params: const YoutubePlayerParams(
        mute: false,
        loop: false,
        showControls: true,
        showFullscreenButton: false,
        enableCaption: true,
        strictRelatedVideos: true,
      ),
    );
    _controller.listen((event) {
      if (!mounted) return;
      if (event.error != YoutubeError.none && !_error) {
        setState(() => _error = true);
      }
    });
  }

  @override
  void dispose() {
    _controller.close();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _seekRelative(double offsetSeconds) async {
    final current = await _controller.currentTime;
    final target = (current + offsetSeconds).clamp(0.0, double.infinity);
    await _controller.seekTo(seconds: target, allowSeekAhead: true);
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    switch (event.logicalKey) {
      case LogicalKeyboardKey.goBack:
      case LogicalKeyboardKey.escape:
        context.pop();
        return KeyEventResult.handled;
      case LogicalKeyboardKey.select:
      case LogicalKeyboardKey.enter:
        // Toggle play/pause via the iframe API
        _controller.value.playerState == PlayerState.playing
            ? _controller.pauseVideo()
            : _controller.playVideo();
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowLeft:
        unawaited(_seekRelative(-10));
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowRight:
        unawaited(_seekRelative(10));
        return KeyEventResult.handled;
      default:
        return KeyEventResult.ignored;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: _onKey,
      child: _TrailerShell(
        title: widget.title,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Center(
              child: AspectRatio(
                aspectRatio: 16 / 9,
                child: YoutubePlayerScaffold(
                  controller: _controller,
                  builder: (context, player) => player,
                ),
              ),
            ),
            if (_error) const _TrailerErrorOverlay(),
          ],
        ),
      ),
    );
  }
}

class _TrailerShell extends StatelessWidget {
  const _TrailerShell({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final inset = TvLayout.horizontalInset(size);
    return Stack(
      fit: StackFit.expand,
      children: [
        child,
        Positioned(
          left: inset,
          top: 22,
          right: inset,
          child: Row(
            children: [
              FocusableScale(
                autofocus: true,
                borderRadius: 999,
                scale: 1.025,
                onPressed: () => context.pop(),
                child: Container(
                  height: 38,
                  padding: const EdgeInsets.symmetric(horizontal: 15),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: .62),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: Colors.white24),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.arrow_back, color: Colors.white, size: 18),
                      SizedBox(width: 7),
                      Text(
                        'Back',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    shadows: [Shadow(color: Colors.black, blurRadius: 12)],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _TrailerMessage extends StatelessWidget {
  const _TrailerMessage({required this.title, required this.message});

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return _TrailerShell(
      title: title,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.movie_filter_outlined,
                color: WenaTheme.red,
                size: 42,
              ),
              const SizedBox(height: 14),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 18),
              FocusableScale(
                autofocus: true,
                borderRadius: 999,
                scale: 1.025,
                onPressed: () => context.pop(),
                child: Container(
                  height: 40,
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  decoration: BoxDecoration(
                    color: WenaTheme.red,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  alignment: Alignment.center,
                  child: const Text(
                    'Back',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TrailerErrorOverlay extends StatelessWidget {
  const _TrailerErrorOverlay();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black.withValues(alpha: .68),
      alignment: Alignment.center,
      child: const Text(
        'Trailer playback failed. Try again later.',
        style: TextStyle(
          color: Colors.white,
          fontSize: 18,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}
