class ApiConfig {
  const ApiConfig._();

  static const tmdbBaseUrl = 'https://api.themoviedb.org/3';
  static const tmdbImageBaseUrl = 'https://image.tmdb.org/t/p';
  static const tmdbApiKey = 'ebe8e02ae76242ede7a0c88e7bbcdfe8';
  static const tmdbReadAccessToken =
      'eyJhbGciOiJIUzI1NiJ9.eyJhdWQiOiJlYmU4ZTAyYWU3NjI0MmVkZTdhMGM4OGU3YmJjZGZlOCIsIm5iZiI6MTc2MDY4NjExNC42MzEsInN1YiI6IjY4ZjFmMDIyM2U5ZWE4M2I0YTBlNDc4ZCIsInNjb3BlcyI6WyJhcGlfcmVhZF0sInZlcnNpb24iOjF9.-i8VxPYkQu8y2IOWIyxE8oP_507gOTTg5PqKxovyhJQ';

  static String poster(String? path, {String size = 'w500'}) =>
      path == null || path.isEmpty ? '' : '$tmdbImageBaseUrl/$size$path';

  static String backdrop(String? path, {String size = 'w1280'}) =>
      path == null || path.isEmpty ? '' : '$tmdbImageBaseUrl/$size$path';
}
