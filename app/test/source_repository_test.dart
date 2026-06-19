import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zen_player/data/app_db.dart';
import 'package:zen_player/sources/source_models.dart';
import 'package:zen_player/sources/source_repository.dart';

import '_sqlite_setup.dart';

void main() {
  setUpAll(useSystemSqlite);

  late AppDatabase db;
  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() async => db.close());

  test('allSources merges backend + local with backend-wins dedup', () async {
    // backend returns one xtream source on host h:8080 / user u
    final backendRows = [
      {
        'id': 'b1', 'kind': 'xtream', 'name': 'Admin Portal',
        'server_url': 'http://h:8080', 'username': 'u', 'password': 'p',
        'm3u_url': null,
      }
    ];
    final repo = SourceRepository(
      db: db,
      fetchBackend: () async => backendRows,
    );

    // local has the SAME endpoint (should be hidden by backend) + a distinct one
    await repo.addLocalXtream(
        name: 'Mine dup', serverUrl: 'http://h:8080', username: 'u', password: 'p');
    await repo.addLocalXtream(
        name: 'Other', serverUrl: 'http://other:8080', username: 'x', password: 'y');

    final all = await repo.allSources();
    // dup endpoint collapses to the backend one -> 2 total
    expect(all, hasLength(2));
    final byKey = {for (final s in all) s.dedupKey: s};
    expect(byKey['xtream|h:8080|u']!.origin, SourceOrigin.backend,
        reason: 'backend wins on conflict');
    expect(byKey['xtream|other:8080|x']!.origin, SourceOrigin.local);
  });

  test('local-only when backend returns nothing', () async {
    final repo = SourceRepository(db: db, fetchBackend: () async => []);
    await repo.addLocalM3u(name: 'My list', m3uUrl: 'http://h/list.m3u');
    final all = await repo.allSources();
    expect(all, hasLength(1));
    expect(all.first.kind, SourceKind.m3u);
    expect(all.first.origin, SourceOrigin.local);
  });

  test('removeLocal deletes a local source', () async {
    final repo = SourceRepository(db: db, fetchBackend: () async => []);
    final s = await repo.addLocalXtream(
        name: 'Tmp', serverUrl: 'http://h:8080', username: 'u', password: 'p');
    expect((await repo.allSources()), hasLength(1));
    await repo.removeLocal(s.id);
    expect((await repo.allSources()), isEmpty);
  });
}
