// showGlassSheet's enableDrag and isDismissible reach the modal sheet
// (cleanups, item 5): a sheet that saves can refuse a swipe down, and one
// can refuse a tap on the dimmed screen.
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:xpense_app/core/ui/ui.dart';

import 'ui_harness.dart';

Future<void> _open(
  WidgetTester tester, {
  bool enableDrag = true,
  bool isDismissible = true,
}) async {
  await tester.pumpWidget(
    signalHarness(
      child: Builder(
        builder: (context) => TextButton(
          onPressed: () => showGlassSheet<void>(
            context: context,
            enableDrag: enableDrag,
            isDismissible: isDismissible,
            builder: (_) => const SizedBox(height: 200, child: Text('Body')),
          ),
          child: const Text('Open'),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
  expect(find.text('Body'), findsOneWidget);
}

void main() {
  setUpAll(loadSignalFonts);

  // Above the half-height sheet: the dimmed screen.
  const barrier = Offset(200, 40);

  testWidgets('by default a swipe down and the dimmed screen close it', (
    tester,
  ) async {
    await _open(tester);
    expect(
      tester.widget<BottomSheet>(find.byType(BottomSheet)).enableDrag,
      isTrue,
    );
    await tester.drag(find.text('Body'), const Offset(0, 600));
    await tester.pumpAndSettle();
    expect(find.text('Body'), findsNothing);

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tapAt(barrier);
    await tester.pumpAndSettle();
    expect(find.text('Body'), findsNothing);
  });

  testWidgets('enableDrag false: a swipe down leaves it open', (tester) async {
    await _open(tester, enableDrag: false);
    expect(
      tester.widget<BottomSheet>(find.byType(BottomSheet)).enableDrag,
      isFalse,
    );
    await tester.drag(find.text('Body'), const Offset(0, 600));
    await tester.pumpAndSettle();
    expect(find.text('Body'), findsOneWidget);
    // The dimmed screen still closes it.
    await tester.tapAt(barrier);
    await tester.pumpAndSettle();
    expect(find.text('Body'), findsNothing);
  });

  testWidgets('isDismissible false: the dimmed screen does nothing', (
    tester,
  ) async {
    await _open(tester, isDismissible: false);
    await tester.tapAt(barrier);
    await tester.pumpAndSettle();
    expect(find.text('Body'), findsOneWidget);
  });
}
