import 'dart:convert';

import '../iptv/models.dart';
import '../iptv/xtream_client.dart';
import 'epg_models.dart';

/// Fetches + parses short EPG for live channels. Xtream `get_short_epg` returns
/// entries with base64-encoded `title`/`description` and epoch `start`/`end`
/// (or `start_timestamp`/`stop_timestamp`). Cached briefly per channel to avoid
/// refetching on every tile build (hot path).
class EpgService {
  EpgService(this._client);
  final XtreamClient _client;

  final Map<int, _CacheEntry> _cache = {};
  static const _ttl = Duration(minutes: 5);

  /// Parse raw `get_short_epg` rows into programmes (pure, unit-testable).
  static List<EpgProgramme> parseShortEpg(List<Map<String, dynamic>> rows) {
    final out = <EpgProgramme>[];
    for (final r in rows) {
      final title = _b64(asString(r['title']));
      final desc = _b64(asString(r['description']));
      final start = _epoch(r['start_timestamp'] ?? r['start']);
      final end = _epoch(r['stop_timestamp'] ?? r['end'] ?? r['stop']);
      if (start == null || end == null) continue;
      out.add(EpgProgramme(
          title: title.isEmpty ? 'Programme' : title,
          start: start,
          end: end,
          description: desc.isEmpty ? null : desc));
    }
    out.sort((a, b) => a.start.compareTo(b.start));
    return out;
  }

  /// now/next for a channel at [at] (defaults to now).
  static NowNext nowNextFrom(List<EpgProgramme> programmes, DateTime at) {
    EpgProgramme? now;
    EpgProgramme? next;
    for (final p in programmes) {
      if (p.isNow(at)) {
        now = p;
      } else if (p.start.isAfter(at)) {
        next ??= p;
      }
    }
    return NowNext(now: now, next: next);
  }

  Future<NowNext> nowNext(int streamId, {DateTime? at}) async {
    final when = at ?? DateTime.now();
    final cached = _cache[streamId];
    if (cached != null && when.difference(cached.fetchedAt).abs() < _ttl) {
      return nowNextFrom(cached.programmes, when);
    }
    try {
      final rows = await _client.shortEpg(streamId);
      final programmes = parseShortEpg(rows);
      _cache[streamId] = _CacheEntry(programmes, when);
      return nowNextFrom(programmes, when);
    } catch (_) {
      return NowNext();
    }
  }

  static String _b64(String s) {
    if (s.isEmpty) return '';
    try {
      return utf8.decode(base64.decode(s));
    } catch (_) {
      return s; // already plain text on some portals
    }
  }

  static DateTime? _epoch(dynamic v) {
    if (v == null) return null;
    final s = v.toString().trim();
    if (s.isEmpty) return null;
    // Epoch seconds (Xtream timestamps) -> local DateTime.
    final secs = int.tryParse(s);
    if (secs != null) {
      return DateTime.fromMillisecondsSinceEpoch(secs * 1000, isUtc: true)
          .toLocal();
    }
    // Fallback: "YYYY-MM-DD HH:MM:SS" string form.
    return DateTime.tryParse(s.replaceFirst(' ', 'T'));
  }
}

class _CacheEntry {
  _CacheEntry(this.programmes, this.fetchedAt);
  final List<EpgProgramme> programmes;
  final DateTime fetchedAt;
}
