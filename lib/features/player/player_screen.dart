import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:video_player/video_player.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../core/theme/app_theme.dart';

typedef EpisodeStreamResolver =
    Future<PlayerResolvedStream?> Function(int season, int episode);
typedef EpisodeMetadataResolver =
    Future<List<PlayerEpisodePayload>> Function(int season);

class PlayerResolvedStream {
  const PlayerResolvedStream({
    required this.url,
    this.headers = const {},
    this.subtitles = const [],
    this.providerName,
    this.quality,
    this.format,
    this.language,
    this.fileSize,
    this.label,
    this.displayTitle,
  });

  final String url;
  final Map<String, String> headers;
  final List<PlayerSubtitlePayload> subtitles;
  final String? providerName;
  final String? quality;
  final String? format;
  final String? language;
  final String? fileSize;
  final String? label;
  final String? displayTitle;
}

class PlayerSubtitlePayload {
  const PlayerSubtitlePayload({
    required this.id,
    required this.label,
    required this.url,
    this.language,
  });

  final String id;
  final String label;
  final String url;
  final String? language;
}

class PlayerEpisodePayload {
  const PlayerEpisodePayload({
    required this.season,
    required this.episode,
    required this.title,
    this.runtime,
    this.overview,
    this.artworkUrl,
  });

  final int season;
  final int episode;
  final String title;
  final int? runtime;
  final String? overview;
  final String? artworkUrl;
}

class PlayerPayload {
  const PlayerPayload({
    required this.title,
    this.episodeTitle,
    this.streamUrl,
    this.headers = const {},
    this.isSeries = false,
    this.artworkUrl,
    this.overview,
    this.year,
    this.genres = const [],
    this.runtime,
    this.season,
    this.episode,
    this.totalSeasons,
    this.episodes = const [],
    this.episodeStreamResolver,
    this.episodeMetadataResolver,
    this.subtitles = const [],
    this.currentStream,
    this.fallbackStreams = const [],
  });

  final String title;
  final String? episodeTitle;
  final String? streamUrl;
  final Map<String, String> headers;
  final bool isSeries;
  final String? artworkUrl;
  final String? overview;
  final String? year;
  final List<String> genres;
  final int? runtime;
  final int? season;
  final int? episode;
  final int? totalSeasons;
  final List<PlayerEpisodePayload> episodes;
  final EpisodeStreamResolver? episodeStreamResolver;
  final EpisodeMetadataResolver? episodeMetadataResolver;
  final List<PlayerSubtitlePayload> subtitles;
  final PlayerResolvedStream? currentStream;
  final List<PlayerResolvedStream> fallbackStreams;

  PlayerPayload copyWith({
    String? title,
    String? episodeTitle,
    String? streamUrl,
    Map<String, String>? headers,
    bool? isSeries,
    String? artworkUrl,
    String? overview,
    String? year,
    List<String>? genres,
    int? runtime,
    int? season,
    int? episode,
    int? totalSeasons,
    List<PlayerEpisodePayload>? episodes,
    EpisodeStreamResolver? episodeStreamResolver,
    EpisodeMetadataResolver? episodeMetadataResolver,
    List<PlayerSubtitlePayload>? subtitles,
    PlayerResolvedStream? currentStream,
    List<PlayerResolvedStream>? fallbackStreams,
  }) {
    return PlayerPayload(
      title: title ?? this.title,
      episodeTitle: episodeTitle ?? this.episodeTitle,
      streamUrl: streamUrl ?? this.streamUrl,
      headers: headers ?? this.headers,
      isSeries: isSeries ?? this.isSeries,
      artworkUrl: artworkUrl ?? this.artworkUrl,
      overview: overview ?? this.overview,
      year: year ?? this.year,
      genres: genres ?? this.genres,
      runtime: runtime ?? this.runtime,
      season: season ?? this.season,
      episode: episode ?? this.episode,
      totalSeasons: totalSeasons ?? this.totalSeasons,
      episodes: episodes ?? this.episodes,
      episodeStreamResolver:
          episodeStreamResolver ?? this.episodeStreamResolver,
      episodeMetadataResolver:
          episodeMetadataResolver ?? this.episodeMetadataResolver,
      subtitles: subtitles ?? this.subtitles,
      currentStream: currentStream ?? this.currentStream,
      fallbackStreams: fallbackStreams ?? this.fallbackStreams,
    );
  }
}

class PlayerScreen extends StatefulWidget {
  const PlayerScreen({super.key, this.payload});

