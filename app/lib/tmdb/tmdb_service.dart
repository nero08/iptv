import 'package:dio/dio.dart';

import '../core/config.dart';
import 'tmdb_models.dart';

/// Enriches VOD/series detail with TMDB artwork/overview when a TMDB API key is
/// configured. Degrades gracefully (returns null) when no key is set or on any
/// failure — callers fall back to Xtream-provided art. Responses cached
/// in-memory by (type,id) to avoid refetching on every detail open.
class TmdbService {
  TmdbService({Dio? dio, String? apiKey})
      : _apiKey = apiKey ?? AppConfig.tmdbKey,
        _dio = dio ?? Dio(BaseOptions(baseUrl: 'https://api.themoviedb.org/3'));

  final Dio _dio;
  final String _apiKey;
  final Map<String, TmdbMeta?> _cache = {};

  bool get enabled => _apiKey.isNotEmpty;

  /// Fetch by TMDB id ('movie' or 'tv'). Returns null when disabled/missing.
  Future<TmdbMeta?> byId(String type, int tmdbId) async {
    if (!enabled) return null;
    final key = '$type/$tmdbId';
    if (_cache.containsKey(key)) return _cache[key];
    try {
      final res = await _dio.get<dynamic>('/$type/$tmdbId',
          queryParameters: {'api_key': _apiKey, 'language': 'fr-FR'},
          options: Options(validateStatus: (_) => true));
      if (res.statusCode == 200 && res.data is Map) {
        final meta = TmdbMeta.fromJson((res.data as Map).cast<String, dynamic>());
        _cache[key] = meta;
        return meta;
      }
    } catch (_) {/* fall through */}
    _cache[key] = null;
    return null;
  }

  /// Fallback search by title (+ optional year). Returns the first hit's meta.
  Future<TmdbMeta?> searchFirst(String type, String title, {String? year}) async {
    if (!enabled || title.trim().isEmpty) return null;
    try {
      final res = await _dio.get<dynamic>('/search/$type',
          queryParameters: {
            'api_key': _apiKey,
            'language': 'fr-FR',
            'query': title,
            if (year != null && year.isNotEmpty)
              (type == 'movie' ? 'year' : 'first_air_date_year'): year,
          },
          options: Options(validateStatus: (_) => true));
      if (res.statusCode == 200 && res.data is Map) {
        final results = (res.data as Map)['results'];
        if (results is List && results.isNotEmpty && results.first is Map) {
          return TmdbMeta.fromJson((results.first as Map).cast<String, dynamic>());
        }
      }
    } catch (_) {/* fall through */}
    return null;
  }
}
