// Goldens for every gallery entry (DESIGN_SYSTEM 8): light and dark, text
// scale 1.0 and 1.5. Record with `flutter test --update-goldens test/ui` on
// a Mac; never in CI.
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:xpense_app/core/ui/gallery/gallery_entries.dart';
import 'package:xpense_app/core/ui/gallery/gallery_page.dart';

import 'ui_harness.dart';

void main() {
  setUpAll(loadSignalFonts);

  for (final entry in galleryEntries) {
    for (final brightness in Brightness.values) {
      for (final scale in [1.0, 1.5]) {
        final variant = '${brightness.name}_${scale == 1 ? '1x' : '1_5x'}';
        testWidgets(
          '${entry.section} / ${entry.name} ($variant)',
          skip: !goldensSupported,
          (tester) async {
            tester.view
              ..physicalSize = const Size(390, 1600) * 3
              ..devicePixelRatio = 3;
            addTearDown(tester.view.reset);
            await tester.pumpWidget(
              signalHarness(
                brightness: brightness,
                textScale: scale,
                child: RepaintBoundary(
                  key: const ValueKey('golden'),
                  child: Padding(
                    padding: const EdgeInsetsDirectional.all(16),
                    child: GalleryEntryView(entry: entry),
                  ),
                ),
              ),
            );
            await tester.pump();
            await expectLater(
              find.byKey(const ValueKey('golden')),
              matchesGoldenFile('goldens/${entry.name}_$variant.png'),
            );
          },
        );
      }
    }
  }

  test('golden skip reason is stated when goldens cannot run', () {
    expect(goldenSkipReason, contains('macOS'));
  });
}
