import 'dart:convert';
import 'dart:typed_data';

import 'models.dart';

/// Pure-Dart M3U / M3U8 playlist parser. Turns `#EXTINF` entries + URL lines
/// into [LiveChannel]s (M3U is treated as a flat list of live channels grouped
/// by `group-title`).
class M3uParser {
  static final _attrRe = RegExp(r'([a-zA-Z0-9-]+)="([^"]*)"');

  /// Decode raw bytes defensively: try UTF-8, fall back to latin1 for portals
  /// that serve non-UTF-8 playlists (rather than aborting on a decode error).
  static String decodeBytes(Uint8List bytes) {
    try {
      return utf8.decode(bytes);
    } catch (_) {
      return latin1.decode(bytes);
    }
  }

  /// Parse playlist text into channels. Each entry is an `#EXTINF` line with
  /// tvg attributes and a trailing display name, followed by the stream URL on
  /// the next line.
  static List<LiveChannel> parse(String content) {
    final channels = <LiveChannel>[];
    final lines = const LineSplitter().convert(content);
    String? pendingName;
    String? pendingLogo;
    String? pendingGroup;
    String? pendingTvgId;

    for (final raw in lines) {
      final line = raw.trim();
      if (line.isEmpty) continue;
      if (line.startsWith('#EXTINF')) {
        final attrs = <String, String>{};
        for (final m in _attrRe.allMatches(line)) {
          attrs[m.group(1)!.toLowerCase()] = m.group(2)!;
        }
        // Display name is the text after the last comma.
        final commaIdx = line.lastIndexOf(',');
        pendingName = commaIdx >= 0 ? line.substring(commaIdx + 1).trim() : 'Sans nom';
        pendingLogo = attrs['tvg-logo'];
        pendingGroup = attrs['group-title'];
        pendingTvgId = attrs['tvg-id'];
      } else if (!line.startsWith('#')) {
        // A URL line. Only emit if we saw an EXTINF immediately before.
        if (pendingName != null) {
          channels.add(LiveChannel(
            streamId: 0,
            name: pendingName,
            icon: (pendingLogo != null && pendingLogo.isNotEmpty) ? pendingLogo : null,
            categoryId: (pendingGroup != null && pendingGroup.isNotEmpty)
                ? pendingGroup
                : null,
            epgChannelId:
                (pendingTvgId != null && pendingTvgId.isNotEmpty) ? pendingTvgId : null,
            directUrl: line,
          ));
          pendingName = null;
          pendingLogo = null;
          pendingGroup = null;
          pendingTvgId = null;
        }
      }
      // other `#...` directives are ignored
    }
    return channels;
  }

  /// Distinct categories derived from `group-title` (id == name for M3U).
  static List<Category> categories(List<LiveChannel> channels) {
    final seen = <String>{};
    final cats = <Category>[];
    for (final c in channels) {
      final g = c.categoryId;
      if (g != null && seen.add(g)) {
        cats.add(Category(id: g, name: g));
      }
    }
    return cats;
  }
}
