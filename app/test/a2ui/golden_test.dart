// Goldens of every shared surface fixture (A2UI_CATALOG 9, story S3.3):
// light and dark, text scale 1.0 and 1.5. The fixtures come from
// packages/xpense_shared/test/fixtures/surfaces and together cover all 24
// components. Record with `flutter test --update-goldens test/a2ui` on a
// Mac; never in CI.
import 'package:clock/clock.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../ui/ui_harness.dart'
    show goldenSkipReason, goldensSupported, loadSignalFonts;
import 'a2ui_harness.dart';

void main() {
  setUpAll(loadSignalFonts);

  for (final name in fixtureNames()) {
    for (final brightness in Brightness.values) {
      for (final scale in [1.0, 1.5]) {
        final variant = '${brightness.name}_${scale == 1 ? '1x' : '1_5x'}';
        testWidgets(
          '$name ($variant)',
          skip: !goldensSupported,
          (tester) => withClock(
            // The fixtures are dated 2026-11-22, so "Today" stays today.
            Clock.fixed(DateTime(2026, 11, 22, 14)),
            () async {
              final (:host, :actions, :sent) = hostWith(fixture(name));
              await pumpThread(
                tester,
                host,
                brightness: brightness,
                textScale: scale,
              );
              await expectLater(
                find.byKey(goldenKey),
                matchesGoldenFile('goldens/${name}_$variant.png'),
              );
            },
          ),
        );
      }
    }
  }

  test('golden skip reason is stated when goldens cannot run', () {
    expect(goldenSkipReason, contains('macOS'));
  });
}
