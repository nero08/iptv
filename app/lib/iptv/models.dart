// IPTV domain models, mapped from Xtream Codes JSON (snake_case) and M3U.
// Mirrors the original app's struct set (RawXtreamMovie/Serie/Channel/Category,
// XtreamSeason, XtreamVodInfo, XtreamSerieInfo).

/// Defensive coercion helpers — Xtream portals are notoriously loose with types
/// (numbers as strings, "0"/"" for null, empty arrays for missing objects).
int asInt(dynamic v, [int fallback = 0]) {
  if (v == null) return fallback;
  if (v is int) return v;
  if (v is double) return v.toInt();
  if (v is String) {
    final s = v.trim();
    if (s.isEmpty) return fallback;
    return int.tryParse(s) ?? double.tryParse(s)?.toInt() ?? fallback;
  }
  return fallback;
}

String asString(dynamic v, [String fallback = '']) {
  if (v == null) return fallback;
  if (v is String) return v;
  return v.toString();
}

String? asStringOrNull(dynamic v) {
  if (v == null) return null;
  final s = v is String ? v : v.toString();
  return s.trim().isEmpty ? null : s;
}

/// Portal account + server info (from the no-action `player_api.php` call).
class SourceInfo {
  SourceInfo({
    required this.status,
    required this.maxConnections,
    required this.activeConnections,
    this.expDate,
    this.auth,
  });

  final String status;
  final int maxConnections;
  final int activeConnections;
  final DateTime? expDate;
  final int? auth;

  bool get isActive => status.toLowerCase() == 'active' && (auth ?? 1) == 1;

  factory SourceInfo.fromJson(Map<String, dynamic> j) {
    final user = (j['user_info'] as Map?)?.cast<String, dynamic>() ?? const {};
    final exp = user['exp_date'];
    DateTime? expDate;
    if (exp != null && asString(exp).isNotEmpty && asString(exp) != '0') {
      final secs = asInt(exp);
      if (secs > 0) {
        expDate = DateTime.fromMillisecondsSinceEpoch(secs * 1000, isUtc: true);
      }
    }
    return SourceInfo(
      status: asString(user['status'], 'Unknown'),
      maxConnections: asInt(user['max_connections']),
      activeConnections: asInt(user['active_cons']),
      expDate: expDate,
      auth: user['auth'] == null ? null : asInt(user['auth']),
    );
  }
}

/// A category (live / vod / series share the same shape).
class Category {
  Category({required this.id, required this.name});
  final String id;
  final String name;

  factory Category.fromJson(Map<String, dynamic> j) => Category(
        id: asString(j['category_id']),
        name: asString(j['category_name'], 'Sans catégorie'),
      );
}

class LiveChannel {
  LiveChannel({
    required this.streamId,
    required this.name,
    this.icon,
    this.categoryId,
    this.epgChannelId,
    this.directUrl,
  });

  /// Xtream stream id (used to build the play URL). For M3U channels this is 0
  /// and [directUrl] carries the playable URL instead.
  final int streamId;
  final String name;
  final String? icon;
  final String? categoryId;
  final String? epgChannelId;

  /// Set for M3U channels (the URL comes straight from the playlist).
  final String? directUrl;

  factory LiveChannel.fromJson(Map<String, dynamic> j) => LiveChannel(
        streamId: asInt(j['stream_id']),
        name: asString(j['name'], 'Sans nom'),
        icon: asStringOrNull(j['stream_icon']),
        categoryId: asStringOrNull(j['category_id']),
        epgChannelId: asStringOrNull(j['epg_channel_id']),
        directUrl: asStringOrNull(j['direct_url']),
      );
}

class VodItem {
  VodItem({
    required this.streamId,
    required this.name,
    this.icon,
    this.categoryId,
    this.containerExtension,
    this.tmdbId,
    this.rating,
    this.added,
  });

  final int streamId;
  final String name;
  final String? icon;
  final String? categoryId;
  final String? containerExtension;
  final int? tmdbId;
  final String? rating;
  final String? added;

  factory VodItem.fromJson(Map<String, dynamic> j) => VodItem(
        streamId: asInt(j['stream_id']),
        name: asString(j['name'], 'Sans nom'),
        icon: asStringOrNull(j['stream_icon']),
        categoryId: asStringOrNull(j['category_id']),
        containerExtension: asStringOrNull(j['container_extension']),
        tmdbId: j['tmdb'] == null ? null : asInt(j['tmdb']),
        rating: asStringOrNull(j['rating']),
        added: asStringOrNull(j['added']),
      );
}

/// Detailed VOD info from `get_vod_info`.
class VodInfo {
  VodInfo({
    required this.streamId,
    required this.containerExtension,
    this.plot,
    this.genre,
    this.cast,
    this.director,
    this.releaseDate,
    this.durationSecs,
    this.tmdbId,
    this.coverBig,
    this.youtubeTrailer,
  });

  final int streamId;
  final String containerExtension;
  final String? plot;
  final String? genre;
  final String? cast;
  final String? director;
  final String? releaseDate;
  final int? durationSecs;
  final int? tmdbId;
  final String? coverBig;
  final String? youtubeTrailer;

