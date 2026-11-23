// Goldens of Home with the daily rate prompt in the notice slot (WP-24,
// DESIGN_SYSTEM 8.2 `RatePrompt`), in light and graphite dark at text
// scale 1.0 and 1.5. No right-to-left goldens until a right-to-left
// language is added (D-36, DESIGN_SYSTEM 10), as for Home itself.
//
// Record with `flutter test --update-goldens test/home` on a Mac; never in
// CI (glyphs rasterise differently on the Linux runner).
import 'package:flutter_test/flutter_test.dart';
import 'package:xpense_app/app.dart';
import 'package:xpense_app/services/settings_store.dart';

import '../ui/ui_harness.dart';
import 'home_test_data.dart';

void main() {
  setUpAll(loadSignalFonts);

  for (final appearance in [AppearanceMode.light, AppearanceMode.dark]) {
    for (final scale in [1.0, 1.5]) {
      final variant = '${appearance.name}_${scale == 1 ? '1x' : '1_5x'}';
      testWidgets(
        'Home with the rate prompt ($variant)',
        skip: !goldensSupported,
        (tester) async {
          tester.platformDispatcher.textScaleFactorTestValue = scale;
          addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
          await pumpHome(
            tester,
            transactions: artboardMonth(),
            services: artboardServices(
              appearance: appearance,
              rateAnswered: false,
            ),
          );
          await expectLater(
            find.byType(XpenseApp),
            matchesGoldenFile('goldens/home_rate_prompt_$variant.png'),
          );
        },
      );
    }
  }
}
