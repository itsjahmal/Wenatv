import 'package:dio/dio.dart';
import 'package:dio_smart_retry/dio_smart_retry.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/api_config.dart';

final dioProvider = Provider<Dio>((ref) {
  final dio = Dio(
    BaseOptions(
      baseUrl: ApiConfig.tmdbBaseUrl,
      connectTimeout: const Duration(seconds: 9),
      receiveTimeout: const Duration(seconds: 12),
      headers: {
        'Authorization': 'Bearer ${ApiConfig.tmdbReadAccessToken}',
        'accept': 'application/json',
      },
    ),
  );
  dio.interceptors.add(
    RetryInterceptor(
      dio: dio,
      retries: 2,
      retryDelays: const [
        Duration(milliseconds: 800),
        Duration(seconds: 2),
      ],
      retryEvaluator: (error, attempt) =>
          error.type != DioExceptionType.cancel &&
          error.type != DioExceptionType.badResponse,
    ),
  );
  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (options, handler) {
        options.queryParameters.putIfAbsent(
          'api_key',
          () => ApiConfig.tmdbApiKey,
        );
        handler.next(options);
      },
      onError: (error, handler) {
        final response = error.response;
        if (response?.statusCode == 401 &&
            error.requestOptions.headers.containsKey('Authorization')) {
          final retryOptions = error.requestOptions;
          retryOptions.headers.remove('Authorization');
          retryOptions.queryParameters.putIfAbsent(
            'api_key',
            () => ApiConfig.tmdbApiKey,
          );
          dio
              .fetch<dynamic>(retryOptions)
              .then(handler.resolve, onError: handler.next);
          return;
        }
        handler.next(error);
      },
    ),
  );
  return dio;
});
