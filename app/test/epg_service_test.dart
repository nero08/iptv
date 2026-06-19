import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:zen_player/epg/epg_service.dart';

String b64(String s) => base64.encode(utf8.encode(s));

void main() {
  group('EpgService.parseShortEpg', () {
    test('decodes base64 titles + epoch timestamps, sorted', () {
      final rows = [
        {
          'title': b64('News at Ten'),
          'description': b64('Evening news'),
          'start_timestamp': '1893456000', // 2030-01-01 00:00 UTC
          'stop_timestamp': '1893459600', // +1h
        },
        {
          'title': b64('Late Show'),
          'start_timestamp': '1893459600',
          'stop_timestamp': '1893463200',
        },
      ];
      final progs = EpgService.parseShortEpg(rows);
      expect(progs, hasLength(2));
      expect(progs[0].title, 'News at Ten');
      expect(progs[0].description, 'Evening news');
      expect(progs[1].title, 'Late Show');
      expect(progs[0].start.isBefore(progs[1].start), true);
    });

    test('skips entries without valid timestamps', () {
      final rows = [
        {'title': b64('No times')},
        {'title': b64('Good'), 'start_timestamp': '1893456000', 'stop_timestamp': '1893459600'},
      ];
      expect(EpgService.parseShortEpg(rows), hasLength(1));
    });

    test('tolerates already-plaintext titles (non-base64)', () {
      final rows = [
        {'title': 'PlainTitle', 'start_timestamp': '1893456000', 'stop_timestamp': '1893459600'},
      ];
      final progs = EpgService.parseShortEpg(rows);
      // base64 of "PlainTitle" fails clean utf8 decode -> falls back to raw.
      expect(progs.single.title.isNotEmpty, true);
    });
  });

  group('EpgService.nowNextFrom', () {
    test('selects current + upcoming programme', () {
      final base = DateTime.utc(2030, 1, 1, 10, 0).toLocal();
      final progs = EpgService.parseShortEpg([
        {
          'title': b64('Morning'),
          'start_timestamp': (DateTime.utc(2030, 1, 1, 9).millisecondsSinceEpoch ~/ 1000).toString(),
          'stop_timestamp': (DateTime.utc(2030, 1, 1, 11).millisecondsSinceEpoch ~/ 1000).toString(),
        },
        {
          'title': b64('Noon'),
          'start_timestamp': (DateTime.utc(2030, 1, 1, 11).millisecondsSinceEpoch ~/ 1000).toString(),
          'stop_timestamp': (DateTime.utc(2030, 1, 1, 13).millisecondsSinceEpoch ~/ 1000).toString(),
        },
      ]);
      final nn = EpgService.nowNextFrom(progs, base);
      expect(nn.now?.title, 'Morning');
      expect(nn.next?.title, 'Noon');
    });
  });
}