  factory VodInfo.fromJson(Map<String, dynamic> j) {
    final info = (j['info'] as Map?)?.cast<String, dynamic>() ?? const {};
    final movieData =
        (j['movie_data'] as Map?)?.cast<String, dynamic>() ?? const {};
    return VodInfo(
      streamId: asInt(movieData['stream_id']),
      containerExtension: asString(movieData['container_extension'], 'mp4'),
      plot: asStringOrNull(info['plot']) ?? asStringOrNull(info['description']),
      genre: asStringOrNull(info['genre']),
      cast: asStringOrNull(info['cast']) ?? asStringOrNull(info['actors']),
      director: asStringOrNull(info['director']),
      releaseDate: asStringOrNull(info['releasedate']) ??
          asStringOrNull(info['release_date']),
      durationSecs: info['duration_secs'] == null
          ? null
          : asInt(info['duration_secs']),
      tmdbId: info['tmdb_id'] == null ? null : asInt(info['tmdb_id']),
      coverBig:
          asStringOrNull(info['cover_big']) ?? asStringOrNull(info['movie_image']),
      youtubeTrailer: asStringOrNull(info['youtube_trailer']),
    );
  }
}

class SeriesItem {
  SeriesItem({
    required this.seriesId,
    required this.name,
    this.cover,
    this.categoryId,
    this.plot,
    this.tmdbId,
    this.rating,
  });

  final int seriesId;
  final String name;
  final String? cover;
  final String? categoryId;
  final String? plot;
  final int? tmdbId;
  final String? rating;

  factory SeriesItem.fromJson(Map<String, dynamic> j) => SeriesItem(
        seriesId: asInt(j['series_id']),
        name: asString(j['name'], 'Sans nom'),
        cover: asStringOrNull(j['cover']),
        categoryId: asStringOrNull(j['category_id']),
        plot: asStringOrNull(j['plot']),
        tmdbId: j['tmdb'] == null ? null : asInt(j['tmdb']),
        rating: asStringOrNull(j['rating']),
      );
}

class Episode {
  Episode({
    required this.id,
    required this.title,
    required this.containerExtension,
    this.episodeNum,
    this.season,
    this.plot,
    this.durationSecs,
    this.cover,
  });

  /// Xtream episode id (used to build the series play URL).
  final String id;
  final String title;
  final String containerExtension;
  final int? episodeNum;
  final int? season;
  final String? plot;
  final int? durationSecs;
  final String? cover;

  factory Episode.fromJson(Map<String, dynamic> j) {
    final _infoRaw = j['info'];
    final info = _infoRaw is Map ? _infoRaw.cast<String, dynamic>() : const <String, dynamic>{};
    return Episode(
      id: asString(j['id']),
      title: asString(j['title'], 'Épisode'),
      containerExtension: asString(j['container_extension'], 'mp4'),
      episodeNum: j['episode_num'] == null ? null : asInt(j['episode_num']),
      season: j['season'] == null ? null : asInt(j['season']),
      plot: asStringOrNull(info['plot']),
      durationSecs:
          info['duration_secs'] == null ? null : asInt(info['duration_secs']),
      cover: asStringOrNull(info['movie_image']),
    );
  }
}

class Season {
  Season({required this.number, required this.episodes});
  final int number;
  final List<Episode> episodes;
}

/// Detailed series info from `get_series_info` (seasons -> episodes).
class SeriesInfo {
  SeriesInfo({
    this.plot,
    this.genre,
    this.cast,
    this.cover,
    this.tmdbId,
    required this.seasons,
  });

  final String? plot;
  final String? genre;
  final String? cast;
  final String? cover;
  final int? tmdbId;
  final List<Season> seasons;

  factory SeriesInfo.fromJson(Map<String, dynamic> j) {
    final _infoRaw = j['info'];
    final info = _infoRaw is Map ? _infoRaw.cast<String, dynamic>() : const <String, dynamic>{};
    // `episodes` is a map keyed by season number -> list of episode maps.
    final episodesRaw = j['episodes'];
    final seasons = <Season>[];
    if (episodesRaw is Map) {
      final keys = episodesRaw.keys.toList()
        ..sort((a, b) => asInt(a).compareTo(asInt(b)));
      for (final k in keys) {
        final list = episodesRaw[k];
        if (list is List) {
          seasons.add(Season(
            number: asInt(k),
            episodes: list
                .whereType<Map>()
                .map((e) => Episode.fromJson(e.cast<String, dynamic>()))
                .toList(),
          ));
        }
      }
    }
    return SeriesInfo(
      plot: asStringOrNull(info['plot']),
      genre: asStringOrNull(info['genre']),
      cast: asStringOrNull(info['cast']),
      cover: asStringOrNull(info['cover']),
      tmdbId: info['tmdb_id'] == null ? null : asInt(info['tmdb_id']),
      seasons: seasons,
    );
  }
}

/// A single EPG programme entry (from `get_short_epg`).
class EpgEntry {
  EpgEntry({
    required this.title,
    required this.start,
    required this.end,
    this.description,
  });

  final String title;
  final DateTime start;
  final DateTime end;
  final String? description;
}
