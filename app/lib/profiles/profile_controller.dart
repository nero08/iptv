import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../data/app_db.dart';
import '../sources/source_repository.dart';

/// Manages watch profiles (Netflix-style). Ensures a default profile exists,
/// tracks the active profile, and supports create/rename/delete.
class ProfileController {
  ProfileController(this._db);
  final AppDatabase _db;

  Future<List<Profile>> all() => _db.select(_db.profiles).get();

  /// Returns existing profiles, creating a "Profil 1" default if none exist.
  Future<List<Profile>> ensureDefault() async {
    final existing = await all();
    if (existing.isNotEmpty) return existing;
    await create('Profil 1');
    return all();
  }

  Future<Profile> create(String name) async {
    final id = const Uuid().v4();
    await _db.into(_db.profiles).insert(
        ProfilesCompanion.insert(id: id, name: name));
    return (_db.select(_db.profiles)..where((t) => t.id.equals(id)))
        .getSingle();
  }

  Future<void> rename(String id, String name) async {
    await (_db.update(_db.profiles)..where((t) => t.id.equals(id)))
        .write(ProfilesCompanion(name: Value(name)));
  }

  Future<void> delete(String id) async {
    await (_db.delete(_db.profiles)..where((t) => t.id.equals(id))).go();
    // cascade app-side: drop this profile's favorites + history
    await (_db.delete(_db.favorites)..where((t) => t.profileId.equals(id))).go();
    await (_db.delete(_db.watchHistory)..where((t) => t.profileId.equals(id))).go();
  }
}

final profileControllerProvider = Provider<ProfileController>(
    (ref) => ProfileController(ref.watch(appDatabaseProvider)));

/// All profiles (refreshable).
final profilesProvider = FutureProvider<List<Profile>>((ref) async {
  return ref.watch(profileControllerProvider).ensureDefault();
});

/// Active profile id. Defaults to the first profile once loaded.
final activeProfileIdProvider = StateProvider<String?>((ref) => null);
