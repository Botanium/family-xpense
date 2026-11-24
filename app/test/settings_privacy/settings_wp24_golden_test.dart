// Goldens of Settings > Exchange rate and Settings > Categories (WP-24), in
// light and graphite dark at text scale 1.0 and 1.5. No right-to-left
// goldens until a right-to-left language is added (D-36, DESIGN_SYSTEM 10).
//
// Record with `flutter test --update-goldens test/settings_privacy` on a
// Mac; never in CI (glyphs rasterise differently on the Linux runner).
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:xpense_app/app.dart';
import 'package:xpense_app/core/routing/routing.dart';
import 'package:xpense_app/data/fx_repository.dart';
import 'package:xpense_app/services/settings_store.dart';
import 'package:xpense_shared/xpense_shared.dart';

import '../capture/ledger_app.dart';
import '../ui/ui_harness.dart';

FxRate _rate(String v) => FxRate.forPair(FxPair.usdIqd, v).valueOrNull!;

void main() {
  setUpAll(loadSignalFonts);

  for (final appearance in [AppearanceMode.light, AppearanceMode.dark]) {
    for (final scale in [1.0, 1.5]) {
      final variant = '${appearance.name}_${scale == 1 ? '1x' : '1_5x'}';
      for (final (name, route) in [
        ('rate', AppRoutes.settingsRate),
        ('categories', AppRoutes.settingsCategories),
      ]) {
        testWidgets('Settings $name ($variant)', skip: !goldensSupported, (
          tester,
        ) async {
          tester.platformDispatcher.textScaleFactorTestValue = scale;
          addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
          final app = LedgerApp(withRate: false, appearance: appearance);
          app.fx
            ..put(
              DailyRate(
                day: '2026-11-20',
                rate: _rate('1700'),
                enteredBy: partner,
              ),
            )
            ..put(
              DailyRate(
                day: '2026-11-21',
                rate: _rate('1705'),
                enteredBy: viewer,
              ),
            );
          await app.categories.setArchived('bakery_tea', archived: true);
          final container = await app.pump(tester);
          unawaited(container.read(routerProvider).push<void>(route));
          await tester.pumpAndSettle();
          await expectLater(
            find.byType(XpenseApp),
            matchesGoldenFile('goldens/settings_${name}_$variant.png'),
          );
        });
      }
    }
  }
}
