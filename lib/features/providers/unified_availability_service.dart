import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/media_item.dart';
import 'provider_js_bridge.dart';
import 'provider_manager_controller.dart';

final unifiedAvailabilityServiceProvider = Provider<UnifiedAvailabilityService>(
  (ref) =>
      UnifiedAvailabilityService(bridge: ref.watch(providerJsBridgeProvider)),
);

final unifiedAvailabilityProvider =
    FutureProvider.family<
      UnifiedAvailabilityResult,
      UnifiedAvailabilityRequest
    >((ref, request) async {
      final providers = ref.watch(providerFallbackOrderProvider);
      return ref
          .watch(unifiedAvailabilityServiceProvider)
          .scan(request: request, providers: providers);
    });

class UnifiedAvailabilityRequest {
  const UnifiedAvailabilityRequest({
    required this.tmdbShowId,
    required this.showTitle,
    required this.episodes,
    this.imdbId,
    this.firstAirYear,
    this.providerPriority = const ['vega', 'autoEmbed', 'flixhq', 'showbox'],
  });

  final int tmdbShowId;
  final String showTitle;
  final List<EpisodeItem> episodes;
  final String? imdbId;
  final int? firstAirYear;
  final List<String> providerPriority;

  @override
  bool operator ==(Object other) {
    return other is UnifiedAvailabilityRequest &&
        other.tmdbShowId == tmdbShowId &&
        other.showTitle == showTitle &&
        other.imdbId == imdbId &&
        other.firstAirYear == firstAirYear &&
        other.providerPriority.join('|') == providerPriority.join('|') &&
        other.episodes.length == episodes.length &&
        other.episodes.map(_episodeKey).join('|') ==
            episodes.map(_episodeKey).join('|');
  }

  @override
  int get hashCode => Object.hash(
    tmdbShowId,
    showTitle,
    imdbId,
    firstAirYear,
    providerPriority.join('|'),
    episodes.map(_episodeKey).join('|'),
  );
}

class ProviderEpisodeMatch {
  const ProviderEpisodeMatch({
    required this.providerValue,
    required this.providerLink,
    required this.seasonNumber,
    required this.episodeNumber,
    required this.confidence,
    required this.matchedBy,
    this.providerDisplayName,
    this.providerSourceUrl,
    this.streamLink,
    this.title,
  });

  final String providerValue;
  final String? providerDisplayName;
  final String? providerSourceUrl;
  final String providerLink;
  final String? streamLink;
  final int seasonNumber;
  final int episodeNumber;
  final String? title;
  final double confidence;
  final String matchedBy;

  String get key =>
      '$providerSourceUrl::$providerValue::$seasonNumber::$episodeNumber::$providerLink';
}

class UnifiedEpisodeAvailability {
  const UnifiedEpisodeAvailability({
    required this.tmdbId,
    required this.showTitle,
    required this.seasonNumber,
    required this.episodeNumber,
    required this.providers,
    required this.playable,
    required this.availabilityStatus,
    this.imdbId,
    this.episodeTitle,
    this.airDate,
    this.overview,
    this.stillPath,
    this.bestProvider,
  });

  final int tmdbId;
  final String? imdbId;
  final String showTitle;
  final int seasonNumber;
  final int episodeNumber;
  final String? episodeTitle;
  final String? airDate;
  final String? overview;
  final String? stillPath;
  final List<ProviderEpisodeMatch> providers;
  final ProviderEpisodeMatch? bestProvider;
  final bool playable;
  final String availabilityStatus;
}

class UnifiedAvailabilityResult {
  const UnifiedAvailabilityResult({
    required this.tmdbShowId,
    required this.providerPriority,
    required this.generatedAt,
    required this.episodes,
    required this.providerAttempts,
  });

  final int tmdbShowId;
  final List<String> providerPriority;
  final int generatedAt;
  final Map<String, UnifiedEpisodeAvailability> episodes;
  final List<ProviderAvailabilityAttempt> providerAttempts;
}

