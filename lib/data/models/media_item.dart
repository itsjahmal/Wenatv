enum MediaKind { movie, tv }

class MediaItem {
  const MediaItem({
    required this.id,
    required this.kind,
    required this.title,
    required this.overview,
    required this.posterPath,
    required this.backdropPath,
    required this.rating,
    required this.releaseDate,
    this.genres = const [],
    this.runtime,
    this.totalSeasons,
    this.externalPosterUrl,
    this.externalBackdropUrl,
    this.sourceUrl,
    this.sourceProvider,
    this.sourceProviderName,
    this.sourceLink,
    this.sourceTitle,
  });

  final int id;
  final MediaKind kind;
  final String title;
  final String overview;
  final String? posterPath;
  final String? backdropPath;
  final double rating;
  final String releaseDate;
  final List<String> genres;
  final int? runtime;
  final int? totalSeasons;
  final String? externalPosterUrl;
  final String? externalBackdropUrl;
  final String? sourceUrl;
  final String? sourceProvider;
  final String? sourceProviderName;
  final String? sourceLink;
  final String? sourceTitle;

  factory MediaItem.fromJson(
    Map<String, dynamic> json,
    MediaKind fallbackKind,
  ) {
    final mediaType = json['media_type'];
    final kind = mediaType == 'tv'
        ? MediaKind.tv
        : mediaType == 'movie'
        ? MediaKind.movie
        : fallbackKind;
    return MediaItem(
      id: json['id'] as int? ?? 0,
      kind: kind,
      title: (json['title'] ?? json['name'] ?? 'Untitled').toString(),
      overview: (json['overview'] ?? '').toString(),
      posterPath: json['poster_path'] as String?,
      backdropPath: json['backdrop_path'] as String?,
      rating: ((json['vote_average'] as num?) ?? 0).toDouble(),
      releaseDate: (json['release_date'] ?? json['first_air_date'] ?? '')
          .toString(),
      genres: ((json['genres'] as List?) ?? const [])
          .map((genre) => (genre as Map<String, dynamic>)['name'].toString())
          .toList(),
      runtime: json['runtime'] as int?,
      totalSeasons: json['number_of_seasons'] as int?,
    );
  }

  String get year => releaseDate.length >= 4 ? releaseDate.substring(0, 4) : '';

  MediaItem copyWith({
    int? id,
    MediaKind? kind,
    String? title,
    String? overview,
    String? posterPath,
    String? backdropPath,
    double? rating,
    String? releaseDate,
    List<String>? genres,
    int? runtime,
    int? totalSeasons,
    String? externalPosterUrl,
    String? externalBackdropUrl,
    String? sourceUrl,
    String? sourceProvider,
    String? sourceProviderName,
    String? sourceLink,
    String? sourceTitle,
  }) {
    return MediaItem(
      id: id ?? this.id,
      kind: kind ?? this.kind,
      title: title ?? this.title,
      overview: overview ?? this.overview,
      posterPath: posterPath ?? this.posterPath,
      backdropPath: backdropPath ?? this.backdropPath,
      rating: rating ?? this.rating,
      releaseDate: releaseDate ?? this.releaseDate,
      genres: genres ?? this.genres,
      runtime: runtime ?? this.runtime,
      totalSeasons: totalSeasons ?? this.totalSeasons,
      externalPosterUrl: externalPosterUrl ?? this.externalPosterUrl,
      externalBackdropUrl: externalBackdropUrl ?? this.externalBackdropUrl,
      sourceUrl: sourceUrl ?? this.sourceUrl,
      sourceProvider: sourceProvider ?? this.sourceProvider,
      sourceProviderName: sourceProviderName ?? this.sourceProviderName,
      sourceLink: sourceLink ?? this.sourceLink,
      sourceTitle: sourceTitle ?? this.sourceTitle,
    );
  }
}

class EpisodeItem {
  const EpisodeItem({
    required this.id,
    required this.season,
    required this.number,
    required this.title,
    required this.overview,
    required this.stillPath,
    this.runtime,
  });

  final int id;
  final int season;
  final int number;
  final String title;
  final String overview;
  final String? stillPath;
  final int? runtime;

  factory EpisodeItem.fromJson(Map<String, dynamic> json, int season) {
    return EpisodeItem(
      id: json['id'] as int? ?? 0,
      season: season,
      number: json['episode_number'] as int? ?? 0,
      title: (json['name'] ?? 'Episode').toString(),
      overview: (json['overview'] ?? '').toString(),
      stillPath: json['still_path'] as String?,
      runtime: json['runtime'] as int?,
    );
  }
}

class CastMember {
  const CastMember({
    required this.name,
    required this.character,
    required this.profilePath,
  });

  final String name;
  final String character;
  final String? profilePath;

  factory CastMember.fromJson(Map<String, dynamic> json) {
    return CastMember(
      name: (json['name'] ?? 'Unknown').toString(),
      character: (json['character'] ?? '').toString(),
      profilePath: json['profile_path'] as String?,
    );
  }
}
