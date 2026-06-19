import 'dart:convert';
import 'dart:isolate';
// Uint8List is used directly below; keep the import explicit rather than relying
// on drift's transitive re-export.
// ignore: unnecessary_import
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:drift/drift.dart';

import '../data/app_db.dart';
import '../sources/source_models.dart';
import 'm3u_parser.dart';
import 'models.dart';
import 'xtream_client.dart';

/// Unifies Xtream and M3U sources behind one interface, backed by a drift
/// catalog cache. UI reads from the cache (fast, offline-capable); network
/// refresh is explicit via [loadCatalog].
class IptvRepository {
  IptvRepository(this._db, {Dio? dio}) : _dio = dio ?? Dio();

  final AppDatabase _db;
  final Dio _dio;

  XtreamClient _xtream(IptvSource s) => XtreamClient(
    serverUrl: s.serverUrl!,
    username: s.username!,
    password: s.password!,
    dio: _dio,
  );

  // --- catalog refresh -----------------------------------------------------

  /// Download a source's catalog and persist it to the cache. For Xtream this
  /// fetches categories + live/vod/series; for M3U it downloads + parses the
  /// playlist into live channels.
  ///
  /// Cache-first: when [force] is false and the cache is already populated this
  /// returns immediately without any network call (so app relaunch is instant).
  /// Pass `force: true` for the background refresh and the manual reload button.
  Future<void> loadCatalog(IptvSource s, {bool force = false}) async {
    if (!force && await hasCatalog(s.id)) return;
    if (s.kind == SourceKind.xtream) {
      await _loadXtream(s);
    } else {
      await _loadM3u(s);
    }
  }

  /// True when this source already has a cached catalog (any media type).
  Future<bool> hasCatalog(String sourceId) async {
    for (final t in const ['live', 'vod', 'series']) {
      if (await itemCount(sourceId, t) > 0) return true;
    }
    return false;
  }

  Future<void> _loadXtream(IptvSource s) async {
    final x = _xtream(s);
    // Network I/O on the UI isolate (async, non-blocking); bodies kept as raw
    // strings so no JSON is decoded here.
    final raw = _XtreamRaw(
      liveCats: await x.rawLiveCategories(),
      live: await x.rawLiveStreams(),
      vodCats: await x.rawVodCategories(),
      vod: await x.rawVodStreams(),
      seriesCats: await x.rawSeriesCategories(),
      series: await x.rawSeries(),
    );
    // Decode + map + jsonEncode for thousands of items off the UI isolate to
    // avoid the frame drops seen during the background refresh.
    final parsed = await _runParseXtream(raw);

    await _db.transaction(() async {
      await _clearSource(s.id);
      await _putCategories(s.id, 'live', parsed.liveCats);
      await _putCategories(s.id, 'vod', parsed.vodCats);
      await _putCategories(s.id, 'series', parsed.seriesCats);
      await _putItems(s.id, 'live', parsed.live);
      await _putItems(s.id, 'vod', parsed.vod);
      await _putItems(s.id, 'series', parsed.series);
    });
  }

  Future<void> _loadM3u(IptvSource s) async {
    final res = await _dio.get<List<int>>(
      s.m3uUrl!,
      options: Options(responseType: ResponseType.bytes),
    );
    // Defensive: dio normally yields List<int> for ResponseType.bytes, but a
    // misbehaving adapter/middleware could hand back something else — never let
    // Uint8List.fromList throw on a non-list body.
    final raw = res.data;
    final bytes = raw is List<int> ? Uint8List.fromList(raw) : Uint8List(0);
    // Decode + parse the playlist off the UI isolate.
    final parsed = await _runParseM3u(bytes);

    await _db.transaction(() async {
      await _clearSource(s.id);
      await _putCategories(s.id, 'live', parsed.cats);
      await _putItems(s.id, 'live', parsed.items);
    });
  }

  // --- cache reads (used by browse screens) --------------------------------

  Future<List<Category>> categories(String sourceId, String type) async {
    final rows = await (_db.select(
      _db.catalogCategories,
    )..where((t) => t.sourceId.equals(sourceId) & t.type.equals(type))).get();
    return rows.map((r) => Category(id: r.categoryId, name: r.name)).toList();
  }

  Future<List<LiveChannel>> liveChannels(
    String sourceId, {
    String? categoryId,
  }) async {
    final rows = await _itemRows(sourceId, 'live', categoryId);
    return rows
        .map(
          (r) => LiveChannel.fromJson(
            jsonDecode(r.payload) as Map<String, dynamic>,
          ),
        )
        .toList();
  }

  Future<List<VodItem>> vodItems(String sourceId, {String? categoryId}) async {
    final rows = await _itemRows(sourceId, 'vod', categoryId);
    return rows
        .map(
          (r) =>
              VodItem.fromJson(jsonDecode(r.payload) as Map<String, dynamic>),
        )
        .toList();
  }

