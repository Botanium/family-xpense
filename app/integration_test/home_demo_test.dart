// The WP-23 demo for the PR (DELEGATION rule 11), on the `fakes`
// environment with its sample month: Home's balance, daily bars and ledger,
// a new expense moving Spent, the bars and Recent at once, then "See all"
// opening Activity. Paced for a short recording:
//
//   tools/pr_demo.sh start <device>
//   cd app && flutter test integration_test/home_demo_test.dart -d <device>
//   tools/pr_demo.sh stop
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:xpense_app/app.dart';
import 'package:xpense_app/bootstrap.dart';
import 'package:xpense_app/core/routing/routing.dart';
import 'package:xpense_app/data/transactions_repository.dart';
import 'package:xpense_app/features/home/home_screen.dart';
import 'package:xpense_shared/xpense_shared.dart';

Future<void> _hold(WidgetTester tester, int tenths) async {
  for (var i = 0; i < tenths; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('home demo', (tester) async {
    final app = await bootstrap(environment: AppEnvironment.fakes);
    final container = ProviderContainer(overrides: app.overrides);
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const XpenseApp()),
    );
    await tester.pumpAndSettle();
    expect(find.byType(HomeScreen), findsOneWidget);
    await _hold(tester, 30);

    // A new expense, saved through the write path: the totals follow.
    final now = DateTime.now();
    final day =
        '${now.year}-${'${now.month}'.padLeft(2, '0')}-'
        '${'${now.day}'.padLeft(2, '0')}';
    final saved = await container
        .read(transactionsRepositoryProvider)
        .saveEntries([
          EntryDraft(
            id: 'demo',
            intent: 'expense',
            amountMinor: 18000,
            currency: 'USD',
            accountId: 'acc-visa',
            categoryId: 'groceries',
            title: 'Carrefour',
            occurredOn: day,
            occurredTime: '23:59',
          ),
        ]);
    expect(saved.isOk, isTrue, reason: '$saved');
    await _hold(tester, 30);
    expect(find.text('Carrefour'), findsOneWidget);

    // Down to Recent, then "See all" opens Activity.
    await tester.drag(find.byType(ListView).first, const Offset(0, -320));
    await _hold(tester, 20);
    await tester.tap(find.text('See all'));
    await _hold(tester, 15);
    expect(container.read(routerProvider).state.uri.path, AppRoutes.activity);
    await _hold(tester, 10);
  });
}