  final PlayerPayload? payload;

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen>
    with WidgetsBindingObserver {
  VideoPlayerController? _controller;
  final _rootFocusNode = FocusNode(debugLabel: 'player-root');
  final _progressFocusNode = FocusNode(debugLabel: 'player-progress');
  final _audioFocusNode = FocusNode(debugLabel: 'player-audio');
  final _subtitlesFocusNode = FocusNode(debugLabel: 'player-subtitles');
  final _qualityFocusNode = FocusNode(debugLabel: 'player-quality');
  final _episodesFocusNode = FocusNode(debugLabel: 'player-episodes');

  bool _controlsVisible = true;
  bool _initializing = true;
  bool _episodePanelVisible = false;
  bool _playing = false;
  bool _buffering = false;
  String? _error;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _audioTrackSupport = false;
  List<VideoAudioTrack> _audioTracks = const [];
  String? _selectedAudioTrackId;
  List<PlayerSubtitlePayload> _subtitleTracks = const [];
  String _selectedSubtitleId = 'off';
  PlayerPayload? _activePayload;
  Timer? _hideTimer;
  bool _handlingPlaybackFailure = false;
  bool _englishAudioApplied = false;
  bool _keepAwakeEnabled = false;
  LogicalKeyboardKey? _lastSeekKey;
  int _seekRepeatCount = 0;
  DateTime _lastSeekAt = DateTime.fromMillisecondsSinceEpoch(0);

  bool get _isSeries =>
      _activePayload?.isSeries == true || _activePayload?.episodeTitle != null;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _activePayload = widget.payload;
    final url = _activePayload?.streamUrl;
    if (url == null || url.isEmpty) {
      _initializing = false;
    } else {
      unawaited(_open(url, headers: _activePayload?.headers));
    }
    unawaited(_ensureEpisodesLoaded());
    _scheduleHide();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _progressFocusNode.requestFocus();
    });
  }

  Future<void> _open(
    String url, {
    Map<String, String>? headers,
    PlayerPayload? payload,
  }) async {
    await _setKeepAwake(false);
    setState(() {
      _initializing = true;
      _error = null;
      _audioTrackSupport = false;
      _audioTracks = const [];
      _selectedAudioTrackId = null;
      _englishAudioApplied = false;
      _subtitleTracks =
          payload?.subtitles ?? _activePayload?.subtitles ?? const [];
      _selectedSubtitleId = 'off';
      if (payload != null) _activePayload = payload;
    });
    final previous = _controller;
    _controller = null;
    await previous?.dispose();
    final controller = VideoPlayerController.networkUrl(
      Uri.parse(url),
      httpHeaders: _normalizedHeaders(headers),
      videoPlayerOptions: VideoPlayerOptions(mixWithOthers: false),
    );
    controller.addListener(_onVideoChanged);

    try {
      await controller.initialize().timeout(const Duration(seconds: 22));
      await controller.play();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() {
        _controller = controller;
        _initializing = false;
        _playing = controller.value.isPlaying;
        _position = controller.value.position;
        _duration = controller.value.duration;
      });
      unawaited(_syncKeepAwake(controller.value));
      await _refreshAudioTracks(preferEnglish: true);
      unawaited(_ensureEpisodesLoaded());
      unawaited(
        Future<void>.delayed(
          const Duration(seconds: 1),
          () => _refreshAudioTracks(preferEnglish: true),
        ),
      );
      unawaited(
        Future<void>.delayed(
          const Duration(seconds: 3),
          () => _refreshAudioTracks(preferEnglish: true),
        ),
      );
    } catch (error) {
      controller.removeListener(_onVideoChanged);
      await controller.dispose();
      if (!mounted) return;
      await _setKeepAwake(false);
      await _handlePlaybackFailure(error.toString());
    }
  }

  void _onVideoChanged() {
    final value = _controller?.value;
    if (!mounted || value == null) return;
    if (value.hasError && _error == null) {
      unawaited(_setKeepAwake(false));
      unawaited(_handlePlaybackFailure(value.errorDescription));
      return;
    }
    setState(() {
      _playing = value.isPlaying;
      _buffering = value.isBuffering;
      _position = value.position;
      _duration = value.duration;
    });
    unawaited(_syncKeepAwake(value));
  }

  Future<void> _handlePlaybackFailure(String? reason) async {
    if (_handlingPlaybackFailure) return;
    _handlingPlaybackFailure = true;
    try {
      final fallback = _nextFallbackStream();
      if (fallback != null) {
        final nextPayload = _activePayload?.copyWith(
          streamUrl: fallback.url,
          headers: fallback.headers,
          subtitles: fallback.subtitles,
          currentStream: fallback,
          fallbackStreams: _remainingFallbacksAfter(fallback.url),
        );
        _handlingPlaybackFailure = false;
        await _open(
          fallback.url,
          headers: fallback.headers,
          payload: nextPayload,
        );
        return;
      }
      if (!mounted) return;
      setState(() {
        _initializing = false;
        _error =
            'Failed to open stream. Try another source or quality. ${reason ?? 'Playback failed.'}';
      });
      await _setKeepAwake(false);
    } finally {
      _handlingPlaybackFailure = false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      final value = _controller?.value;
      if (value != null) unawaited(_syncKeepAwake(value));
      return;
    }
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached ||
        state == AppLifecycleState.hidden) {
      unawaited(_setKeepAwake(false));
    }
  }

  Future<void> _syncKeepAwake(VideoPlayerValue value) async {
    final ended =
        value.duration > Duration.zero &&
        value.position >= value.duration - const Duration(milliseconds: 500);
    final shouldKeepAwake =
        value.isInitialized && value.isPlaying && !value.hasError && !ended;
    await _setKeepAwake(shouldKeepAwake);
  }

  Future<void> _setKeepAwake(bool enabled) async {
    if (_keepAwakeEnabled == enabled) return;
    _keepAwakeEnabled = enabled;
    try {
      if (enabled) {
        await WakelockPlus.enable();
      } else {
        await WakelockPlus.disable();
      }
    } catch (_) {}
  }

  PlayerResolvedStream? _nextFallbackStream() {
    final current = _activePayload?.streamUrl;
    for (final stream in _activePayload?.fallbackStreams ?? const []) {
      if (stream.url.isNotEmpty && stream.url != current) return stream;
    }
    return null;
  }

  List<PlayerResolvedStream> _remainingFallbacksAfter(String url) {
    return [
      for (final stream in _activePayload?.fallbackStreams ?? const [])
        if (stream.url != url) stream,
    ];
  }

  List<PlayerResolvedStream> _qualityStreams() {
    final streams = <String, PlayerResolvedStream>{};
    final current = _activePayload?.currentStream;
    if (current != null && current.url.isNotEmpty) {
      streams[current.url] = current;
    }
    for (final stream in _activePayload?.fallbackStreams ?? const []) {
      if (stream.url.isNotEmpty) streams[stream.url] = stream;
    }
    final sorted = streams.values.toList();
    sorted.sort((a, b) {
      final quality = _qualityValue(b).compareTo(_qualityValue(a));
      if (quality != 0) return quality;
      return _formatRank(a).compareTo(_formatRank(b));
    });
    return sorted;
  }

  Future<void> _switchQuality(PlayerResolvedStream stream) async {
    if (stream.url == _activePayload?.streamUrl) return;
    final controller = _controller;
    final previousPosition = controller?.value.position ?? _position;
    final wasPlaying = controller?.value.isPlaying ?? _playing;
    final fallbacks = [
      for (final item in _qualityStreams())
        if (item.url != stream.url) item,
    ];
    final nextPayload = _activePayload?.copyWith(
      streamUrl: stream.url,
      headers: stream.headers,
      subtitles: stream.subtitles,
      currentStream: stream,
      fallbackStreams: fallbacks,
    );
    await _open(stream.url, headers: stream.headers, payload: nextPayload);
    final nextController = _controller;
    if (nextController != null && nextController.value.isInitialized) {
      if (previousPosition > Duration.zero) {
        await nextController.seekTo(previousPosition);
      }
      if (wasPlaying) await nextController.play();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _hideTimer?.cancel();
    unawaited(_setKeepAwake(false));
    _rootFocusNode.dispose();
    _progressFocusNode.dispose();
    _audioFocusNode.dispose();
    _subtitlesFocusNode.dispose();
    _qualityFocusNode.dispose();
    _episodesFocusNode.dispose();
    _controller?.removeListener(_onVideoChanged);
    _controller?.dispose();
    super.dispose();
  }

  void _showControls({FocusNode? focusNode}) {
    if (!_controlsVisible) setState(() => _controlsVisible = true);
    _scheduleHide();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      (focusNode ?? _progressFocusNode).requestFocus();
    });
  }

  void _keepControlsAwake() {
    if (!_controlsVisible) setState(() => _controlsVisible = true);
    _scheduleHide();
  }

  void _hideControls() {
    if (!_controlsVisible || !_playing) return;
    setState(() => _controlsVisible = false);
    _rootFocusNode.requestFocus();
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 5), _hideControls);
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }

    if (_episodePanelVisible) {
      if (_isBackKey(event.logicalKey)) {
        setState(() => _episodePanelVisible = false);
        _showControls(focusNode: _episodesFocusNode);
        return KeyEventResult.handled;
      }
      _keepControlsAwake();
      return KeyEventResult.ignored;
    }

    if (!_controlsVisible) {
      switch (event.logicalKey) {
        case LogicalKeyboardKey.select:
        case LogicalKeyboardKey.enter:
          _showControls(focusNode: _progressFocusNode);
          return KeyEventResult.handled;
        case LogicalKeyboardKey.arrowDown:
          _showControls(focusNode: _firstSecondaryNode());
          return KeyEventResult.handled;
        case LogicalKeyboardKey.arrowLeft:
          _showControls(focusNode: _progressFocusNode);
          _seekBy(_seekDelta(event.logicalKey), focusProgress: true);
          return KeyEventResult.handled;
        case LogicalKeyboardKey.arrowRight:
          _showControls(focusNode: _progressFocusNode);
          _seekBy(_seekDelta(event.logicalKey), focusProgress: true);
          return KeyEventResult.handled;
        case LogicalKeyboardKey.arrowUp:
          _showControls(focusNode: _progressFocusNode);
          return KeyEventResult.handled;
        case LogicalKeyboardKey.goBack:
        case LogicalKeyboardKey.escape:
          context.pop();
          return KeyEventResult.handled;
      }
    }

    _keepControlsAwake();
    final focused = FocusManager.instance.primaryFocus;
    final secondaryIndex = _secondaryNodes.indexWhere(
      (node) => node == focused,
    );

    switch (event.logicalKey) {
      case LogicalKeyboardKey.select:
      case LogicalKeyboardKey.enter:
        if (secondaryIndex >= 0) {
          _activateSecondary(_secondaryNodes[secondaryIndex]);
        } else {
          _togglePlayPause();
        }
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowLeft:
        if (secondaryIndex >= 0) {
          _focusSecondary(
            (secondaryIndex - 1).clamp(0, _secondaryNodes.length - 1),
          );
          return KeyEventResult.handled;
        }
        _seekBy(_seekDelta(event.logicalKey), focusProgress: true);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowRight:
        if (secondaryIndex >= 0) {
          _focusSecondary(
            (secondaryIndex + 1).clamp(0, _secondaryNodes.length - 1),
          );
          return KeyEventResult.handled;
        }
        _seekBy(_seekDelta(event.logicalKey), focusProgress: true);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowUp:
        _progressFocusNode.requestFocus();
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowDown:
        if (focused == _progressFocusNode || secondaryIndex == -1) {
          _firstSecondaryNode().requestFocus();
        }
        return KeyEventResult.handled;
      case LogicalKeyboardKey.goBack:
      case LogicalKeyboardKey.escape:
        if (_controlsVisible) {
          _hideControls();
          return KeyEventResult.handled;
        }
        context.pop();
        return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  bool _isBackKey(LogicalKeyboardKey key) =>
      key == LogicalKeyboardKey.goBack || key == LogicalKeyboardKey.escape;

  FocusNode _firstSecondaryNode() => _audioFocusNode;

  List<FocusNode> get _secondaryNodes => [
    _audioFocusNode,
    _subtitlesFocusNode,
    _qualityFocusNode,
    if (_isSeries) _episodesFocusNode,
  ];

  void _focusSecondary(int index) {
    final nodes = _secondaryNodes;
    if (nodes.isEmpty) return;
    nodes[index.clamp(0, nodes.length - 1)].requestFocus();
  }

  void _activateSecondary(FocusNode node) {
    if (node == _audioFocusNode) {
      unawaited(_showAudioOptions());
    } else if (node == _subtitlesFocusNode) {
      unawaited(_showSubtitleOptions());
    } else if (node == _qualityFocusNode) {
      unawaited(_showQualityOptions());
    } else if (node == _episodesFocusNode && _isSeries) {
      setState(() => _episodePanelVisible = true);
    }
  }

  Duration _seekDelta(LogicalKeyboardKey key) {
    final now = DateTime.now();
    if (_lastSeekKey == key &&
        now.difference(_lastSeekAt) < const Duration(milliseconds: 450)) {
      _seekRepeatCount = (_seekRepeatCount + 1).clamp(0, 6);
    } else {
      _seekRepeatCount = 0;
    }
    _lastSeekKey = key;
    _lastSeekAt = now;
    final seconds = 8 + (_seekRepeatCount * 6);
    return key == LogicalKeyboardKey.arrowLeft
        ? Duration(seconds: -seconds)
        : Duration(seconds: seconds);
  }

  @override
  Widget build(BuildContext context) {
    final payload = _activePayload;
    final controller = _controller;
    final hasVideo = controller != null && controller.value.isInitialized;
    final isPaused = hasVideo && !controller.value.isPlaying;

    return Focus(
      focusNode: _rootFocusNode,
      autofocus: true,
      onKeyEvent: _onKey,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          fit: StackFit.expand,
          children: [
            if (payload?.streamUrl == null)
              const _NoStreamPreview()
            else if (hasVideo)
              Center(
                child: AspectRatio(
                  aspectRatio: controller.value.aspectRatio == 0
                      ? 16 / 9
                      : controller.value.aspectRatio,
                  child: VideoPlayer(controller),
                ),
              ),
            if (hasVideo && _selectedSubtitleId != 'off')
              Positioned(
                left: 80,
                right: 80,
                bottom: _controlsVisible ? 124 : 48,
                child: ClosedCaption(
                  text: controller.value.caption.text,
                  textStyle: const TextStyle(
                    color: Colors.white,
                    fontSize: 21,
                    fontWeight: FontWeight.w700,
                    shadows: [
                      Shadow(color: Colors.black, blurRadius: 8),
                      Shadow(color: Colors.black, blurRadius: 14),
                    ],
                  ),
                ),
              ),
            if (isPaused && _controlsVisible)
              _PauseBackdrop(artworkUrl: payload?.artworkUrl),
            AnimatedOpacity(
              opacity: _controlsVisible ? 1 : 0,
              duration: const Duration(milliseconds: 180),
              child: IgnorePointer(
                ignoring: !_controlsVisible,
                child: _PlayerOverlay(
                  payload: payload,
                  position: _position,
                  duration: _duration,
                  initializing: _initializing,
                  error: _error,
                  buffering: _buffering,
                  isPaused: isPaused,
                  isSeries: _isSeries,
                  progressFocusNode: _progressFocusNode,
                  audioFocusNode: _audioFocusNode,
                  subtitlesFocusNode: _subtitlesFocusNode,
                  qualityFocusNode: _qualityFocusNode,
                  episodesFocusNode: _episodesFocusNode,
                  onSeekToFraction: _seekToFraction,
                  onAudio: _showAudioOptions,
                  onSubtitles: _showSubtitleOptions,
                  onQuality: _showQualityOptions,
                  onEpisodes: _isSeries
                      ? () {
                          _hideTimer?.cancel();
                          setState(() => _episodePanelVisible = true);
                        }
                      : null,
                ),
              ),
            ),
            if (_episodePanelVisible)
              _EpisodePanel(
                payload: payload,
                onSelect: _playEpisode,
                onSeasonSelected: _loadSeasonEpisodes,
                onClose: () {
                  setState(() => _episodePanelVisible = false);
                  _showControls(focusNode: _episodesFocusNode);
                },
              ),
            if (_initializing && _error == null)
              const Center(
                child: CircularProgressIndicator(color: WenaTheme.red),
              ),
            if (_error != null)
              _PlaybackError(
                message: _error!,
                onRetry: () {
                  final url = payload?.streamUrl;
                  if (url != null && url.isNotEmpty) {
                    unawaited(_open(url, headers: payload?.headers));
                  }
                },
              ),
          ],
        ),
      ),
    );
  }

  void _togglePlayPause() {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    controller.value.isPlaying
        ? unawaited(controller.pause())
        : unawaited(controller.play());
    _showControls(focusNode: _progressFocusNode);
  }

  void _seekBy(Duration delta, {bool focusProgress = false}) {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    final rawTarget = _position + delta;
    final target = rawTarget < Duration.zero
        ? Duration.zero
        : rawTarget > _duration
        ? _duration
        : rawTarget;
    unawaited(controller.seekTo(target));
    _showControls(focusNode: focusProgress ? _progressFocusNode : null);
  }

  void _seekToFraction(double fraction) {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    final target = Duration(
      milliseconds: (_duration.inMilliseconds * fraction).round(),
    );
    unawaited(controller.seekTo(target));
    _showControls(focusNode: _progressFocusNode);
  }

  Future<void> _showAudioOptions() async {
    await _refreshAudioTracks();
    final options = _audioTracks;
    if (!_audioTrackSupport || options.isEmpty) {
      await _showOptionSheet<_SimplePlayerOption>(
        title: 'Audio',
        options: const [
          _SimplePlayerOption(
            id: 'default',
            title: 'Default Audio',
            subtitle: 'The stream exposes its default audio track only.',
          ),
        ],
        selected: const _SimplePlayerOption(id: 'default', title: ''),
        labelBuilder: (option, _) => option.title,
        subtitleBuilder: (option, _) => option.subtitle,
        isSelected: (_) => true,
        onSelected: (_) async {},
      );
      return;
    }
    await _showOptionSheet<VideoAudioTrack>(
      title: 'Audio',
      options: options,
      selected: options.firstWhere(
        (track) => track.id == _selectedAudioTrackId,
        orElse: () => options.first,
      ),
      labelBuilder: _audioTrackTitle,
      subtitleBuilder: _audioTrackSubtitle,
      isSelected: (track) =>
          track.id == _selectedAudioTrackId || track.isSelected,
      onSelected: (track) async {
        await _selectAudioTrack(track, userInitiated: true);
      },
    );
  }

  Future<void> _showSubtitleOptions() async {
    final options = [
      _SimplePlayerOption(
        id: 'off',
        title: 'Off',
        subtitle: 'Disable subtitle rendering.',
      ),
      for (final track in _subtitleTracks)
        _SimplePlayerOption(
          id: track.id,
          title: _subtitleTitle(track),
          subtitle: track.url,
        ),
    ];
    await _showOptionSheet<_SimplePlayerOption>(
      title: 'Subtitles',
      options: options,
      selected: options.first,
      labelBuilder: (option, _) => option.title,
      subtitleBuilder: (option, _) => option.subtitle,
      isSelected: (option) => option.id == _selectedSubtitleId,
      emptyHint: _subtitleTracks.isEmpty
          ? 'No external subtitle files were provided by this source.'
          : null,
      onSelected: (option) async {
        setState(() => _selectedSubtitleId = option.id);
        if (option.id == 'off') {
          await _controller?.setClosedCaptionFile(null);
          return;
        }
        final track = _subtitleTracks.firstWhere(
          (item) => item.id == option.id,
          orElse: () => _subtitleTracks.first,
        );
        await _controller?.setClosedCaptionFile(_loadSubtitle(track));
      },
    );
  }

  Future<void> _showQualityOptions() async {
    final options = _qualityStreams();
    if (options.isEmpty) {
      await _showOptionSheet<_SimplePlayerOption>(
        title: 'Quality',
        options: const [
          _SimplePlayerOption(
            id: 'current',
            title: 'Current Stream',
            subtitle: 'No alternate resolved streams were provided.',
          ),
        ],
        selected: const _SimplePlayerOption(id: 'current', title: ''),
        labelBuilder: (option, _) => option.title,
        subtitleBuilder: (option, _) => option.subtitle,
        isSelected: (_) => true,
        onSelected: (_) async {},
      );
      return;
    }
    await _showOptionSheet<PlayerResolvedStream>(
      title: 'Quality',
      options: options,
      selected: options.firstWhere(
        (stream) => stream.url == _activePayload?.streamUrl,
        orElse: () => options.first,
      ),
      labelBuilder: (stream, _) => _qualityStreamTitle(stream),
      subtitleBuilder: (stream, _) => _qualityStreamSubtitle(stream),
      isSelected: (stream) => stream.url == _activePayload?.streamUrl,
      onSelected: _switchQuality,
    );
  }

  Future<void> _showOptionSheet<T>({
    required String title,
    required List<T> options,
    required T selected,
    required String Function(T option, int index) labelBuilder,
    required String Function(T option, int index) subtitleBuilder,
    required bool Function(T option) isSelected,
    required Future<void> Function(T option) onSelected,
    String? emptyHint,
  }) async {
    _hideTimer?.cancel();
    await showDialog<void>(
      context: context,
      builder: (context) => _PlayerOptionDialog<T>(
        title: title,
        options: options,
        selected: selected,
        labelBuilder: labelBuilder,
        subtitleBuilder: subtitleBuilder,
        isSelected: isSelected,
        emptyHint: emptyHint,
        onSelected: (option) async {
          await onSelected(option);
          if (context.mounted) Navigator.of(context).pop();
        },
      ),
    );
    if (mounted) _showControls();
  }

  Future<void> _playEpisode(PlayerEpisodePayload episode) async {
    final payload = _activePayload;
    final resolver = payload?.episodeStreamResolver;
    if (payload == null || resolver == null) return;
    setState(() => _episodePanelVisible = false);
    _showControls(focusNode: _progressFocusNode);
    final resolved = await resolver(episode.season, episode.episode);
    if (!mounted || resolved == null) return;
    final nextPayload = payload.copyWith(
      episodeTitle: 'E${episode.episode} ${episode.title}',
      streamUrl: resolved.url,
      headers: resolved.headers,
      subtitles: resolved.subtitles,
      currentStream: resolved,
      artworkUrl: episode.artworkUrl ?? payload.artworkUrl,
      overview: (episode.overview ?? '').isEmpty
          ? payload.overview
          : episode.overview,
      runtime: episode.runtime ?? payload.runtime,
      season: episode.season,
      episode: episode.episode,
    );
    await _open(resolved.url, headers: resolved.headers, payload: nextPayload);
  }

  Future<void> _loadSeasonEpisodes(int season) async {
    final payload = _activePayload;
    final resolver = payload?.episodeMetadataResolver;
    if (payload == null || resolver == null) return;
    if (payload.episodes.any((episode) => episode.season == season)) return;
    try {
      final episodes = await resolver(
        season,
      ).timeout(const Duration(seconds: 18), onTimeout: () => const []);
      if (!mounted || episodes.isEmpty || _activePayload != payload) return;
      setState(() {
        _activePayload = payload.copyWith(
          episodes: _mergeEpisodes(payload.episodes, episodes),
        );
      });
    } catch (_) {}
  }

  Future<void> _refreshAudioTracks({bool preferEnglish = false}) async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    final supported = controller.isAudioTrackSupportAvailable();
    if (!supported) {
      if (!mounted) return;
      setState(() {
        _audioTrackSupport = false;
        _audioTracks = const [];
        _selectedAudioTrackId = null;
      });
      return;
    }
    try {
      var tracks = await controller.getAudioTracks();
      if (!mounted || controller != _controller) return;
      if (preferEnglish && !_englishAudioApplied) {
        final english = _preferredEnglishTrack(tracks);
        if (english != null && !english.isSelected) {
          await _selectAudioTrack(english, userInitiated: false);
          await Future<void>.delayed(const Duration(milliseconds: 250));
          if (!mounted || controller != _controller) return;
          tracks = await controller.getAudioTracks();
        }
        _englishAudioApplied = true;
      }
      String? selectedId;
      for (final track in tracks) {
        if (track.isSelected) {
          selectedId = track.id;
          break;
        }
      }
      selectedId ??= _selectedAudioTrackId;
      if (selectedId == null && tracks.isNotEmpty) {
        selectedId = tracks.first.id;
      }
      setState(() {
        _audioTrackSupport = true;
        _audioTracks = tracks;
        _selectedAudioTrackId = selectedId;
      });
    } catch (_) {
      if (!mounted || controller != _controller) return;
      setState(() {
        _audioTrackSupport = false;
        _audioTracks = const [];
        _selectedAudioTrackId = null;
      });
    }
  }

  Future<void> _selectAudioTrack(
    VideoAudioTrack track, {
    required bool userInitiated,
  }) async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    final before = controller.value.position;
    final wasPlaying = controller.value.isPlaying;
    if (mounted) setState(() => _selectedAudioTrackId = track.id);
    await controller.selectAudioTrack(track.id);
    if (!mounted || controller != _controller) return;
    await Future<void>.delayed(const Duration(milliseconds: 250));
    if (!mounted || controller != _controller) return;
    final after = controller.value.position;
    if (before > const Duration(seconds: 3) &&
        after < const Duration(seconds: 2)) {
      await controller.seekTo(before);
    }
    if (wasPlaying && !controller.value.isPlaying) {
      await controller.play();
    }
    if (userInitiated) {
      _englishAudioApplied = true;
      await _refreshAudioTracks();
    }
  }

  Future<void> _ensureEpisodesLoaded() async {
    final payload = _activePayload;
    if (payload == null ||
        !_isSeries ||
        payload.episodeMetadataResolver == null) {
      return;
    }
    final currentSeason = payload.season ?? 1;
    final hasCurrentSeason = payload.episodes.any(
      (episode) => episode.season == currentSeason,
    );
    if (payload.episodes.isNotEmpty && hasCurrentSeason) return;
    try {
      final episodes = await payload.episodeMetadataResolver!(currentSeason)
          .timeout(const Duration(seconds: 18), onTimeout: () => const []);
      if (!mounted || _activePayload != payload) return;
      final merged = _mergeEpisodes(payload.episodes, episodes);
      if (merged.isEmpty) return;
      setState(() {
        _activePayload = payload.copyWith(episodes: merged);
      });
    } catch (_) {}
  }

  Future<ClosedCaptionFile> _loadSubtitle(PlayerSubtitlePayload track) async {
    final response = await Dio().get<String>(
      track.url,
      options: Options(
        responseType: ResponseType.plain,
        headers: _normalizedHeaders(_activePayload?.headers),
      ),
    );
    final contents = response.data ?? '';
    final path = Uri.tryParse(track.url)?.path.toLowerCase() ?? '';
    if (path.endsWith('.vtt') || contents.trimLeft().startsWith('WEBVTT')) {
      return WebVTTCaptionFile(contents);
    }
    return SubRipCaptionFile(contents);
  }
}

