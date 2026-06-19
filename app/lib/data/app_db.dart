import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

part 'app_db.g.dart';

// ---------------------------------------------------------------------------
// Tables
// ---------------------------------------------------------------------------

/// User-added (BYO) IPTV sources. Backend-pushed sources are NOT stored here —
/// they are fetched live via get_sources_for_code and merged in the repository.
class LocalSources extends Table {
  TextColumn get id => text()(); // uuid
  TextColumn get kind => text()(); // 'xtream' | 'm3u'
  TextColumn get name => text()();
  TextColumn get serverUrl => text().nullable()();
  TextColumn get username => text().nullable()();
  TextColumn get password => text().nullable()();
  TextColumn get m3uUrl => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

/// Cached catalog rows. One generic table keyed by (sourceId, type, itemId)
/// keeps the schema small; `payload` holds the JSON-encoded model.
class CatalogItems extends Table {
  TextColumn get sourceId => text()();
  TextColumn get type => text()(); // 'live' | 'vod' | 'series'
  TextColumn get itemId => text()(); // stream_id / series_id
  TextColumn get categoryId => text().nullable()();
  TextColumn get title => text()();
  TextColumn get cleanTitle => text()(); // lowercased, for search
  TextColumn get payload => text()(); // JSON of the full model
  IntColumn get sortIndex => integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {sourceId, type, itemId};
}

/// Categories per source+type (so browsing can list them without re-deriving).
class CatalogCategories extends Table {
  TextColumn get sourceId => text()();
  TextColumn get type => text()();
  TextColumn get categoryId => text()();
  TextColumn get name => text()();

  @override
  Set<Column> get primaryKey => {sourceId, type, categoryId};
}

/// Netflix-style watch profiles.
class Profiles extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

/// Favorites, keyed by profile + item.
class Favorites extends Table {
  TextColumn get profileId => text()();
  TextColumn get itemKey => text()(); // "<sourceId>|<type>|<itemId>"
  TextColumn get type => text()();
  TextColumn get title => text()();
  TextColumn get payload => text()();
  DateTimeColumn get addedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {profileId, itemKey};
}

/// Resume / watch history, per profile.
class WatchHistory extends Table {
  TextColumn get profileId => text()();
  TextColumn get itemKey => text()();
  IntColumn get positionSecs => integer().withDefault(const Constant(0))();
  IntColumn get durationSecs => integer().nullable()();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {profileId, itemKey};
}

/// Downloaded VOD/episodes for offline playback.
class Downloads extends Table {
  TextColumn get itemKey => text()();
  TextColumn get title => text()();
  TextColumn get filePath => text()();
  IntColumn get bytes => integer().withDefault(const Constant(0))();
  TextColumn get status => text().withDefault(const Constant('pending'))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {itemKey};
}

// ---------------------------------------------------------------------------
// Database
// ---------------------------------------------------------------------------

@DriftDatabase(tables: [
  LocalSources,
  CatalogItems,
  CatalogCategories,
  Profiles,
  Favorites,
  WatchHistory,
  Downloads,
])
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? executor]) : super(executor ?? _open());

  @override
  int get schemaVersion => 1;

  static QueryExecutor _open() {
    return LazyDatabase(() async {
      final dir = await getApplicationDocumentsDirectory();
      final file = File(p.join(dir.path, 'zen_player.sqlite'));
      return NativeDatabase.createInBackground(file);
    });
  }
}
