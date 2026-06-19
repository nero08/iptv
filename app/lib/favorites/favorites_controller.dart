import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/app_db.dart';
import '../profiles/profile_controller.dart';
import '../sources/source_repository.dart';

/// Per-profile favorites + watch-history. Favorites are keyed by
/// `<sourceId>|<type>|<itemId>` so they are stable across catalog refreshes.
class FavoritesController {
  FavoritesController(this._db);
  final AppDatabase _db;

  static String key(String sourceId, String type, String itemId) =>
      '$sourceId|$type|$itemId';

  Future<bool> isFavorite(String profileId, String itemKey) async {
    final row = await (_db.select(_db.favorites)
          ..where((t) => t.profileId.equals(profileId) & t.itemKey.equals(itemKey)))
        .getSingleOrNull();
    return row != null;
  }

  Future<void> toggle({
    required String profileId,
    required String itemKey,
    required String type,
    required String title,
    String payload = '{}',
  }) async {
    if (await isFavorite(profileId, itemKey)) {
      await (_db.delete(_db.favorites)
            ..where((t) => t.profileId.equals(profileId) & t.itemKey.equals(itemKey)))
          .go();
    } else {
      await _db.into(_db.favorites).insert(
            FavoritesCompanion.insert(
                profileId: profileId,
                itemKey: itemKey,
                type: type,
                title: title,
                payload: payload),
            mode: InsertMode.insertOrReplace,
          );
    }
  }

  Future<List<Favorite>> list(String profileId) =>
      (_db.select(_db.favorites)..where((t) => t.profileId.equals(profileId)))
          .get();

  // --- watch history / resume ---
  Future<void> saveProgress({
    required String profileId,
    required String itemKey,
    required int positionSecs,
    int? durationSecs,
  }) async {
    await _db.into(_db.watchHistory).insert(
          WatchHistoryCompanion.insert(
            profileId: profileId,
            itemKey: itemKey,
            positionSecs: Value(positionSecs),
            durationSecs: Value(durationSecs),
          ),
          mode: InsertMode.insertOrReplace,
        );
  }

  Future<int> resumePosition(String profileId, String itemKey) async {
    final row = await (_db.select(_db.watchHistory)
          ..where((t) => t.profileId.equals(profileId) & t.itemKey.equals(itemKey)))
        .getSingleOrNull();
    return row?.positionSecs ?? 0;
  }
}

final favoritesControllerProvider = Provider<FavoritesController>(
    (ref) => FavoritesController(ref.watch(appDatabaseProvider)));

/// Favorites for the active profile (refreshable list).
final favoritesListProvider = FutureProvider.autoDispose<List<Favorite>>((ref) async {
  final pid = ref.watch(activeProfileIdProvider);
  if (pid == null) return const [];
  return ref.watch(favoritesControllerProvider).list(pid);
});
