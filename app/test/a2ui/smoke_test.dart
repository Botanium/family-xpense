import 'package:flutter_test/flutter_test.dart';

import 'a2ui_harness.dart';

void main() {
  for (final name in fixtureNames()) {
    testWidgets('$name renders without errors', (tester) async {
      final (:host, :actions, :sent) = hostWith(fixture(name));
      expect(host.failedMessages, 0, reason: '${host.issues}');
      await pumpThread(tester, host);
      expect(tester.takeException(), isNull);
      expect(host.issues, isEmpty);
    });
  }
}
