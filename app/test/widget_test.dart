import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zen_player/main.dart';

void main() {
  testWidgets('app boots into splash/login without crashing', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: ZenPlayerApp()));
    await tester.pump(); // splash frame
    // No exception thrown during boot is the smoke assertion.
    expect(tester.takeException(), isNull);
  });
}
