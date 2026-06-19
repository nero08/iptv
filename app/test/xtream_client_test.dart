import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zen_player/iptv/xtream_client.dart';
import 'package:zen_player/iptv/models.dart';

/// Returns canned JSON keyed by the `action` query param (or the no-action
/// validation call).
class _XtreamStubAdapter implements HttpClientAdapter {
  _XtreamStubAdapter(this.byAction);
  final Map<String, String> byAction;

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<List<int>>? requestStream, Future<void>? cancelFuture) async {
    final action = options.queryParameters['action'] as String? ?? '_validate';
    final body = byAction[action] ?? '[]';
    return ResponseBody.fromString(body, 200, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    });
  }
}

XtreamClient _client(Map<String, String> byAction) {
  final dio = Dio();
  dio.httpClientAdapter = _XtreamStubAdapter(byAction);
  return XtreamClient(
    serverUrl: 'http://portal.example:8080',
    username: 'user1',
    password: 'pass1',
    dio: dio,
  );
}

void main() {
  group('stream URL builders', () {
    final c = _client({});
    test('live URL', () {
      expect(c.liveStreamUrl(1234),
          'http://portal.example:8080/live/user1/pass1/1234.ts');
    });
    test('vod URL uses container extension', () {
      expect(c.vodStreamUrl(55, 'mkv'),
          'http://portal.example:8080/movie/user1/pass1/55.mkv');
    });
    test('series episode URL', () {
      expect(c.seriesStreamUrl('900', 'mp4'),
          'http://portal.example:8080/series/user1/pass1/900.mp4');
    });
    test('trailing slash in server URL is normalized', () {
      final c2 = XtreamClient(
          serverUrl: 'http://portal.example:8080/',
          username: 'u',
          password: 'p',
          dio: Dio());
      expect(c2.liveStreamUrl(7), 'http://portal.example:8080/live/u/p/7.ts');
    });
  });

  group('fetchSourceInfo', () {
    test('parses user_info with string-encoded numbers', () async {
      final c = _client({
        '_validate': jsonEncode({
          'user_info': {
            'status': 'Active',
            'max_connections': '2', // string number
            'active_cons': '1',
            'auth': 1,
            'exp_date': '1893456000',
          },
          'server_info': {'url': 'portal.example'}
        }),
      });
      final info = await c.fetchSourceInfo();
      expect(info.status, 'Active');
      expect(info.maxConnections, 2);
      expect(info.activeConnections, 1);
      expect(info.isActive, true);
      expect(info.expDate, isNotNull);
    });
  });

  group('catalog parsing', () {
    test('live categories + streams', () async {
      final c = _client({
        'get_live_categories':
            jsonEncode([{'category_id': '1', 'category_name': 'News'}]),
        'get_live_streams': jsonEncode([
          {'stream_id': '101', 'name': 'CNN', 'stream_icon': 'http://i/c.png',
           'category_id': '1', 'epg_channel_id': 'cnn.us'},
          // a quirky row: numeric name, missing icon
          {'stream_id': 102, 'name': 'BBC', 'category_id': '1'},
        ]),
      });
      final cats = await c.liveCategories();
      expect(cats, hasLength(1));
      expect(cats.first.name, 'News');
      final channels = await c.liveStreams('1');
      expect(channels, hasLength(2));
      expect(channels[0].streamId, 101);
      expect(channels[0].epgChannelId, 'cnn.us');
      expect(channels[1].streamId, 102);
      expect(channels[1].icon, isNull);
    });

    test('vod info nested shape', () async {
      final c = _client({
        'get_vod_info': jsonEncode({
          'info': {
            'plot': 'A film',
            'genre': 'Drama',
            'tmdb_id': '603',
            'duration_secs': '7200',
            'movie_image': 'http://i/p.jpg',
          },
          'movie_data': {'stream_id': '55', 'container_extension': 'mkv'},
        }),
      });
      final vi = await c.vodInfo(55);
      expect(vi.streamId, 55);
      expect(vi.containerExtension, 'mkv');
      expect(vi.plot, 'A film');
      expect(vi.tmdbId, 603);
      expect(vi.durationSecs, 7200);
    });

    test('series info seasons -> episodes', () async {
      final c = _client({
        'get_series_info': jsonEncode({
          'info': {'plot': 'A show', 'genre': 'SciFi'},
          'episodes': {
            '1': [
              {'id': '900', 'title': 'Pilot', 'container_extension': 'mp4',
               'episode_num': '1', 'season': '1',
               'info': {'duration_secs': '2700'}},
            ],
            '2': [
              {'id': '950', 'title': 'S2E1', 'container_extension': 'mkv',
               'episode_num': 1, 'season': 2, 'info': {}},
            ],
          },
        }),
      });
      final si = await c.seriesInfo(42);
      expect(si.plot, 'A show');
      expect(si.seasons, hasLength(2));
      expect(si.seasons[0].number, 1);
      expect(si.seasons[0].episodes.first.id, '900');
      expect(si.seasons[0].episodes.first.containerExtension, 'mp4');
      expect(si.seasons[1].number, 2);
    });
  });

  group('coercion helpers', () {
    test('asInt handles strings, doubles, null, empty', () {
      expect(asInt('42'), 42);
      expect(asInt(3.9), 3);
      expect(asInt(''), 0);
      expect(asInt(null, 7), 7);
      expect(asInt('not-a-number', 5), 5);
    });
    test('asStringOrNull treats empty/whitespace as null', () {
      expect(asStringOrNull(''), isNull);
      expect(asStringOrNull('  '), isNull);
      expect(asStringOrNull('x'), 'x');
      expect(asStringOrNull(0), '0');
    });
  });
}
