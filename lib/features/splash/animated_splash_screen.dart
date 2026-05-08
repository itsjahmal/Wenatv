import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:video_player/video_player.dart';

import '../../core/startup/app_bootstrap.dart';
import '../../core/theme/app_theme.dart';

class AnimatedSplashScreen extends ConsumerStatefulWidget {
  const AnimatedSplashScreen({super.key});

  @override
  ConsumerState<AnimatedSplashScreen> createState() =>
      _AnimatedSplashScreenState();
}

class _AnimatedSplashScreenState extends ConsumerState<AnimatedSplashScreen>
    with SingleTickerProviderStateMixin {
  static const _animationAsset = 'assets/animations/boot_logo_animation.mp4';
  static const _posterAsset = 'assets/animations/boot_logo_poster.jpg';
  static const _fallbackLogoAsset = 'assets/branding/startuplogo.png';

  late final AnimationController _fadeController;
  late final Future<void> _bootstrapFuture;
  VideoPlayerController? _videoController;
  Timer? _safetyTimer;
  bool _videoReady = false;
  bool _usingFallback = false;
  bool _navigated = false;

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
      value: 1,
    );
    _bootstrapFuture = ref.read(appBootstrapProvider);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _initVideo();
    });
    _safetyTimer = Timer(const Duration(seconds: 12), _enterHome);
  }

  Future<void> _initVideo() async {
    final controller = VideoPlayerController.asset(
      _animationAsset,
      videoPlayerOptions: VideoPlayerOptions(mixWithOthers: false),
    );
    _videoController = controller;
    try {
      await controller.initialize().timeout(const Duration(seconds: 4));
      await controller.setLooping(false);
      await controller.setVolume(1.0);
      controller.addListener(_onVideoTick);
      if (!mounted || _videoController != controller) return;
      await controller.play();
      if (!mounted || _videoController != controller) return;
      setState(() => _videoReady = true);
    } catch (_) {
      await controller.dispose();
      if (!mounted || _navigated) return;
      setState(() => _usingFallback = true);
      Timer(const Duration(milliseconds: 2200), _enterHome);
    }
  }

  void _onVideoTick() {
    final controller = _videoController;
    if (controller == null || !controller.value.isInitialized || _navigated) {
      return;
    }
    final value = controller.value;
    if (value.hasError) {
      setState(() => _usingFallback = true);
      Timer(const Duration(milliseconds: 1400), _enterHome);
      return;
    }
    final duration = value.duration;
    if (duration > Duration.zero &&
        value.position >= duration - const Duration(milliseconds: 120)) {
      _enterHome();
    }
  }

  Future<void> _enterHome() async {
    if (_navigated || !mounted) return;
    _navigated = true;
    _safetyTimer?.cancel();
    try {
      await _bootstrapFuture;
    } catch (_) {
      // Startup should still continue when optional services such as Firebase
      // fail; required Hive boxes are opened before this future completes.
    }
    await _fadeController.reverse();
    if (!mounted) return;
    context.go('/');
  }

  @override
  void dispose() {
    _safetyTimer?.cancel();
    final controller = _videoController;
    controller?.removeListener(_onVideoTick);
    unawaited(controller?.dispose());
    _fadeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: WenaTheme.black,
      body: FadeTransition(
        opacity: _fadeController,
        child: Stack(
          fit: StackFit.expand,
          children: [
            const ColoredBox(color: WenaTheme.black),
            if (!_usingFallback) const _BootPoster(),
            if (_videoReady && !_usingFallback)
              _ContainedVideo(controller: _videoController!)
            else if (_usingFallback)
              const _StaticFallbackLogo(),
          ],
        ),
      ),
    );
  }
}

class _ContainedVideo extends StatelessWidget {
  const _ContainedVideo({required this.controller});

  final VideoPlayerController controller;

  @override
  Widget build(BuildContext context) {
    final aspectRatio = controller.value.aspectRatio == 0
        ? 16 / 9
        : controller.value.aspectRatio;
    return LayoutBuilder(
      builder: (context, constraints) {
        final screenRatio = constraints.maxWidth / constraints.maxHeight;
        final width = screenRatio > aspectRatio
            ? constraints.maxHeight * aspectRatio
            : constraints.maxWidth;
        final height = width / aspectRatio;
        return Center(
          child: SizedBox(
            width: width,
            height: height,
            child: VideoPlayer(controller),
          ),
        );
      },
    );
  }
}

class _BootPoster extends StatelessWidget {
  const _BootPoster();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Image.asset(
        _AnimatedSplashScreenState._posterAsset,
        fit: BoxFit.contain,
        width: double.infinity,
        height: double.infinity,
        filterQuality: FilterQuality.high,
        errorBuilder: (_, __, ___) => const SizedBox.shrink(),
      ),
    );
  }
}

class _StaticFallbackLogo extends StatelessWidget {
  const _StaticFallbackLogo();

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final logoSize = (size.shortestSide * .34).clamp(160.0, 260.0);
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: RadialGradient(
          center: const Alignment(0, -.05),
          radius: 1.05,
          colors: [
            WenaTheme.red.withValues(alpha: .16),
            const Color(0xFF090707),
            WenaTheme.black,
          ],
          stops: const [0, .38, 1],
        ),
      ),
      child: Center(
        child: Image.asset(
          _AnimatedSplashScreenState._fallbackLogoAsset,
          width: logoSize,
          height: logoSize,
          fit: BoxFit.contain,
          filterQuality: FilterQuality.high,
        ),
      ),
    );
  }
}