  Future<List<SeriesItem>> seriesItems(
    String sourceId, {
    String? categoryId,
  }) async {
    final rows = await _itemRows(sourceId, 'series', categoryId);
    return rows
        .map(
          (r) => SeriesItem.fromJson(
            jsonDecode(r.payload) as Map<String, dynamic>,
          ),
        )
        .toList();
  }

  /// Search the cached catalog by title (case-insensitive LIKE). Returns raw
  /// rows of the given type; callers decode to the right model. Pure cache
  /// query — no network.
  Future<List<CatalogItem>> search(
    String sourceId,
    String type,
    String query, {
    int limit = 50,
  }) async {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return const [];
    final sel = _db.select(_db.catalogItems)
      ..where(
        (t) =>
            t.sourceId.equals(sourceId) &
            t.type.equals(type) &
            t.cleanTitle.like('%$q%'),
      )
      ..orderBy([(t) => OrderingTerm(expression: t.sortIndex)])
      ..limit(limit);
    return sel.get();
  }

  Future<int> itemCount(String sourceId, String type) async {
    final c = _db.catalogItems.itemId.count();
    final q = _db.selectOnly(_db.catalogItems)
      ..addColumns([c])
      ..where(
        _db.catalogItems.sourceId.equals(sourceId) &
            _db.catalogItems.type.equals(type),
      );
    final row = await q.getSingle();
    return row.read(c) ?? 0;
  }

  Future<List<CatalogItem>> _itemRows(
    String sourceId,
    String type,
    String? categoryId,
  ) {
    final q = _db.select(_db.catalogItems)
      ..where(
        (t) =>
            t.sourceId.equals(sourceId) &
            t.type.equals(type) &
            (categoryId == null
                ? const Constant(true)
                : t.categoryId.equals(categoryId)),
      )
      ..orderBy([(t) => OrderingTerm(expression: t.sortIndex)]);
    return q.get();
  }

  // --- detail (network, not cached as full payload) ------------------------

  Future<VodInfo> vodInfo(IptvSource s, int vodId) => _xtream(s).vodInfo(vodId);

  Future<SeriesInfo> seriesInfo(IptvSource s, int seriesId) =>
      _xtream(s).seriesInfo(seriesId);

  /// Resolve the playable URL for a live channel. [ext] selects the Xtream
  /// container: 'ts' (MPEG-TS, default) or 'm3u8' (HLS) — some streams only
  /// produce audio in libmpv via the HLS variant.
  String liveUrl(IptvSource s, LiveChannel ch, {String ext = 'ts'}) {
    if (ch.directUrl != null) return ch.directUrl!; // M3U
    return _xtream(s).liveStreamUrl(ch.streamId, ext: ext);
  }

  String vodUrl(IptvSource s, int streamId, String containerExt) =>
      _xtream(s).vodStreamUrl(streamId, containerExt);

  String episodeUrl(IptvSource s, String episodeId, String containerExt) =>
      _xtream(s).seriesStreamUrl(episodeId, containerExt);

  // --- write helpers -------------------------------------------------------

  Future<void> _clearSource(String sourceId) async {
    await (_db.delete(
      _db.catalogItems,
    )..where((t) => t.sourceId.equals(sourceId))).go();
    await (_db.delete(
      _db.catalogCategories,
    )..where((t) => t.sourceId.equals(sourceId))).go();
  }

  Future<void> _putCategories(
    String sourceId,
    String type,
    List<Category> cats,
  ) async {
    await _db.batch((b) {
      b.insertAll(
        _db.catalogCategories,
        cats.map(
          (c) => CatalogCategoriesCompanion.insert(
            sourceId: sourceId,
            type: type,
            categoryId: c.id,
            name: c.name,
          ),
        ),
        mode: InsertMode.insertOrReplace,
      );
    });
  }

  Future<void> _putItems(
    String sourceId,
    String type,
    List<_CatalogRow> rows,
  ) async {
    await _db.batch((b) {
      b.insertAll(
        _db.catalogItems,
        rows.map(
          (r) => CatalogItemsCompanion.insert(
            sourceId: sourceId,
            type: type,
            itemId: r.itemId,
            categoryId: Value(r.categoryId),
            title: r.title,
            cleanTitle: r.title.toLowerCase(),
            payload: r.payload,
            sortIndex: Value(r.sortIndex),
          ),
        ),
        mode: InsertMode.insertOrReplace,
      );
    });
  }
}

class _CatalogRow {
  _CatalogRow(
    this.itemId,
    this.categoryId,
    this.title,
    this.payload,
    this.sortIndex,
  );
  final String itemId;
  final String? categoryId;
  final String title;
  final String payload;
  final int sortIndex;
}