class _PlayerOverlay extends StatelessWidget {
  const _PlayerOverlay({
    required this.payload,
    required this.position,
    required this.duration,
    required this.initializing,
    required this.error,
    required this.buffering,
    required this.isPaused,
    required this.isSeries,
    required this.progressFocusNode,
    required this.audioFocusNode,
    required this.subtitlesFocusNode,
    required this.qualityFocusNode,
    required this.episodesFocusNode,
    required this.onSeekToFraction,
    required this.onAudio,
    required this.onSubtitles,
    required this.onQuality,
    required this.onEpisodes,
  });

  final PlayerPayload? payload;
  final Duration position;
  final Duration duration;
  final bool initializing;
  final String? error;
  final bool buffering;
  final bool isPaused;
  final bool isSeries;
  final FocusNode progressFocusNode;
  final FocusNode audioFocusNode;
  final FocusNode subtitlesFocusNode;
  final FocusNode qualityFocusNode;
  final FocusNode episodesFocusNode;
  final ValueChanged<double> onSeekToFraction;
  final VoidCallback onAudio;
  final VoidCallback onSubtitles;
  final VoidCallback onQuality;
  final VoidCallback? onEpisodes;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            if (isPaused) const Color(0x99000000) else Colors.transparent,
            Colors.transparent,
            const Color(0xE6000000),
          ],
        ),
      ),
      padding: const EdgeInsets.fromLTRB(34, 24, 34, 26),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isPaused) _PauseInfo(payload: payload, isSeries: isSeries),
          const Spacer(),
          Text(
            payload?.title ?? 'WenaTV Player',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          if (payload?.episodeTitle != null)
            Text(
              payload!.episodeTitle!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white70, fontSize: 13),
            ),
          const SizedBox(height: 10),
          Row(
            children: [
              Text(_formatDuration(position), style: _timeStyle),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: _FocusableProgressBar(
                    focusNode: progressFocusNode,
                    position: position,
                    duration: duration,
                    onSeekToFraction: onSeekToFraction,
                  ),
                ),
              ),
              Text(
                duration == Duration.zero
                    ? _statusText(initializing, error, buffering)
                    : _formatDuration(duration),
                style: _timeStyle,
              ),
            ],
          ),
          const SizedBox(height: 12),
          FocusTraversalGroup(
            policy: ReadingOrderTraversalPolicy(),
            child: Row(
              children: [
                _ControlChip(
                  label: 'Audio',
                  icon: Icons.graphic_eq,
                  focusNode: audioFocusNode,
                  onPressed: onAudio,
                ),
                _ControlChip(
                  label: 'Subtitles',
                  icon: Icons.closed_caption_outlined,
                  focusNode: subtitlesFocusNode,
                  onPressed: onSubtitles,
                ),
                _ControlChip(
                  label: 'Quality',
                  icon: Icons.hd,
                  focusNode: qualityFocusNode,
                  onPressed: onQuality,
                ),
                if (isSeries)
                  _ControlChip(
                    label: 'Episodes',
                    icon: Icons.view_list,
                    focusNode: episodesFocusNode,
                    onPressed: onEpisodes ?? () {},
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PauseInfo extends StatelessWidget {
  const _PauseInfo({required this.payload, required this.isSeries});

  final PlayerPayload? payload;
  final bool isSeries;

  @override
  Widget build(BuildContext context) {
    final meta = isSeries ? _seriesInfo(payload) : _movieInfo(payload);
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 780),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if ((payload?.artworkUrl ?? '').isNotEmpty)
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: CachedNetworkImage(
                imageUrl: payload!.artworkUrl!,
                width: 154,
                height: 86,
                fit: BoxFit.cover,
              ),
            ),
          if ((payload?.artworkUrl ?? '').isNotEmpty) const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  payload?.title ?? 'Paused',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.displaySmall?.copyWith(
                    fontSize: 34,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                if (meta.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    meta,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white70, fontSize: 14),
                  ),
                ],
                if ((payload?.overview ?? '').isNotEmpty) ...[
                  const SizedBox(height: 9),
                  Text(
                    payload!.overview!,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 13,
                      height: 1.35,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PauseBackdrop extends StatelessWidget {
  const _PauseBackdrop({required this.artworkUrl});

  final String? artworkUrl;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        if ((artworkUrl ?? '').isNotEmpty)
          CachedNetworkImage(imageUrl: artworkUrl!, fit: BoxFit.cover),
        Container(color: Colors.black.withValues(alpha: .62)),
        Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: [Colors.black, Color(0xCC000000), Colors.transparent],
            ),
          ),
        ),
      ],
    );
  }
}