class ProviderAvailabilityAttempt {
  const ProviderAvailabilityAttempt({
    required this.providerValue,
    required this.status,
    this.matchedTitle,
    this.matchedBy,
    this.episodeMatchesFound,
    this.error,
  });

  final String providerValue;
  final String status;
  final String? matchedTitle;
  final String? matchedBy;
  final int? episodeMatchesFound;
  final String? error;
}

class UnifiedAvailabilityService {
  const UnifiedAvailabilityService({required ProviderJsBridge bridge})
    : _bridge = bridge;

  final ProviderJsBridge _bridge;

  Future<UnifiedAvailabilityResult> scan({
    required UnifiedAvailabilityRequest request,
    required List<ActiveProviderSelection> providers,
  }) async {
    final attempts = <ProviderAvailabilityAttempt>[];
    final matches = <ProviderEpisodeMatch>[];

    for (final provider in providers) {
      if (provider.value == 'autoEmbed') {
        attempts.add(
          const ProviderAvailabilityAttempt(
            providerValue: 'autoEmbed',
            status: 'skipped',
            matchedBy: 'playback_time',
            episodeMatchesFound: 0,
          ),
        );
        continue;
      }
      try {
        final providerMatches = await _scanProvider(
          request: request,
          provider: provider,
        ).timeout(const Duration(seconds: 35));
        matches.addAll(providerMatches);
        attempts.add(
          ProviderAvailabilityAttempt(
            providerValue: provider.value,
            status: providerMatches.isEmpty ? 'empty' : 'success',
            episodeMatchesFound: providerMatches.length,
            matchedBy: providerMatches.isEmpty
                ? null
                : providerMatches.first.matchedBy,
            matchedTitle: providerMatches.isEmpty
                ? null
                : providerMatches.first.title,
          ),
        );
      } catch (error) {
        attempts.add(
          ProviderAvailabilityAttempt(
            providerValue: provider.value,
            status: 'failed',
            error: error.toString(),
          ),
        );
      }
    }

    return UnifiedAvailabilityResult(
      tmdbShowId: request.tmdbShowId,
      providerPriority: request.providerPriority,
      generatedAt: DateTime.now().millisecondsSinceEpoch,
      episodes: mergeProviderAvailabilityIntoTmdbEpisodes(
        tmdbShowId: request.tmdbShowId,
        showTitle: request.showTitle,
        imdbId: request.imdbId,
        tmdbEpisodes: request.episodes,
        providerMatches: matches,
        providerPriority: request.providerPriority,
        complete: true,
      ),
      providerAttempts: attempts,
    );
  }

  Future<List<ProviderEpisodeMatch>> _scanProvider({
    required UnifiedAvailabilityRequest request,
    required ActiveProviderSelection provider,
  }) async {
    final posts = await _bridge.searchPosts(
      sourceUrl: provider.sourceUrl,
      providerValue: provider.value,
      query: request.showTitle,
    );
    if (posts.isEmpty) return const [];

    final post = _bestPostMatch(posts, request.showTitle, request.firstAirYear);
    if (post == null) return const [];

    final meta = await _bridge.getMeta(
      sourceUrl: provider.sourceUrl,
      providerValue: provider.value,
      link: post.link,
    );
    if (meta == null) return const [];

    final episodeLinks = <ProviderEpisodeLink>[];
    for (final group in meta.linkList) {
      for (final direct in group.directLinks) {
        episodeLinks.add(
          ProviderEpisodeLink(
            groupTitle: group.title,
            title: direct.title,
            link: direct.link,
          ),
        );
      }
      if (group.episodesLink.isNotEmpty) {
        final episodes = await _bridge.getEpisodes(
          sourceUrl: provider.sourceUrl,
          providerValue: provider.value,
          episodesLink: group.episodesLink,
        );
        for (final episode in episodes) {
          episodeLinks.add(
            ProviderEpisodeLink(
              groupTitle: group.title,
              title: episode.title,
              link: episode.link,
            ),
          );
        }
      }
    }

    return normalizeProviderEpisodes(
      providerValue: provider.value,
      providerDisplayName: provider.displayName,
      providerSourceUrl: provider.sourceUrl,
      links: episodeLinks,
      showTitle: request.showTitle,
    );
  }
}

