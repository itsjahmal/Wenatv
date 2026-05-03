import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/models/media_item.dart';
import '../../features/details/details_screen.dart';
import '../../features/home/home_screen.dart';
import '../../features/player/player_screen.dart';
import '../../features/search/search_screen.dart';
import '../../features/settings/settings_screen.dart';
import '../../features/splash/animated_splash_screen.dart';
import '../../features/trailer/trailer_screen.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/splash',
    routes: [
      GoRoute(
        path: '/splash',
        builder: (context, state) => const AnimatedSplashScreen(),
      ),
      GoRoute(
        path: '/',
        pageBuilder: (context, state) => CustomTransitionPage<void>(
          key: state.pageKey,
          child: HomeScreen(section: state.uri.queryParameters['section']),
          transitionDuration: const Duration(milliseconds: 480),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return FadeTransition(opacity: animation, child: child);
          },
        ),
      ),
      GoRoute(
        path: '/search',
        builder: (context, state) => const SearchScreen(),
      ),
      GoRoute(path: '/movies', redirect: (_, __) => '/?section=movies'),
      GoRoute(path: '/tv', redirect: (_, __) => '/?section=tv'),
      GoRoute(path: '/trending', redirect: (_, __) => '/?section=trending'),
      GoRoute(path: '/watchlist', redirect: (_, __) => '/?section=watchlist'),
      GoRoute(
        path: '/settings',
        builder: (context, state) => const SettingsScreen(),
      ),
      GoRoute(
        path: '/details/:kind/:id',
        builder: (context, state) => DetailsScreen(
          id: int.parse(state.pathParameters['id']!),
          kind: state.pathParameters['kind'] == 'tv'
              ? MediaKind.tv
              : MediaKind.movie,
          initialItem: state.extra as MediaItem?,
        ),
      ),
      GoRoute(
        path: '/player',
        builder: (context, state) =>
            PlayerScreen(payload: state.extra as PlayerPayload?),
      ),
      GoRoute(
        path: '/trailer/:kind/:id',
        builder: (context, state) => TrailerScreen(
          id: int.parse(state.pathParameters['id']!),
          kind: state.pathParameters['kind'] == 'tv'
              ? MediaKind.tv
              : MediaKind.movie,
          title: (state.extra as String?) ?? 'Trailer',
        ),
      ),
    ],
  );
});
