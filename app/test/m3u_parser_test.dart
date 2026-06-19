import 'package:flutter_test/flutter_test.dart';
import 'package:zen_player/iptv/m3u_parser.dart';

void main() {
  group('M3uParser', () {
    test('parses EXTINF entries with tvg attrs + group-title', () {
      const playlist = '''
#EXTM3U
#EXTINF:-1 tvg-id="cnn.us" tvg-logo="http://logo/cnn.png" group-title="News",CNN HD
http://portal/live/u/p/101.ts
#EXTINF:-1 tvg-logo="http://logo/bbc.png" group-title="News",BBC One
http://portal/live/u/p/102.ts
#EXTINF:-1 group-title="Sports",ESPN
http://portal/live/u/p/103.ts
''';
      final channels = M3uParser.parse(playlist);
      expect(channels, hasLength(3));
      expect(channels[0].name, 'CNN HD');
      expect(channels[0].directUrl, 'http://portal/live/u/p/101.ts');
      expect(channels[0].icon, 'http://logo/cnn.png');
      expect(channels[0].categoryId, 'News');
      expect(channels[0].epgChannelId, 'cnn.us');
      expect(channels[2].categoryId, 'Sports');
      expect(channels[2].name, 'ESPN');
    });

    test('tolerates missing attributes and blank lines', () {
      const playlist = '''
#EXTM3U

#EXTINF:-1,Plain Channel
http://portal/x.ts
''';
      final channels = M3uParser.parse(playlist);
      expect(channels, hasLength(1));
      expect(channels[0].name, 'Plain Channel');
      expect(channels[0].categoryId, isNull);
      expect(channels[0].icon, isNull);
    });

    test('groups channels into categories', () {
      const playlist = '''
#EXTM3U
#EXTINF:-1 group-title="A",One
http://p/1.ts
#EXTINF:-1 group-title="B",Two
http://p/2.ts
#EXTINF:-1 group-title="A",Three
http://p/3.ts
''';
      final cats = M3uParser.categories(M3uParser.parse(playlist));
      expect(cats.map((c) => c.name).toSet(), {'A', 'B'});
    });

    test('ignores a non-EXTINF line / empty input', () {
      expect(M3uParser.parse(''), isEmpty);
      expect(M3uParser.parse('garbage\nmore garbage'), isEmpty);
    });
  });
}