List<ProviderEpisodeMatch> normalizeProviderEpisodes({
  required String providerValue,
  required String providerDisplayName,
  required String providerSourceUrl,
  required List<ProviderEpisodeLink> links,
  required String showTitle,
}) {
  final dedupe = <String, ProviderEpisodeMatch>{};
  for (var index = 0; index < links.length; index++) {
    final link = links[index];
    final text = '${link.groupTitle} ${link.title}';
    final parsed = _parseEpisodeKey(text);
    if (parsed == null) continue;
    final key = '$providerValue:${parsed.$1}:${parsed.$2}:${link.link}';
    dedupe[key] = ProviderEpisodeMatch(
      providerValue: providerValue,
      providerDisplayName: providerDisplayName,
      providerSourceUrl: providerSourceUrl,
      providerLink: link.link,
      seasonNumber: parsed.$1,
      episodeNumber: parsed.$2,
      title: link.title.isEmpty ? showTitle : link.title,
      confidence: parsed.$3,
      matchedBy: parsed.$4,
    );
  }
  return dedupe.values.toList();
}

Map<String, UnifiedEpisodeAvailability>
mergeProviderAvailabilityIntoTmdbEpisodes({
  required int tmdbShowId,
  required String showTitle,
  required String? imdbId,
  required List<EpisodeItem> tmdbEpisodes,
  required List<ProviderEpisodeMatch> providerMatches,
  required List<String> providerPriority,
  required bool complete,
}) {
  final matchesByEpisode = <String, List<ProviderEpisodeMatch>>{};
  for (final match in providerMatches) {
    matchesByEpisode
        .putIfAbsent(_key(match.seasonNumber, match.episodeNumber), () => [])
        .add(match);
  }

  final result = <String, UnifiedEpisodeAvailability>{};
  for (final episode in tmdbEpisodes) {
    final key = _episodeKey(episode);
    final matches = <ProviderEpisodeMatch>[
      ...matchesByEpisode[key] ?? const <ProviderEpisodeMatch>[],
    ];
    matches.sort((a, b) {
      final priority = _priorityRank(
        a.providerValue,
        providerPriority,
      ).compareTo(_priorityRank(b.providerValue, providerPriority));
      if (priority != 0) return priority;
      return b.confidence.compareTo(a.confidence);
    });
    final playable = matches.isNotEmpty;
    result[key] = UnifiedEpisodeAvailability(
      tmdbId: tmdbShowId,
      imdbId: imdbId,
      showTitle: showTitle,
      seasonNumber: episode.season,
      episodeNumber: episode.number,
      episodeTitle: episode.title,
      overview: episode.overview,
      stillPath: episode.stillPath,
      providers: matches,
      bestProvider: matches.isEmpty ? null : matches.first,
      playable: playable,
      availabilityStatus: playable
          ? 'playable'
          : complete
          ? 'unavailable'
          : 'loading',
    );
  }
  return result;
}

ProviderPost? _bestPostMatch(
  List<ProviderPost> posts,
  String title,
  int? year,
) {
  final normalized = _normalizeTitle(title);
  ProviderPost? best;
  var bestScore = 0.0;
  for (final post in posts) {
    final candidate = _normalizeTitle(post.title);
    if (candidate.isEmpty) continue;
    var score = _titleScore(normalized, candidate);
    if (year != null && post.title.contains(year.toString())) score += .12;
    if (candidate == normalized) score += .25;
    if (!_looksLikeSeriesRelease(post.title)) score -= .2;
    if (score > bestScore) {
      bestScore = score;
      best = post;
    }
  }
  return bestScore >= .58 ? best : null;
}