class _FocusableProgressBar extends StatefulWidget {
  const _FocusableProgressBar({
    required this.focusNode,
    required this.position,
    required this.duration,
    required this.onSeekToFraction,
  });

  final FocusNode focusNode;
  final Duration position;
  final Duration duration;
  final ValueChanged<double> onSeekToFraction;

  @override
  State<_FocusableProgressBar> createState() => _FocusableProgressBarState();
}

class _FocusableProgressBarState extends State<_FocusableProgressBar> {
  @override
  void initState() {
    super.initState();
    widget.focusNode.addListener(_onFocus);
  }

  @override
  void dispose() {
    widget.focusNode.removeListener(_onFocus);
    super.dispose();
  }

  void _onFocus() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final progress = widget.duration.inMilliseconds <= 0
        ? 0.0
        : (widget.position.inMilliseconds / widget.duration.inMilliseconds)
              .clamp(0.0, 1.0);
    final focused = widget.focusNode.hasFocus;
    return Focus(
      focusNode: widget.focusNode,
      onKeyEvent: (_, event) {
        if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
          return KeyEventResult.ignored;
        }
        if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
          widget.onSeekToFraction((progress - .025).clamp(0.0, 1.0));
          return KeyEventResult.handled;
        }
        if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
          widget.onSeekToFraction((progress + .025).clamp(0.0, 1.0));
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        height: focused ? 11 : 7,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: .22),
          borderRadius: BorderRadius.circular(999),
          boxShadow: focused
              ? [
                  BoxShadow(
                    color: WenaTheme.red.withValues(alpha: .45),
                    blurRadius: 18,
                    spreadRadius: 1,
                  ),
                ]
              : null,
        ),
        alignment: Alignment.centerLeft,
        child: FractionallySizedBox(
          widthFactor: progress,
          child: Container(
            decoration: BoxDecoration(
              color: WenaTheme.red,
              borderRadius: BorderRadius.circular(999),
            ),
          ),
        ),
      ),
    );
  }
}

