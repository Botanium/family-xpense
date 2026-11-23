// Goldens of Activity (screen 16, artboard 16) in light and dark: the list
// as it opens, and right after a delete with the undo toast. Recorded on
// macOS: `flutter test --update-goldens test/activity`. Also: the screen at
// the largest text size we test builds without overflow.
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:xpense_app/features/activity/activity_screen.dart';

import '../ui/ui_harness.dart'
    show goldenSkipReason, goldensSupported, loadSignalFonts;
import 'activity_harness.dart';

void main() {
  setUpAll(loadSignalFonts);

  for (final brightness in Brightness.values) {
    final name = brightness.name;

    testWidgets('Activity in $name', skip: !goldensSupported, (tester) async {
      tester.platformDispatcher.platformBrightnessTestValue = brightness;
      addTearDown(tester.platformDispatcher.clearAllTestValues);
      await pumpActivity(tester);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/activity_$name.png'),
      );
    });

    testWidgets(
      'Activity after a delete, with Undo, in $name',
      skip: !goldensSupported,
      (tester) async {
        tester.platformDispatcher.platformBrightnessTestValue = brightness;
        addTearDown(tester.platformDispatcher.clearAllTestValues);
        await pumpActivity(tester);
        await tester.drag(find.text('Costco'), const Offset(-340, 0));
        await tester.pumpAndSettle();
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('goldens/activity_undo_$name.png'),
        );
        await tester.pump(const Duration(seconds: 11));
      },
    );

    testWidgets(
      'Activity with a row swiped open in $name',
      skip: !goldensSupported,
      (tester) async {
        tester.platformDispatcher.platformBrightnessTestValue = brightness;
        addTearDown(tester.platformDispatcher.clearAllTestValues);
        await pumpActivity(tester);
        await tester.drag(find.text('Salary'), const Offset(-200, 0));
        await tester.pumpAndSettle();
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('goldens/activity_swiped_$name.png'),
        );
      },
    );

    testWidgets('builds at 2x text in $name without overflow', (tester) async {
      tester.platformDispatcher
        ..textScaleFactorTestValue = 2
        ..platformBrightnessTestValue = brightness;
      addTearDown(tester.platformDispatcher.clearAllTestValues);
      await pumpActivity(tester);
      // Scoped to Activity: Home, offstage in the shell, reads the same
      // store and lists Costco too (WP-23).
      expect(
        find.descendant(
          of: find.byType(ActivityScreen, skipOffstage: false),
          matching: find.text('Costco', skipOffstage: false),
        ),
        findsOneWidget,
      );
      await tester.drag(find.text('Costco'), const Offset(-200, 0));
      await tester.pumpAndSettle();
      expect(find.text('Delete'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  test('golden skip reason is stated when goldens cannot run', () {
    expect(goldenSkipReason, contains('macOS'));
  });
}