// --- off-isolate catalog parsing -------------------------------------------
// Run inside Isolate.run() so JSON decode + model mapping + jsonEncode (the
// heavy CPU that caused UI freezes during the background refresh) never block
// the UI isolate. Depend only on pure-Dart helpers (models, M3uParser).

/// Raw Xtream response bodies (one per endpoint).
class _XtreamRaw {
  const _XtreamRaw({
    required this.liveCats,
    required this.live,
    required this.vodCats,
    required this.vod,
    required this.seriesCats,
    required this.series,
  });
  final String liveCats;
  final String live;
  final String vodCats;
  final String vod;
  final String seriesCats;
  final String series;
}

class _ParsedXtream {
  const _ParsedXtream({
    required this.liveCats,
    required this.live,
    required this.vodCats,
    required this.vod,
    required this.seriesCats,
    required this.series,
  });
  final List<Category> liveCats;
  final List<_CatalogRow> live;
  final List<Category> vodCats;
  final List<_CatalogRow> vod;
  final List<Category> seriesCats;
  final List<_CatalogRow> series;
}

class _ParsedM3u {
  const _ParsedM3u(this.cats, this.items);
  final List<Category> cats;
  final List<_CatalogRow> items;
}

List<Map<String, dynamic>> _decodeList(String raw) {
  if (raw.isEmpty) return const [];
  try {
    final data = jsonDecode(raw);
    if (data is List) {
      return data
          .whereType<Map>()
          .map((e) => e.cast<String, dynamic>())
          .toList();
    }
  } catch (_) {
    /* malformed body -> empty */
  }
  return const [];
}

// Top-level wrappers so the Isolate.run closure captures ONLY the sendable
// argument — never `this` (IptvRepository -> AppDatabase/drift is unsendable,
// which crashed catalog load with "Illegal argument in isolate message").
Future<_ParsedXtream> _runParseXtream(_XtreamRaw raw) =>
    Isolate.run(() => _parseXtreamCatalog(raw));

Future<_ParsedM3u> _runParseM3u(Uint8List bytes) =>
    Isolate.run(() => _parseM3u(bytes));

_ParsedXtream _parseXtreamCatalog(_XtreamRaw r) {
  final live = _decodeList(r.live).map(LiveChannel.fromJson).toList();
  final vod = _decodeList(r.vod).map(VodItem.fromJson).toList();
  final series = _decodeList(r.series).map(SeriesItem.fromJson).toList();
  return _ParsedXtream(
    liveCats: _decodeList(r.liveCats).map(Category.fromJson).toList(),
    vodCats: _decodeList(r.vodCats).map(Category.fromJson).toList(),
    seriesCats: _decodeList(r.seriesCats).map(Category.fromJson).toList(),
    live: [
      for (var i = 0; i < live.length; i++)
        _CatalogRow(
          live[i].streamId.toString(),
          live[i].categoryId,
          live[i].name,
          jsonEncode(_liveToJson(live[i])),
          i,
        ),
    ],
    vod: [
      for (var i = 0; i < vod.length; i++)
        _CatalogRow(
          vod[i].streamId.toString(),
          vod[i].categoryId,
          vod[i].name,
          jsonEncode(_vodToJson(vod[i])),
          i,
        ),
    ],
    series: [
      for (var i = 0; i < series.length; i++)
        _CatalogRow(
          series[i].seriesId.toString(),
          series[i].categoryId,
          series[i].name,
          jsonEncode(_seriesToJson(series[i])),
          i,
        ),
    ],
  );
}

_ParsedM3u _parseM3u(Uint8List bytes) {
  final channels = M3uParser.parse(M3uParser.decodeBytes(bytes));
  return _ParsedM3u(M3uParser.categories(channels), [
    for (var i = 0; i < channels.length; i++)
      _CatalogRow(
        'm3u_$i',
        channels[i].categoryId,
        channels[i].name,
        jsonEncode(_liveToJson(channels[i])),
        i,
      ),
  ]);
}

Map<String, dynamic> _liveToJson(LiveChannel c) => {
  'stream_id': c.streamId,
  'name': c.name,
  'stream_icon': c.icon,
  'category_id': c.categoryId,
  'epg_channel_id': c.epgChannelId,
  if (c.directUrl != null) 'direct_url': c.directUrl,
};

Map<String, dynamic> _vodToJson(VodItem v) => {
  'stream_id': v.streamId,
  'name': v.name,
  'stream_icon': v.icon,
  'category_id': v.categoryId,
  'container_extension': v.containerExtension,
  'tmdb': v.tmdbId,
  'rating': v.rating,
  'added': v.added,
};

Map<String, dynamic> _seriesToJson(SeriesItem s) => {
  'series_id': s.seriesId,
  'name': s.name,
  'cover': s.cover,
  'category_id': s.categoryId,
  'plot': s.plot,
  'tmdb': s.tmdbId,
  'rating': s.rating,
};
