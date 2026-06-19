import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zen_player/data/app_db.dart';
import 'package:zen_player/favorites/favorites_controller.dart';
import 'package:zen_player/profiles/profile_controller.dart';

import '_sqlite_setup.dart';

void main() {
  setUpAll(useSystemSqlite);

  late AppDatabase db;
  late ProfileController profiles;
  late FavoritesController favs;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    profiles = ProfileController(db);
    favs = FavoritesController(db);
  });
  tearDown(() async => db.close());

  test('ensureDefault creates a default profile once', () async {
    final p1 = await profiles.ensureDefault();
    expect(p1, hasLength(1));
    final p2 = await profiles.ensureDefault();
    expect(p2, hasLength(1), reason: 'does not duplicate');
  });

  test('favorites are per-profile and toggle on/off', () async {
    final a = await profiles.create('A');
    final b = await profiles.create('B');
    final key = FavoritesController.key('s1', 'live', '101');

    await favs.toggle(profileId: a.id, itemKey: key, type: 'live', title: 'CNN');
    expect(await favs.isFavorite(a.id, key), true);
    expect(await favs.isFavorite(b.id, key), false,
        reason: 'favorite is scoped to profile A');

    expect((await favs.list(a.id)), hasLength(1));
    expect((await favs.list(b.id)), isEmpty);

    // toggle off
    await favs.toggle(profileId: a.id, itemKey: key, type: 'live', title: 'CNN');
    expect(await favs.isFavorite(a.id, key), false);
    expect((await favs.list(a.id)), isEmpty);
  });

  test('watch history resume position round-trips per profile', () async {
    final a = await profiles.create('A');
    final key = FavoritesController.key('s1', 'vod', '55');
    expect(await favs.resumePosition(a.id, key), 0);
    await favs.saveProgress(
        profileId: a.id, itemKey: key, positionSecs: 360, durationSecs: 7200);
    expect(await favs.resumePosition(a.id, key), 360);
    // overwrite (insertOrReplace)
    await favs.saveProgress(profileId: a.id, itemKey: key, positionSecs: 500);
    expect(await favs.resumePosition(a.id, key), 500);
  });

  test('deleting a profile clears its favorites + history', () async {
    final a = await profiles.create('A');
    final key = FavoritesController.key('s1', 'live', '101');
    await favs.toggle(profileId: a.id, itemKey: key, type: 'live', title: 'CNN');
    await favs.saveProgress(profileId: a.id, itemKey: key, positionSecs: 10);
    await profiles.delete(a.id);
    expect((await favs.list(a.id)), isEmpty);
    expect(await favs.resumePosition(a.id, key), 0);
  });
}
