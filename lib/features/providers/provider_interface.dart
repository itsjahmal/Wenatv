import '../../data/models/media_item.dart';

abstract interface class WenaStreamProvider {
  String get id;
  String get name;
  String get version;

  Future<List<ProviderSearchResult>> searchMovie(String query);
  Future<List<ProviderSearchResult>> searchSeries(String query);
  Future<List<StreamSource>> getMovieStreams(int tmdbId);
  Future<List<StreamSource>> getEpisodeStreams({
    required int tmdbId,
    required int season,
    required int episode,
  });
  Future<List<SubtitleTrack>> getSubtitles(StreamSource source);
  Future<List<AudioTrack>> getAudioTracks(StreamSource source);
  Future<ProviderHealth> healthCheck();
}

class ProviderSearchResult {
  const ProviderSearchResult({
    required this.title,
    required this.kind,
    required this.providerId,
    this.externalId,
  });

  final String title;
  final MediaKind kind;
  final String providerId;
  final String? externalId;
}

class StreamSource {
  const StreamSource({
    required this.url,
    required this.quality,
    required this.format,
    this.headers = const {},
    this.providerName,
    this.language,
    this.fileSize,
    this.label,
    this.displayTitle,
    this.season,
    this.episode,
    this.subtitles = const [],
  });

  final String url;
  final String quality;
  final String format;
  final Map<String, String> headers;
  final String? providerName;
  final String? language;
  final String? fileSize;
  final String? label;
  final String? displayTitle;
  final int? season;
  final int? episode;
  final List<SubtitleTrack> subtitles;

  StreamSource copyWith({
    String? providerName,
    String? language,
    String? fileSize,
    String? label,
    String? displayTitle,
    int? season,
    int? episode,
    List<SubtitleTrack>? subtitles,
  }) {
    return StreamSource(
      url: url,
      quality: quality,
      format: format,
      headers: headers,
      providerName: providerName ?? this.providerName,
      language: language ?? this.language,
      fileSize: fileSize ?? this.fileSize,
      label: label ?? this.label,
      displayTitle: displayTitle ?? this.displayTitle,
      season: season ?? this.season,
      episode: episode ?? this.episode,
      subtitles: subtitles ?? this.subtitles,
    );
  }
}

class SubtitleTrack {
  const SubtitleTrack({
    required this.label,
    required this.language,
    required this.url,
  });

  final String label;
  final String language;
  final String url;
}

class AudioTrack {
  const AudioTrack({required this.label, required this.language});

  final String label;
  final String language;
}

class ProviderHealth {
  const ProviderHealth({required this.ok, required this.message});

  final bool ok;
  final String message;
}
