import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zen_player/data/app_db.dart';
import 'package:zen_player/iptv/iptv_repository.dart';
import 'package:zen_player/iptv/models.dart';
import 'package:zen_player/sources/source_models.dart';

import '_sqlite_setup.dart';

void main() {
  setUpAll(useSystemSqlite);

  late AppDatabase db;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
  });
  tearDown(() async => db.close());

  test('drift round-trips a local source + cached channels', () async {
    // insert a local source
    await db.into(db.localSources).insert(LocalSourcesCompanion.insert(
          id: 's1',
          kind: 'xtream',
          name: 'My Portal',
          serverUrl: const Value('http://h:8080'),
          username: const Value('u'),
          password: const Value('p'),
        ));
    final src = await db.select(db.localSources).getSingle();
    expect(src.name, 'My Portal');
    expect(src.kind, 'xtream');

    // insert two cached live items
    await db.batch((b) {
      b.insertAll(db.catalogItems, [
        CatalogItemsCompanion.insert(
          sourceId: 's1', type: 'live', itemId: '101',
          categoryId: const Value('news'),
          title: 'CNN', cleanTitle: 'cnn',
          payload: jsonEncode({'stream_id': 101, 'name': 'CNN'}),
          sortIndex: const Value(0),
        ),
        CatalogItemsCompanion.insert(
          sourceId: 's1', type: 'live', itemId: '102',
          categoryId: const Value('news'),
          title: 'BBC', cleanTitle: 'bbc',
          payload: jsonEncode({'stream_id': 102, 'name': 'BBC'}),
          sortIndex: const Value(1),
        ),
      ]);
    });

    final rows = await (db.select(db.catalogItems)
          ..where((t) => t.sourceId.equals('s1') & t.type.equals('live'))
          ..orderBy([(t) => OrderingTerm(expression: t.sortIndex)]))
        .get();
    expect(rows, hasLength(2));
    expect(rows.first.title, 'CNN');
    final payload = jsonDecode(rows.first.payload) as Map<String, dynamic>;
    expect(payload['stream_id'], 101);
  });

  test('loadCatalog is cache-first: no network when catalog already cached',
      () async {
    // Seed a cached live item so the source counts as "has catalog".
    await db.into(db.catalogItems).insert(CatalogItemsCompanion.insert(
          sourceId: 's1', type: 'live', itemId: '101',
          title: 'CNN', cleanTitle: 'cnn',
          payload: jsonEncode({'stream_id': 101, 'name': 'CNN'}),
        ));
    final repo = IptvRepository(db);
    expect(await repo.hasCatalog('s1'), isTrue);

    final xtream = IptvSource(
      id: 's1',
      origin: SourceOrigin.local,
      kind: SourceKind.xtream,
      name: 'Portal',
      // Unroutable: any network attempt would throw and fail this test.
      serverUrl: 'http://10.255.255.1:1',
      username: 'u',
      password: 'p',
    );
    // force:false + cache present => returns immediately, never touches network.
    await repo.loadCatalog(xtream);
    expect(await repo.hasCatalog('s1'), isTrue);
  });

  test('hasCatalog is false for an empty source', () async {
    expect(await IptvRepository(db).hasCatalog('nope'), isFalse);
  });

  test('loadCatalog (xtream) parses off-isolate without an unsendable crash',
      () async {
    // Regression: the off-isolate parse closure must not capture `this`
    // (IptvRepository -> AppDatabase/drift is unsendable), otherwise
    // Isolate.run throws "Illegal argument in isolate message" on catalog load.
    final dio = Dio();
    dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      final body = switch (options.queryParameters['action']) {
        'get_live_categories' => '[{"category_id":"1","category_name":"News"}]',
        'get_live_streams' =>
          '[{"stream_id":101,"name":"CNN","category_id":"1"}]',
        _ => '[]',
      };
      handler.resolve(
          Response(requestOptions: options, data: body, statusCode: 200));
    }));
    final repo = IptvRepository(db, dio: dio);
    final src = IptvSource(
      id: 's1',
      origin: SourceOrigin.local,
      kind: SourceKind.xtream,
      name: 'Portal',
      serverUrl: 'http://h:8080',
      username: 'u',
      password: 'p',
    );

    await repo.loadCatalog(src, force: true); // must not throw

    expect((await repo.categories('s1', 'live')).map((c) => c.name),
        contains('News'));
    expect((await repo.liveChannels('s1')).map((c) => c.name), contains('CNN'));
  });

  test('liveUrl resolves an M3U channel from its cached direct_url', () {
    // Regression: an M3U channel read back from the cache must keep its
    // direct_url, otherwise liveUrl falls through to the Xtream branch and
    // dereferences serverUrl! (null for M3U) — silently throwing in the tap
    // handler so the player never opens.
    final repo = IptvRepository(db);
    final m3u = IptvSource(
      id: 's1',
      origin: SourceOrigin.local,
      kind: SourceKind.m3u,
      name: 'Playlist',
      m3uUrl: 'http://host/list.m3u',
    );
    // Payload exactly as the repository stores an M3U channel.
    final ch = LiveChannel.fromJson(
        {'name': 'CNN', 'stream_id': 0, 'direct_url': 'http://host/cnn.ts'});
    expect(ch.directUrl, 'http://host/cnn.ts');
    expect(repo.liveUrl(m3u, ch), 'http://host/cnn.ts');
  });

  test('profiles + favorites + watch history tables work', () async {
    await db.into(db.profiles).insert(
        ProfilesCompanion.insert(id: 'p1', name: 'Default'));
    await db.into(db.favorites).insert(FavoritesCompanion.insert(
          profileId: 'p1', itemKey: 's1|live|101', type: 'live',
          title: 'CNN', payload: '{}',
        ));
    await db.into(db.watchHistory).insert(WatchHistoryCompanion.insert(
          profileId: 'p1', itemKey: 's1|vod|55',
          positionSecs: const Value(120),
        ));

    final favs = await (db.select(db.favorites)
          ..where((t) => t.profileId.equals('p1')))
        .get();
    expect(favs, hasLength(1));
    final hist = await db.select(db.watchHistory).getSingle();
    expect(hist.positionSecs, 120);
  });
}
