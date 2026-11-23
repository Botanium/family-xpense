// WP-21 on the simulator, on the `fakes` environment (no Firebase):
//
// - "walk-through" saves an expense, an income, a transfer and a loan
//   through Add manually, then opens an entry's detail, edits it from a
//   row and restores the old value from its history.
// - "demo" is the same without income and transfer, paced, for the PR
//   recording:
//
//   tools/pr_demo.sh start <device>
//   cd app && flutter test integration_test/manual_entry_demo_test.dart \
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
import 'package:xpense_app/data/transactions_repository.dart';
import 'package:xpense_shared/xpense_shared.dart';

Future<void> _hold(WidgetTester tester, int tenths) async {
  for (var i = 0; i < tenths; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Finder _amount() => find
    .descendant(
      of: find.byType(AmountField),
      matching: find.byType(CupertinoTextField),
    )
    .first;

Finder _field(String label) => find.descendant(
  of: find.widgetWithText(XpTextField, label),
  matching: find.byType(CupertinoTextField),
);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Future<ProviderContainer> start(WidgetTester tester) async {
    final app = await bootstrap(environment: AppEnvironment.fakes);
    final container = ProviderContainer(overrides: app.overrides);
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const XpenseApp()),
    );
    await tester.pumpAndSettle();
    return container;
  }

  Future<void> run(
    WidgetTester tester, {
    required int pace,
    bool everyType = true,
  }) async {
    Future<void> tap(Finder target) async {
      await tester.ensureVisible(target);
      await tester.pumpAndSettle();
      await tester.tap(target);
      await tester.pumpAndSettle();
      await _hold(tester, pace);
    }

    Future<void> type(Finder field, String text) async {
      await tester.ensureVisible(field);
      await tester.enterText(field, text);
      await tester.pumpAndSettle();
      await _hold(tester, pace);
    }

    Future<void> saved() async {
      expect(find.text('Saved'), findsWidgets);
      await _hold(tester, pace * 2);
    }

    final container = await start(tester);
    final router = container.read(routerProvider);
    Future<void> open() async {
      router.push<void>(AppRoutes.addEntry).ignore();
      await tester.pumpAndSettle();
      await _hold(tester, pace);
      expect(find.text('Add manually'), findsOneWidget);
    }

    // Expense: amount, category, who, then Save (the header's, so a
    // toast from the last save never sits over the button tapped).
    await open();
    await type(_amount(), '42.80');
    await tap(find.text('Food'));
    await tap(find.text('Groceries'));
    await tap(find.text('Joint'));
    await tap(find.text('Save'));
    await saved();

    if (everyType) {
      // Income in dinars: the currency follows the account.
      await open();
      await tap(find.text('Income'));
      await tap(find.widgetWithText(XpDisclosure, 'Account'));
      await tap(find.text('Cash (IQD)').last);
      expect(find.text('IQD'), findsOneWidget);
      await type(_amount(), '250000');
      await tap(find.text('Received'));
      await tap(find.text('Gifts received'));
      await tap(find.text('Save'));
      // The fakes ledger has no dollar rate yet: the sheet asks inline.
      expect(
        find.text("There's no dollar rate for this day yet. Enter it to save."),
        findsOneWidget,
      );
      await type(_field('Dollar rate, dinars per dollar'), '1705');
      await tap(find.text('Save'));
      await saved();

      // Transfer to the savings account.
      await open();
      await tap(find.text('Transfer'));
      await type(_amount(), '100');
      await tap(find.widgetWithText(XpDisclosure, 'To'));
      await tap(find.text('Summer trip').last);
      await tap(find.text('Save'));
      await saved();
    }

    // Loan: a missing person is named next to the field.
    await open();
    await tap(find.text('Loan'));
    await type(_amount(), '300');
    await tap(find.text('Save'));
    expect(find.text("Add who it's with."), findsOneWidget);
    await _hold(tester, pace);
    await type(_field('Person'), 'Alex');
    await tap(find.text('Save'));
    await saved();

    // Entry detail: edit a row, then restore from the history.
    final seeded = await container
        .read(transactionsRepositoryProvider)
        .saveEntries([
          EntryDraft(
            id: 'demo',
            intent: 'expense',
            amountMinor: 10000,
            currency: 'IQD',
            accountId: 'acc-cash',
            categoryId: 'dining',
            who: 'me',
            note: 'Lunch with the kids',
            fx: FxQuote(pair: 'USD/IQD', pairRate: '1705', source: 'market'),
          ),
        ], source: EntrySource.voice);
    final id = seeded.valueOrNull!.txnIds.single;
    router.push<void>(AppRoutes.entry(id)).ignore();
    await tester.pumpAndSettle();
    await _hold(tester, pace * 2);
    expect(find.text('EXPENSE · DINING OUT'), findsOneWidget);
    await tap(find.widgetWithText(XpDisclosure, 'Category'));
    expect(find.text('Edit entry'), findsOneWidget);
    await tap(find.text('Groceries'));
    await tap(find.text('Save changes'));
    expect(find.text('EXPENSE · GROCERIES'), findsOneWidget);
    await tester.ensureVisible(find.text('Category changed'));
    await tester.pumpAndSettle();
    await _hold(tester, pace * 2);
    await tap(find.text('Restore'));
    expect(find.text('EXPENSE · DINING OUT'), findsOneWidget);
    await _hold(tester, pace * 2);
  }

  testWidgets('walk-through', (tester) => run(tester, pace: 0));

  testWidgets('demo', (tester) => run(tester, pace: 3, everyType: false));
}
