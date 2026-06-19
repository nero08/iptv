import 'dart:convert';

import 'package:dio/dio.dart';

import 'models.dart';

/// Pure-Dart Xtream Codes client. Talks to `<server>/player_api.php` with
/// `username`/`password`/`action` params, parses the JSON, and builds playable
/// stream URLs. Replaces the original Rust `libiptv_loader`.
class XtreamClient {
  XtreamClient({
    required String serverUrl,
    required this.username,
    required this.password,
    Dio? dio,
  }) : server = _normalize(serverUrl),
       _dio =
           dio ??
           Dio(
             BaseOptions(
               connectTimeout: const Duration(seconds: 15),
               receiveTimeout: const Duration(seconds: 60),
             ),
           );

  final String server;
  final String username;
  final String password;
  final Dio _dio;

  static String _normalize(String url) {
    var u = url.trim();
    while (u.endsWith('/')) {
      u = u.substring(0, u.length - 1);
    }
    return u;
  }

  // --- stream URL builders -------------------------------------------------
  String liveStreamUrl(int streamId, {String ext = 'ts'}) =>
      '$server/live/$username/$password/$streamId.$ext';

  String vodStreamUrl(int streamId, String containerExtension) =>
      '$server/movie/$username/$password/$streamId.$containerExtension';

  String seriesStreamUrl(String episodeId, String containerExtension) =>
      '$server/series/$username/$password/$episodeId.$containerExtension';

  // --- API calls -----------------------------------------------------------
  Future<dynamic> _call(String? action, [Map<String, dynamic>? extra]) async {
    final res = await _dio.get<dynamic>(
      '$server/player_api.php',
      queryParameters: {
        'username': username,
        'password': password,
        if (action != null) 'action': action,
        ...?extra,
      },
      options: Options(responseType: ResponseType.json),
    );
    var data = res.data;
    // Some portals send JSON with a text/html content-type, so Dio leaves it as
    // a String; decode defensively.
    if (data is String) {
      try {
        data = data.isEmpty ? <dynamic>[] : jsonDecode(data);
      } catch (_) {
        data = <dynamic>[];
      }
    }
    return data;
  }

  // --- raw API calls -------------------------------------------------------
  // Return the response body as a String (no JSON decode on the caller's
  // isolate) so the catalog can be decoded/parsed off the UI thread.
  Future<String> _callRaw(String? action, [Map<String, dynamic>? extra]) async {
    final res = await _dio.get<String>(
      '$server/player_api.php',
      queryParameters: {
        'username': username,
        'password': password,
        if (action != null) 'action': action,
        ...?extra,
      },
      options: Options(responseType: ResponseType.plain),
    );
    return res.data ?? '';
  }

  Future<String> rawLiveCategories() => _callRaw('get_live_categories');
  Future<String> rawLiveStreams() => _callRaw('get_live_streams');
  Future<String> rawVodCategories() => _callRaw('get_vod_categories');
  Future<String> rawVodStreams() => _callRaw('get_vod_streams');
  Future<String> rawSeriesCategories() => _callRaw('get_series_categories');
  Future<String> rawSeries() => _callRaw('get_series');

  List<Map<String, dynamic>> _asList(dynamic data) {
    if (data is List) {
      return data
          .whereType<Map>()
          .map((e) => e.cast<String, dynamic>())
          .toList();
    }
    return const [];
  }

  /// No-action call -> {user_info, server_info}. Used to validate a source.
  Future<SourceInfo> fetchSourceInfo() async {
    final data = await _call(null);
    if (data is Map) {
      return SourceInfo.fromJson(data.cast<String, dynamic>());
    }
    throw const FormatException('Unexpected source-info response');
  }

  Future<List<Category>> liveCategories() async => _asList(
    await _call('get_live_categories'),
  ).map(Category.fromJson).toList();

  Future<List<LiveChannel>> liveStreams([String? categoryId]) async => _asList(
    await _call(
      'get_live_streams',
      categoryId != null ? {'category_id': categoryId} : null,
    ),
  ).map(LiveChannel.fromJson).toList();

  Future<List<Category>> vodCategories() async => _asList(
    await _call('get_vod_categories'),
  ).map(Category.fromJson).toList();

  Future<List<VodItem>> vodStreams([String? categoryId]) async => _asList(
    await _call(
      'get_vod_streams',
      categoryId != null ? {'category_id': categoryId} : null,
    ),
  ).map(VodItem.fromJson).toList();

  Future<VodInfo> vodInfo(int vodId) async {
    final data = await _call('get_vod_info', {'vod_id': vodId});
    if (data is Map) return VodInfo.fromJson(data.cast<String, dynamic>());
    throw const FormatException('Unexpected vod_info response');
  }

  Future<List<Category>> seriesCategories() async => _asList(
    await _call('get_series_categories'),
  ).map(Category.fromJson).toList();

  Future<List<SeriesItem>> series([String? categoryId]) async => _asList(
    await _call(
      'get_series',
      categoryId != null ? {'category_id': categoryId} : null,
    ),
  ).map(SeriesItem.fromJson).toList();

  Future<SeriesInfo> seriesInfo(int seriesId) async {
    final data = await _call('get_series_info', {'series_id': seriesId});
    if (data is Map) return SeriesInfo.fromJson(data.cast<String, dynamic>());
    throw const FormatException('Unexpected series_info response');
  }

  /// Short EPG for a live stream (base64 titles decoded by EpgService later).
  Future<List<Map<String, dynamic>>> shortEpg(
    int streamId, {
    int limit = 4,
  }) async {
    final data = await _call('get_short_epg', {
      'stream_id': streamId,
      'limit': limit,
    });
    if (data is Map && data['epg_listings'] is List) {
      return (data['epg_listings'] as List)
          .whereType<Map>()
          .map((e) => e.cast<String, dynamic>())
          .toList();
    }
    return const [];
  }
}