(int, int, double, String)? _parseEpisodeKey(String text) {
  final normalized = text.replaceAll(RegExp(r'[._-]+'), ' ');
  final patterns = <RegExp>[
    RegExp(
      r'\bS(?:eason)?\s*(\d{1,2})\s*E(?:p(?:isode)?)?\s*(\d{1,3})\b',
      caseSensitive: false,
    ),
    RegExp(r'\b(\d{1,2})x(\d{1,3})\b', caseSensitive: false),
    RegExp(
      r'\bSeason\s*(\d{1,2}).{0,40}?\b(?:Episode|Ep)\s*(\d{1,3})\b',
      caseSensitive: false,
    ),
  ];
  for (final pattern in patterns) {
    final match = pattern.firstMatch(normalized);
    if (match != null) {
      final season = int.tryParse(match.group(1) ?? '');
      final episode = int.tryParse(match.group(2) ?? '');
      if (season != null && episode != null) {
        return (season, episode, .98, 'season_episode');
      }
    }
  }

  final season = RegExp(
    r'\bSeason\s*(\d{1,2})\b',
    caseSensitive: false,
  ).firstMatch(normalized);
  final episode = RegExp(
    r'\b(?:Episode|Ep|E)\s*(\d{1,3})\b',
    caseSensitive: false,
  ).firstMatch(normalized);
  if (episode != null) {
    final seasonNumber = int.tryParse(season?.group(1) ?? '') ?? 1;
    final episodeNumber = int.tryParse(episode.group(1) ?? '');
    if (episodeNumber != null) {
      return (
        seasonNumber,
        episodeNumber,
        season == null ? .78 : .9,
        'season_episode',
      );
    }
  }
  return null;
}

String _normalizeTitle(String value) {
  return value
      .toLowerCase()
      .replaceFirst(RegExp(r'^download\s+', caseSensitive: false), '')
      .replaceAll(RegExp(r'\[[^\]]*\]|\([^)]*\)|\{[^}]*\}'), ' ')
      .replaceAll(RegExp(r'\b(19|20)\d{2}\b'), '')
      .replaceAll(
        RegExp(
          r'\b(480p|720p|1080p|2160p|4k|uhd|hdr|sdr|hevc|x264|x265|10bit|web[- ]?dl|webrip|bluray|brrip|hdrip|dual audio|multi audio|hindi|english|esub|nf|amzn)\b',
          caseSensitive: false,
        ),
        ' ',
      )
      .replaceAll(
        RegExp(
          r'\b(S\d{1,2}\s*E\d{1,3}(?:\s*-\s*\d{1,3})?|Season\s*\d+|Episode\s*\d+|Ep\s*\d+)\b',
          caseSensitive: false,
        ),
        ' ',
      )
      .replaceAll(
        RegExp(
          r'\b(Prime Video|Amazon Prime Video|Amazon Prime|Netflix|Disney\+|Hotstar|HBO Max|Apple TV|Hulu)\b',
          caseSensitive: false,
        ),
        ' ',
      )
      .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

double _titleScore(String a, String b) {
  if (a.isEmpty || b.isEmpty) return 0;
  if (a == b) return 1;
  if (a.contains(b) || b.contains(a)) return .82;
  final left = a.split(' ').toSet();
  final right = b.split(' ').toSet();
  final shared = left.intersection(right).length;
  final total = left.union(right).length;
  return total == 0 ? 0 : shared / total;
}

bool _looksLikeSeriesRelease(String value) {
  return RegExp(
    r'\b(S\d{1,2}\s*E\d{1,3}|Season\s*\d+|Episode\s*\d+|Ep\s*\d+)\b',
    caseSensitive: false,
  ).hasMatch(value);
}

int _priorityRank(String value, List<String> priority) {
  final index = priority
      .map((item) => item.toLowerCase())
      .toList()
      .indexOf(value.toLowerCase());
  return index == -1 ? 999 : index;
}

String _episodeKey(EpisodeItem episode) => _key(episode.season, episode.number);

String _key(int season, int episode) => 's${season}e$episode';

class ProviderEpisodeLink {
  const ProviderEpisodeLink({
    required this.groupTitle,
    required this.title,
    required this.link,
  });

  final String groupTitle;
  final String title;
  final String link;
}
