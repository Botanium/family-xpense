// The WP-13 demo for the PR (DELEGATION rule 11), on the `fakes`
// environment: Accounts with "Your view", the filter bar, then sharing a
// private account and its "Sharing past entries…" line. Paced for a short
// recording:
//
//   tools/pr_demo.sh start <device>
//   cd app && flutter test integration_test/accounts_demo_test.dart -d <device>
//   tools/pr_demo.sh stop
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

Future<void> _tap(WidgetTester tester, Finder target) async {
  await tester.tap(target);
  await _hold(tester, 8);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('accounts demo', (tester) async {
    final app = await bootstrap(environment: AppEnvironment.fakes);
    final container = ProviderContainer(overrides: app.overrides);
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const XpenseApp()),
    );
    await tester.pumpAndSettle();
    container.read(routerProvider).go(AppRoutes.accounts);
    await tester.pumpAndSettle();
    await _hold(tester, 25);

    // The filter bar: Sam's shared account, then back to All.
    await _tap(tester, find.text('Sam'));
    await _hold(tester, 10);
    await _tap(tester, find.text('All'));

    // Share the private checking account; the history follows.
    await _tap(tester, find.text('My checking ••1187'));
    await _hold(tester, 12);
    await _tap(tester, find.byType(XpSwitch));
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.textContaining('Sharing past entries'), findsNothing);
    await _hold(tester, 10);
    await _tap(tester, find.bySemanticsLabel('Back'));
    await _hold(tester, 15);
    expect(find.text('Bank account · You, shared'), findsOneWidget);
  });
}
