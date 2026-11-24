// WP-24 on the simulator, on the `fakes` environment (no Firebase): the
// daily rate prompt on Home with the >5% confirmation, the rate history
// in Settings, and renaming a category. Paced for the PR recording:
//
//   tools/pr_demo.sh start <device>
//   cd app && flutter test integration_test/rate_demo_test.dart \
//     --flavor dev -d <device> --plain-name demo
//   tools/pr_demo.sh stop
import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:xpense_app/app.dart';
import 'package:xpense_app/bootstrap.dart';
import 'package:xpense_app/core/routing/routing.dart';
import 'package:xpense_app/core/ui/ui.dart';

Future<void> _hold(WidgetTester tester, int tenths) async {
  for (var i = 0; i < tenths; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _key(WidgetTester tester, String key) async {
  await tester.tap(
    key == 'del' ? find.bySemanticsLabel('Delete').last : find.text(key).last,
  );
  await _hold(tester, 3);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('demo', (tester) async {
    final app = await bootstrap(environment: AppEnvironment.fakes);
    final container = ProviderContainer(overrides: app.overrides);
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const XpenseApp()),
    );
    await tester.pumpAndSettle();
    await _hold(tester, 15);

    // Home asks for today's rate; Change, and a slip of the finger.
    expect(find.byType(RatePrompt), findsOneWidget);
    await tester.tap(find.text('Change'));
    await _hold(tester, 8);
    await _key(tester, '0');
    await tester.tap(find.text('Save').last);
    await _hold(tester, 15);
    expect(find.textContaining('more than 5%'), findsOneWidget);
    await tester.tap(find.text('Change it'));
    await _hold(tester, 8);
    await _key(tester, 'del');
    await _key(tester, 'del');
    await _key(tester, 'del');
    await _key(tester, '2');
    await _key(tester, '0');
    await tester.tap(find.text('Save').last);
    await _hold(tester, 12);
    expect(find.byType(RatePrompt), findsNothing);

    // The history in Settings.
    container.read(routerProvider).push<void>(AppRoutes.settingsRate).ignore();
    await _hold(tester, 25);

    // Rename a category.
    container
        .read(routerProvider)
        .push<void>(AppRoutes.settingsCategories)
        .ignore();
    await _hold(tester, 10);
    await tester.tap(find.byKey(const ValueKey('category_groceries')));
    await _hold(tester, 8);
    await tester.tap(find.text('Rename'));
    await _hold(tester, 8);
    await tester.enterText(
      find.descendant(
        of: find.byType(GlassSheet),
        matching: find.byType(CupertinoTextField),
      ),
      'Food shop',
    );
    await _hold(tester, 8);
    await tester.tap(find.text('Save').last);
    await _hold(tester, 20);
    expect(find.text('Food shop'), findsOneWidget);
  });
}
