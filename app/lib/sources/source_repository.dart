import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../auth/auth_controller.dart';
import '../data/app_db.dart';
import 'source_models.dart';

/// Merges admin-assigned sources (from `get_sources_for_code`) with
/// user-added local sources (drift). Backend sources are read-only; local
/// sources are full CRUD. Backend wins on dedup conflicts.
class SourceRepository {
  SourceRepository({
    required AppDatabase db,
    required Future<List<Map<String, dynamic>>> Function() fetchBackend,
  })  : _db = db,
        _fetchBackend = fetchBackend;

  final AppDatabase _db;
  final Future<List<Map<String, dynamic>>> Function() _fetchBackend;

  /// All sources: backend ∪ local, deduped by [IptvSource.dedupKey]
  /// (backend wins). Backend fetch failures degrade to local-only.
  Future<List<IptvSource>> allSources() async {
    final result = <String, IptvSource>{};

    // local first
    for (final s in await _localSources()) {
      result[s.dedupKey] = s;
    }
    // backend overrides on conflict
    try {
      for (final row in await _fetchBackend()) {
        final s = IptvSource.fromBackendRow(row);
        result[s.dedupKey] = s;
      }
    } catch (_) {
      // offline / no backend sources — keep local-only
    }
    return result.values.toList();
  }

  Future<List<IptvSource>> _localSources() async {
    final rows = await _db.select(_db.localSources).get();
    return rows
        .map((r) => IptvSource(
              id: r.id,
              origin: SourceOrigin.local,
              kind: IptvSource.kindFromString(r.kind),
              name: r.name,
              serverUrl: r.serverUrl,
              username: r.username,
              password: r.password,
              m3uUrl: r.m3uUrl,
            ))
        .toList();
  }

  Future<IptvSource> addLocalXtream({
    required String name,
    required String serverUrl,
    required String username,
    required String password,
  }) async {
    final id = const Uuid().v4();
    await _db.into(_db.localSources).insert(LocalSourcesCompanion.insert(
          id: id,
          kind: 'xtream',
          name: name,
          serverUrl: Value(serverUrl),
          username: Value(username),
          password: Value(password),
        ));
    return IptvSource(
      id: id,
      origin: SourceOrigin.local,
      kind: SourceKind.xtream,
      name: name,
      serverUrl: serverUrl,
      username: username,
      password: password,
    );
  }

  Future<IptvSource> addLocalM3u({
    required String name,
    required String m3uUrl,
  }) async {
    final id = const Uuid().v4();
    await _db.into(_db.localSources).insert(LocalSourcesCompanion.insert(
          id: id,
          kind: 'm3u',
          name: name,
          m3uUrl: Value(m3uUrl),
        ));
    return IptvSource(
      id: id,
      origin: SourceOrigin.local,
      kind: SourceKind.m3u,
      name: name,
      m3uUrl: m3uUrl,
    );
  }

  Future<void> removeLocal(String id) async {
    await (_db.delete(_db.localSources)..where((t) => t.id.equals(id))).go();
  }
}

// --- providers --------------------------------------------------------------

final appDatabaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});

/// Repository wired to the live backend: pulls the current code + device id
/// from auth and calls `get_sources_for_code`.
final sourceRepositoryProvider = Provider<SourceRepository>((ref) {
  final db = ref.watch(appDatabaseProvider);
  final svc = ref.watch(supabaseServiceProvider);
  final auth = ref.watch(authControllerProvider.notifier);
  final dev = ref.watch(deviceIdProvider);
  return SourceRepository(
    db: db,
    fetchBackend: () async {
      final code = await auth.currentCode();
      if (code == null) return const [];
      final id = await dev.deviceId();
      return svc.getSourcesForCode(code, id);
    },
  );
});

/// The merged source list (re-evaluated when invalidated after add/remove).
final sourceListProvider = FutureProvider<List<IptvSource>>((ref) async {
  return ref.watch(sourceRepositoryProvider).allSources();
});
