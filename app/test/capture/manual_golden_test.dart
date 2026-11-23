// Goldens of Add manually (screen 9) in light and dark. Record with `flutter test --update-goldens test/capture` on a
// Mac; never in CI (glyphs rasterise differently on Linux).
import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xpense_app/core/routing/routing.dart';
import 'package:xpense_app/core/ui/ui.dart';
import 'package:xpense_app/services/settings_store.dart';

import '../ui/ui_harness.dart';
import 'ledger_app.dart';

void main() {
  setUpAll(loadSignalFonts);

  for (final appearance in [AppearanceMode.light, AppearanceMode.dark]) {
    testWidgets(
      'Add manually, expense (${appearance.name})',
      skip: !goldensSupported,
      (tester) async {
        final app = LedgerApp(appearance: appearance);
        final container = await app.pump(tester);
        await pushTo(tester, container, AppRoutes.addEntry);
        await tester.enterText(
          find
              .descendant(
                of: find.byType(AmountField),
                matching: find.byType(CupertinoTextField),
              )
              .first,
          '42.80',
        );
        await tester.tap(find.text('Food'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Groceries'));
        // The caret blinks; settle on a frame without it.
        FocusManager.instance.primaryFocus?.unfocus();
        await tester.pumpAndSettle();
        await expectLater(
          find.byType(WidgetsApp).first,
          matchesGoldenFile('goldens/add_manually_${appearance.name}.png'),
        );
      },
    );

    testWidgets(
      'Add manually, errors (${appearance.name})',
      skip: !goldensSupported,
      (tester) async {
        final app = LedgerApp(appearance: appearance);
        final container = await app.pump(tester);
        await pushTo(tester, container, AppRoutes.addEntry);
        await tester.tap(find.text('Loan'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Save loan'));
        await tester.pumpAndSettle();
        await expectLater(
          find.byType(WidgetsApp).first,
          matchesGoldenFile(
            'goldens/add_manually_errors_${appearance.name}.png',
          ),
        );
      },
    );
  }
}
