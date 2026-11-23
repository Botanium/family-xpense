// Goldens of entry detail (screen 17) in light and dark. Record with
// `flutter test --update-goldens test/activity` on a Mac; never in CI
// (glyphs rasterise differently on Linux).
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:xpense_app/core/routing/routing.dart';
import 'package:xpense_app/services/settings_store.dart';

import '../capture/ledger_app.dart';
import '../ui/ui_harness.dart';
import 'entry_detail_test.dart' show seedEntry;

void main() {
  setUpAll(loadSignalFonts);

  for (final appearance in [AppearanceMode.light, AppearanceMode.dark]) {
    testWidgets('Entry detail (${appearance.name})', skip: !goldensSupported, (
      tester,
    ) async {
      final app = LedgerApp(appearance: appearance);
      final id = await seedEntry(app);
      final container = await app.pump(tester);
      await pushTo(tester, container, AppRoutes.entry(id));
      await expectLater(
        find.byType(WidgetsApp).first,
        matchesGoldenFile('goldens/entry_detail_${appearance.name}.png'),
      );
    });
  }
}