class _ControlChip extends StatefulWidget {
  const _ControlChip({
    required this.label,
    required this.icon,
    required this.focusNode,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final FocusNode focusNode;
  final VoidCallback onPressed;

  @override
  State<_ControlChip> createState() => _ControlChipState();
}

class _ControlChipState extends State<_ControlChip> {
  @override
  void initState() {
    super.initState();
    widget.focusNode.addListener(_onFocus);
  }

  @override
  void dispose() {
    widget.focusNode.removeListener(_onFocus);
    super.dispose();
  }

  void _onFocus() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final focused = widget.focusNode.hasFocus;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Focus(
        focusNode: widget.focusNode,
        onKeyEvent: (_, event) {
          if (event is KeyDownEvent &&
              (event.logicalKey == LogicalKeyboardKey.select ||
                  event.logicalKey == LogicalKeyboardKey.enter)) {
            widget.onPressed();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: GestureDetector(
          onTap: widget.onPressed,
          child: AnimatedScale(
            scale: focused ? 1.025 : 1,
            duration: const Duration(milliseconds: 120),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: focused
                    ? WenaTheme.red
                    : Colors.black.withValues(alpha: .48),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: focused
                      ? WenaTheme.red
                      : Colors.white.withValues(alpha: .12),
                ),
                boxShadow: focused
                    ? [
                        BoxShadow(
                          color: WenaTheme.red.withValues(alpha: .36),
                          blurRadius: 18,
                        ),
                      ]
                    : null,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(widget.icon, size: 18),
                  const SizedBox(width: 7),
                  Text(
                    widget.label,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PlayerOptionDialog<T> extends StatelessWidget {
  const _PlayerOptionDialog({
    required this.title,
    required this.options,
    required this.selected,
    required this.labelBuilder,
    required this.subtitleBuilder,
    required this.isSelected,
    required this.onSelected,
    this.emptyHint,
  });

  final String title;
  final List<T> options;
  final T selected;
  final String Function(T option, int index) labelBuilder;
  final String Function(T option, int index) subtitleBuilder;
  final bool Function(T option) isSelected;
  final Future<void> Function(T option) onSelected;
  final String? emptyHint;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 180, vertical: 80),
      child: Container(
        width: 500,
        constraints: const BoxConstraints(maxHeight: 380),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xF0111111),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.white.withValues(alpha: .08)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
            ),
            if ((emptyHint ?? '').isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(emptyHint!, style: const TextStyle(color: Colors.white54)),
            ],
            const SizedBox(height: 10),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: options.length,
                separatorBuilder: (_, __) => const SizedBox(height: 6),
                itemBuilder: (context, index) {
                  final option = options[index];
                  return _PlayerOptionTile(
                    autofocus: index == 0 || isSelected(option),
                    selected: isSelected(option),
                    title: labelBuilder(option, index),
                    subtitle: subtitleBuilder(option, index),
                    onPressed: () => onSelected(option),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PlayerOptionTile extends StatefulWidget {
  const _PlayerOptionTile({
    required this.autofocus,
    required this.selected,
    required this.title,
    required this.subtitle,
    required this.onPressed,
  });

  final bool autofocus;
  final bool selected;
  final String title;
  final String subtitle;
  final Future<void> Function() onPressed;

  @override
  State<_PlayerOptionTile> createState() => _PlayerOptionTileState();
}

class _PlayerOptionTileState extends State<_PlayerOptionTile> {
  final _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_onFocus);
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocus);
    _focusNode.dispose();
    super.dispose();
  }

  void _onFocus() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final focused = _focusNode.hasFocus;
    return Focus(
      autofocus: widget.autofocus,
      focusNode: _focusNode,
      onKeyEvent: (_, event) {
        if (event is KeyDownEvent &&
            (event.logicalKey == LogicalKeyboardKey.select ||
                event.logicalKey == LogicalKeyboardKey.enter)) {
          unawaited(widget.onPressed());
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        onTap: () => unawaited(widget.onPressed()),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            color: focused
                ? WenaTheme.red.withValues(alpha: .18)
                : Colors.white.withValues(alpha: .05),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: widget.selected || focused
                  ? WenaTheme.red
                  : Colors.white.withValues(alpha: .08),
            ),
          ),
          child: Row(
            children: [
              Icon(
                widget.selected
                    ? Icons.radio_button_checked
                    : Icons.radio_button_off,
                color: widget.selected ? WenaTheme.red : Colors.white54,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                    if (widget.subtitle.isNotEmpty)
                      Text(
                        widget.subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 12,
                        ),
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

class _EpisodePanel extends StatefulWidget {
  const _EpisodePanel({
    required this.payload,
    required this.onSelect,
    required this.onSeasonSelected,
    required this.onClose,
  });

  final PlayerPayload? payload;
  final ValueChanged<PlayerEpisodePayload> onSelect;
  final ValueChanged<int> onSeasonSelected;
  final VoidCallback onClose;

  @override
  State<_EpisodePanel> createState() => _EpisodePanelState();
}

class _EpisodePanelState extends State<_EpisodePanel> {
  int? _selectedSeason;

  @override
  void initState() {
    super.initState();
    _selectedSeason = widget.payload?.season ?? 1;
  }

  @override
  void didUpdateWidget(covariant _EpisodePanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    final season = widget.payload?.season ?? 1;
    if (_selectedSeason == null ||
        oldWidget.payload?.streamUrl != widget.payload?.streamUrl) {
      _selectedSeason = season;
    }
  }

  @override
  Widget build(BuildContext context) {
    final payload = widget.payload;
    final currentSeason = payload?.season ?? 1;
    final currentEpisode = payload?.episode ?? 1;
    final fallbackEpisode = PlayerEpisodePayload(
      season: currentSeason,
      episode: currentEpisode,
      title: payload?.episodeTitle ?? 'Current Episode',
      runtime: payload?.runtime,
      overview: payload?.overview,
      artworkUrl: payload?.artworkUrl,
    );
    final allEpisodes = payload?.episodes.isNotEmpty == true
        ? payload!.episodes
        : [fallbackEpisode];
    final seasons = _availableSeasons(payload, allEpisodes, currentSeason);
    final selectedSeason = seasons.contains(_selectedSeason)
        ? _selectedSeason!
        : currentSeason;
    final episodes = _episodesForSeason(
      allEpisodes,
      selectedSeason,
      fallbackEpisode,
    );
    return Align(
      alignment: Alignment.centerRight,
      child: FocusTraversalGroup(
        policy: OrderedTraversalPolicy(),
        child: Container(
          width: 540,
          height: double.infinity,
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 18),
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: [Color(0xF5000000), Color(0xFA080808)],
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Episodes',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 18),
              SizedBox(
                height: 42,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: seasons.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (context, index) {
                    final season = seasons[index];
                    return _SeasonChip(
                      season: season,
                      selected: season == selectedSeason,
                      playing: season == currentSeason,
                      autofocus: index == 0,
                      onPressed: () {
                        setState(() => _selectedSeason = season);
                        widget.onSeasonSelected(season);
                      },
                    );
                  },
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: episodes.isEmpty
                    ? _EpisodeEmptyState(
                        season: selectedSeason,
                        onRetry: () => widget.onSeasonSelected(selectedSeason),
                      )
                    : ListView.separated(
                        itemCount: episodes.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 9),
                        itemBuilder: (context, index) {
                          final episode = episodes[index];
                          final playing =
                              episode.season == currentSeason &&
                              episode.episode == currentEpisode;
                          return _EpisodePanelCard(
                            item: episode,
                            playing: playing,
                            autofocus: playing,
                            onPressed: () => widget.onSelect(episode),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EpisodePanelCard extends StatefulWidget {
  const _EpisodePanelCard({
    required this.item,
    required this.playing,
    required this.autofocus,
    required this.onPressed,
  });

  final PlayerEpisodePayload item;
  final bool playing;
  final bool autofocus;
  final VoidCallback onPressed;

  @override
  State<_EpisodePanelCard> createState() => _EpisodePanelCardState();
}

class _EpisodeEmptyState extends StatelessWidget {
  const _EpisodeEmptyState({required this.season, required this.onRetry});

  final int season;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.playlist_play, color: Colors.white38, size: 42),
          const SizedBox(height: 12),
          Text(
            'No episodes loaded for Season $season',
            style: const TextStyle(
              color: Colors.white70,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 12),
          TextButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: const Text('Retry'),
          ),
        ],
      ),
    );
  }
}

class _SeasonChip extends StatefulWidget {
  const _SeasonChip({
    required this.season,
    required this.selected,
    required this.playing,
    required this.autofocus,
    required this.onPressed,
  });

  final int season;
  final bool selected;
  final bool playing;
  final bool autofocus;
  final VoidCallback onPressed;

  @override
  State<_SeasonChip> createState() => _SeasonChipState();
}

class _SeasonChipState extends State<_SeasonChip> {
  final _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_onFocus);
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocus);
    _focusNode.dispose();
    super.dispose();
  }

  void _onFocus() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final focused = _focusNode.hasFocus;
    return Focus(
      focusNode: _focusNode,
      autofocus: widget.autofocus,
      onKeyEvent: (_, event) {
        if (event is KeyDownEvent &&
            (event.logicalKey == LogicalKeyboardKey.select ||
                event.logicalKey == LogicalKeyboardKey.enter)) {
          widget.onPressed();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        onTap: widget.onPressed,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(
            color: widget.selected
                ? WenaTheme.red
                : focused
                ? WenaTheme.red.withValues(alpha: .22)
                : Colors.white.withValues(alpha: .08),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: focused || widget.selected
                  ? WenaTheme.red
                  : Colors.white.withValues(alpha: .08),
              width: focused ? 2 : 1,
            ),
            boxShadow: focused
                ? [
                    BoxShadow(
                      color: WenaTheme.red.withValues(alpha: .35),
                      blurRadius: 18,
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Season ${widget.season}',
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 13,
                ),
              ),
              if (widget.playing) ...[
                const SizedBox(width: 8),
                const Icon(Icons.play_arrow, size: 15),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _EpisodePanelCardState extends State<_EpisodePanelCard> {
  final _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_onFocus);
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocus);
    _focusNode.dispose();
    super.dispose();
  }

  void _onFocus() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final focused = _focusNode.hasFocus;
    final item = widget.item;
    return Focus(
      focusNode: _focusNode,
      autofocus: widget.autofocus,
      onKeyEvent: (_, event) {
        if (event is KeyDownEvent &&
            (event.logicalKey == LogicalKeyboardKey.select ||
                event.logicalKey == LogicalKeyboardKey.enter)) {
          widget.onPressed();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        onTap: widget.onPressed,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: focused
                ? WenaTheme.red.withValues(alpha: .16)
                : WenaTheme.surface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: focused || widget.playing
                  ? WenaTheme.red
                  : Colors.white.withValues(alpha: .08),
              width: focused ? 2 : 1,
            ),
            boxShadow: focused
                ? [
                    BoxShadow(
                      color: WenaTheme.red.withValues(alpha: .35),
                      blurRadius: 20,
                    ),
                  ]
                : null,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: (item.artworkUrl ?? '').isEmpty
                    ? Container(width: 112, height: 64, color: WenaTheme.soft)
                    : CachedNetworkImage(
                        imageUrl: item.artworkUrl!,
                        width: 112,
                        height: 64,
                        fit: BoxFit.cover,
                      ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'S${item.season.toString().padLeft(2, '0')}E${item.episode.toString().padLeft(2, '0')}',
                      style: const TextStyle(
                        color: WenaTheme.red,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Text(
                      item.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                    if (item.runtime != null)
                      Text(
                        '${item.runtime} min',
                        style: const TextStyle(color: Colors.white60),
                      ),
                    if ((item.overview ?? '').isNotEmpty)
                      Text(
                        item.overview!,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 12,
                        ),
                      ),
                  ],
                ),
              ),
              if (widget.playing)
                const Padding(
                  padding: EdgeInsets.only(left: 8),
                  child: Icon(Icons.play_arrow, color: WenaTheme.red),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PlaybackError extends StatelessWidget {
  const _PlaybackError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 560,
        padding: const EdgeInsets.all(18),
        color: const Color(0xDD111111),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: WenaTheme.red, size: 42),
            const SizedBox(height: 14),
            const Text(
              'Stream failed to start',
              style: TextStyle(fontSize: 21, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 18),
            TextButton.icon(
              autofocus: true,
              style: TextButton.styleFrom(
                backgroundColor: WenaTheme.red,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 12,
                ),
              ),
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}

class _NoStreamPreview extends StatelessWidget {
  const _NoStreamPreview();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF161616), Colors.black, Color(0xFF280507)],
        ),
      ),
      child: const Center(
        child: Text(
          'Choose an enabled provider stream to start playback.',
          style: TextStyle(fontSize: 20, color: Colors.white70),
        ),
      ),
    );
  }
}

Map<String, String> _normalizedHeaders(Map<String, String>? headers) {
  final normalized = <String, String>{};
  for (final entry in (headers ?? const <String, String>{}).entries) {
    final key = entry.key.toLowerCase() == 'referer'
        ? 'Referer'
        : entry.key.toLowerCase() == 'user-agent'
        ? 'User-Agent'
        : entry.key.toLowerCase() == 'origin'
        ? 'Origin'
        : entry.key;
    if (!key.startsWith('x-wenatv-')) normalized[key] = entry.value;
  }
  normalized.putIfAbsent(
    'User-Agent',
    () => 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
  );
  normalized.putIfAbsent('Accept', () => '*/*');
  return normalized;
}

const _timeStyle = TextStyle(color: Colors.white70, fontSize: 13);

class _SimplePlayerOption {
  const _SimplePlayerOption({
    required this.id,
    required this.title,
    this.subtitle = '',
  });

  final String id;
  final String title;
  final String subtitle;
}

String _audioTrackTitle(VideoAudioTrack track, int index) {
  final language = _friendlyLanguage(track.language);
  final title = _cleanTrackText(track.label);
  if (language.isNotEmpty && title.isNotEmpty && language != title) {
    return '$language - $title';
  }
  if (language.isNotEmpty) return language;
  if (title.isNotEmpty) return title;
  final channels = _channelLabel(track);
  return channels.isEmpty ? 'Audio ${index + 1}' : channels;
}

String _audioTrackSubtitle(VideoAudioTrack track, int index) {
  final parts = <String>[
    if ((track.codec ?? '').isNotEmpty) track.codec!.toUpperCase(),
    if (_channelLabel(track).isNotEmpty) _channelLabel(track),
    if (track.bitrate != null) '${(track.bitrate! / 1000).round()} kbps',
    if (track.sampleRate != null) '${(track.sampleRate! / 1000).round()} kHz',
  ];
  return parts.join(' | ');
}

String _qualityStreamTitle(PlayerResolvedStream stream) {
  final quality = _cleanQuality(stream.quality, stream.url);
  final adaptive = _isAdaptiveStream(stream);
  if (adaptive && (quality == 'AUTO' || quality.isEmpty)) return 'Auto';
  return quality.isEmpty ? 'Stream' : quality;
}

String _qualityStreamSubtitle(PlayerResolvedStream stream) {
  final parts = <String>[
    if ((stream.providerName ?? '').isNotEmpty) stream.providerName!,
    if ((stream.format ?? '').isNotEmpty) stream.format!.toUpperCase(),
    if ((stream.language ?? '').isNotEmpty) stream.language!,
    if ((stream.fileSize ?? '').isNotEmpty) stream.fileSize!,
  ];
  return parts.join(' • ');
}

int _qualityValue(PlayerResolvedStream stream) {
  final text =
      '${stream.quality ?? ''} ${stream.label ?? ''} ${stream.displayTitle ?? ''} ${stream.url}';
  if (text.toLowerCase().contains('4k')) return 2160;
  final match = RegExp(r'(\d{3,4})p?', caseSensitive: false).firstMatch(text);
  return int.tryParse(match?.group(1) ?? '') ?? 0;
}

int _formatRank(PlayerResolvedStream stream) {
  final text = '${stream.format ?? ''} ${stream.url}'.toLowerCase();
  if (text.contains('m3u8') || text.contains('hls')) return 0;
  if (text.contains('mp4')) return 1;
  if (text.contains('mkv')) return 3;
  return 2;
}

bool _isAdaptiveStream(PlayerResolvedStream stream) {
  final text = '${stream.format ?? ''} ${stream.url}'.toLowerCase();
  return text.contains('m3u8') || text.contains('hls') || text.contains('mpd');
}

String _cleanQuality(String? quality, String fallback) {
  final text = '${quality ?? ''} $fallback';
  if (text.toLowerCase().contains('4k')) return '2160P';
  final match = RegExp(r'(\d{3,4})p?', caseSensitive: false).firstMatch(text);
  if (match != null) return '${match.group(1)}P';
  final clean = (quality ?? '').trim();
  if (clean.isEmpty || clean.toLowerCase() == 'auto') return 'AUTO';
  return clean.toUpperCase();
}

List<PlayerEpisodePayload> _mergeEpisodes(
  List<PlayerEpisodePayload> existing,
  List<PlayerEpisodePayload> incoming,
) {
  final byKey = <String, PlayerEpisodePayload>{};
  for (final episode in [...existing, ...incoming]) {
    if (episode.episode <= 0) continue;
    byKey['${episode.season}:${episode.episode}'] = episode;
  }
  final merged = byKey.values.toList()
    ..sort((a, b) {
      final season = a.season.compareTo(b.season);
      return season != 0 ? season : a.episode.compareTo(b.episode);
    });
  return merged;
}

List<int> _availableSeasons(
  PlayerPayload? payload,
  List<PlayerEpisodePayload> episodes,
  int currentSeason,
) {
  final seasons = <int>{currentSeason};
  for (final episode in episodes) {
    if (episode.season > 0) seasons.add(episode.season);
  }
  final total = payload?.totalSeasons ?? 0;
  if (total > 0 && total <= 30) {
    for (var season = 1; season <= total; season++) {
      seasons.add(season);
    }
  }
  return seasons.toList()..sort();
}

List<PlayerEpisodePayload> _episodesForSeason(
  List<PlayerEpisodePayload> episodes,
  int selectedSeason,
  PlayerEpisodePayload fallbackEpisode,
) {
  final filtered =
      episodes
          .where(
            (episode) =>
                episode.season == selectedSeason &&
                episode.episode > 0 &&
                episode.title.trim().isNotEmpty,
          )
          .toList()
        ..sort((a, b) => a.episode.compareTo(b.episode));
  if (filtered.isNotEmpty) return filtered;
  return fallbackEpisode.season == selectedSeason
      ? [fallbackEpisode]
      : const [];
}

VideoAudioTrack? _preferredEnglishTrack(List<VideoAudioTrack> tracks) {
  for (final track in tracks) {
    if (_isEnglishTrack(track)) return track;
  }
  return null;
}

bool _isEnglishTrack(VideoAudioTrack track) {
  final language = (track.language ?? '').trim().toLowerCase();
  final label = (track.label ?? '').trim().toLowerCase();
  return language == 'en' ||
      language == 'eng' ||
      language == 'english' ||
      label.contains('english') ||
      RegExp(r'\beng\b').hasMatch(label);
}

String _subtitleTitle(PlayerSubtitlePayload track) {
  final language = _friendlyLanguage(track.language);
  final label = _cleanTrackText(track.label);
  if (language.isNotEmpty && label.isNotEmpty && language != label) {
    return '$language - $label';
  }
  if (language.isNotEmpty) return language;
  if (label.isNotEmpty) return label;
  return 'Subtitle';
}

String _friendlyLanguage(String? value) {
  final code = (value ?? '').trim().toLowerCase();
  if (code.isEmpty || code == 'und') return '';
  const languages = {
    'en': 'English',
    'eng': 'English',
    'es': 'Spanish',
    'spa': 'Spanish',
    'fr': 'French',
    'fre': 'French',
    'fra': 'French',
    'de': 'German',
    'ger': 'German',
    'deu': 'German',
    'it': 'Italian',
    'ita': 'Italian',
    'pt': 'Portuguese',
    'por': 'Portuguese',
    'hi': 'Hindi',
    'hin': 'Hindi',
    'ja': 'Japanese',
    'jpn': 'Japanese',
    'ko': 'Korean',
    'kor': 'Korean',
    'zh': 'Chinese',
    'chi': 'Chinese',
    'zho': 'Chinese',
  };
  return languages[code] ?? value!.trim();
}

String _cleanTrackText(String? value) {
  return (value ?? '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .replaceAll(RegExp(r'^(default|unknown|und)$', caseSensitive: false), '')
      .trim();
}

String _channelLabel(VideoAudioTrack track) {
  final count = track.channelCount;
  if (count == 6) return '5.1';
  if (count == 8) return '7.1';
  if (count == 2) return 'Stereo';
  if (count != null && count > 0) return '$count channels';
  return '';
}

String _statusText(bool initializing, String? error, bool buffering) {
  if (error != null) return 'Error';
  if (initializing) return 'Buffering';
  return buffering ? 'Buffering' : 'Paused';
}

String _seriesInfo(PlayerPayload? payload) {
  final parts = <String>[];
  if (payload?.season != null && payload?.episode != null) {
    parts.add(
      'S${payload!.season!.toString().padLeft(2, '0')}E${payload.episode!.toString().padLeft(2, '0')}',
    );
  }
  if ((payload?.episodeTitle ?? '').isNotEmpty) {
    parts.add(payload!.episodeTitle!);
  }
  if (payload?.runtime != null) parts.add('${payload!.runtime}m');
  return parts.join(' | ');
}

String _movieInfo(PlayerPayload? payload) {
  final parts = <String>[
    if ((payload?.year ?? '').isNotEmpty) payload!.year!,
    ...?payload?.genres.take(2),
    if (payload?.runtime != null) _formatRuntime(payload!.runtime!),
  ];
  return parts.join(' | ');
}

String _formatRuntime(int minutes) {
  final hours = minutes ~/ 60;
  final mins = minutes % 60;
  if (hours == 0) return '${mins}m';
  if (mins == 0) return '${hours}h';
  return '${hours}h ${mins}m';
}

String _formatDuration(Duration duration) {
  final totalSeconds = duration.inSeconds;
  final hours = totalSeconds ~/ 3600;
  final minutes = (totalSeconds % 3600) ~/ 60;
  final seconds = totalSeconds % 60;
  if (hours > 0) {
    return '$hours:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }
  return '$minutes:${seconds.toString().padLeft(2, '0')}';
}
