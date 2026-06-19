import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:zen_player/browse/media_tile.dart';
import 'package:zen_player/player/player_screen.dart';

void main() {
  testWidgets('tapping a MediaTile fires onTap (the play wiring)', (tester) async {
    var tapped = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: MediaTile(title: 'CNN', icon: Icons.live_tv, onTap: () => tapped++),
      ),
    ));
    await tester.tap(find.text('CNN'));
    await tester.pump();
    expect(tapped, 1, reason: 'InkWell.onTap fires on tap');
  });

  test('PlayerScreen carries the resolved stream URL + isLive flag', () {
    const w = PlayerScreen(
        streamUrl: 'http://portal/live/u/p/101.ts', title: 'CNN', isLive: true);
    expect(w.streamUrl, 'http://portal/live/u/p/101.ts');
    expect(w.isLive, true);
    expect(w.title, 'CNN');
    // Note: building PlayerScreen requires MediaKit native init (device/emulator
    // only), so the widget render is verified on the emulator, not here.
  });
}
