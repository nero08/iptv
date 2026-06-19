import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zen_player/tmdb/tmdb_models.dart';
import 'package:zen_player/tmdb/tmdb_service.dart';

class _Stub implements HttpClientAdapter {
  _Stub(this.body, [this.status = 200]);
  final String body;
  final int status;
  @override
  void close({bool force = false}) {}
  @override
  Future<ResponseBody> fetch(o, s, c) async => ResponseBody.fromString(body, status,
      headers: {Headers.contentTypeHeader: [Headers.jsonContentType]});
}

TmdbService _svc(String body, {String key = 'k', int status = 200}) {
  final dio = Dio(BaseOptions(baseUrl: 'https://api.themoviedb.org/3'));
  dio.httpClientAdapter = _Stub(body, status);
  return TmdbService(dio: dio, apiKey: key);
}

void main() {
  test('TmdbMeta builds full image URL from poster_path', () {
    final m = TmdbMeta.fromJson({
      'poster_path': '/abc.jpg',
      'overview': 'A film',
      'vote_average': 7.5,
      'release_date': '2020-01-01',
    });
    expect(m.posterUrl, 'https://image.tmdb.org/t/p/w500/abc.jpg');
    expect(m.overview, 'A film');
    expect(m.voteAverage, 7.5);
  });

  test('byId parses a movie response', () async {
    final svc = _svc(jsonEncode({'poster_path': '/p.jpg', 'overview': 'Plot'}));
    final m = await svc.byId('movie', 603);
    expect(m, isNotNull);
    expect(m!.posterUrl, 'https://image.tmdb.org/t/p/w500/p.jpg');
    expect(m.overview, 'Plot');
  });

  test('no-key -> disabled, byId returns null (graceful fallback)', () async {
    final svc = _svc('{}', key: '');
    expect(svc.enabled, false);
    expect(await svc.byId('movie', 1), isNull);
  });

  test('non-200 returns null without throwing', () async {
    final svc = _svc('{"status_message":"not found"}', status: 404);
    expect(await svc.byId('movie', 999), isNull);
  });

  test('searchFirst returns first result meta', () async {
    final svc = _svc(jsonEncode({
      'results': [
        {'poster_path': '/s.jpg', 'overview': 'Found'},
        {'poster_path': '/other.jpg'},
      ]
    }));
    final m = await svc.searchFirst('movie', 'Matrix', year: '1999');
    expect(m?.posterUrl, 'https://image.tmdb.org/t/p/w500/s.jpg');
    expect(m?.overview, 'Found');
  });

  test('empty overview becomes null', () {
    final m = TmdbMeta.fromJson({'poster_path': '/p.jpg', 'overview': '   '});
    expect(m.overview, isNull);
  });
}
