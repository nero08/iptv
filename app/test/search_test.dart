import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zen_player/data/app_db.dart';
import 'package:zen_player/iptv/iptv_repository.dart';

import '_sqlite_setup.dart';

void main() {
  setUpAll(useSystemSqlite);

  late AppDatabase db;
  late IptvRepository repo;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    repo = IptvRepository(db);
    // seed a small catalog
    await db.batch((b) {
      b.insertAll(db.catalogItems, [
        CatalogItemsCompanion.insert(
            sourceId: 's1', type: 'live', itemId: '1',
            title: 'CNN News', cleanTitle: 'cnn news',
            payload: jsonEncode({'stream_id': 1, 'name': 'CNN News'})),
        CatalogItemsCompanion.insert(
            sourceId: 's1', type: 'vod', itemId: '2',
            title: 'The Newsroom', cleanTitle: 'the newsroom',
            payload: jsonEncode({'stream_id': 2, 'name': 'The Newsroom'})),
        CatalogItemsCompanion.insert(
            sourceId: 's1', type: 'series', itemId: '3',
            title: 'Breaking Bad', cleanTitle: 'breaking bad',
            payload: jsonEncode({'series_id': 3, 'name': 'Breaking Bad'})),
      ]);
    });
  });
  tearDown(() async => db.close());

  test('search matches title case-insensitively, scoped to type', () async {
    final live = await repo.search('s1', 'live', 'news');
    expect(live, hasLength(1));
    expect(live.first.title, 'CNN News');

    final vod = await repo.search('s1', 'vod', 'NEWS'); // case-insensitive
    expect(vod, hasLength(1));
    expect(vod.first.title, 'The Newsroom');

    final series = await repo.search('s1', 'series', 'break');
    expect(series, hasLength(1));
  });

  test('empty query returns nothing', () async {
    expect(await repo.search('s1', 'live', ''), isEmpty);
    expect(await repo.search('s1', 'live', '   '), isEmpty);
  });

  test('no match returns empty', () async {
    expect(await repo.search('s1', 'vod', 'zzzznomatch'), isEmpty);
  });
}
