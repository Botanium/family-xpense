import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xpense_app/app.dart';
import 'package:xpense_app/core/routing/routing.dart';
import 'package:xpense_app/core/ui/ui.dart';
import 'package:xpense_app/data/accounts_repository.dart';
import 'package:xpense_app/data/accounts_repository_fake.dart';
import 'package:xpense_app/data/transactions_repository.dart';
import 'package:xpense_app/features/home/home_screen.dart';
import 'package:xpense_app/features/settings_privacy/settings_screen.dart';
import 'package:xpense_shared/xpense_shared.dart';

import '../support/test_app.dart';
import 'home_test_data.dart';

/// The value of the ledger row labelled [label].
String ledgerValue(WidgetTester tester, String label) => tester
    .widget<LedgerRow>(
      find.byWidgetPredicate((w) => w is LedgerRow && w.label == label),
    )
    .value;

ProviderContainer containerOf(WidgetTester tester) =>
    ProviderScope.containerOf(tester.element(find.byType(HomeScreen)));

void main() {
  testWidgets('shows the artboard month: header, hero, ledger, Recent', (
    tester,
  ) async {
    await pumpHome(tester, transactions: artboardMonth());

    expect(find.text('NOV 2026 · OUR HOME'), findsOneWidget);
    expect(find.text('Household balance'), findsOneWidget);
    final hero = tester.widget<HeroBalance>(find.byType(HeroBalance));
    expect(hero.minorUnits, 1248000);
    expect(hero.currencyMark, r'$');
    expect(hero.delta, '+1,240.00 this month');
    expect(hero.deltaPositive, isTrue);
    expect(hero.secondary, 'IQD\u00A021.3M');

    expect(ledgerValue(tester, 'Income'), '5,650.00');
    expect(ledgerValue(tester, 'Spent'), '4,410.00');
    expect(ledgerValue(tester, 'Saved'), '650.00');
    expect(find.text('AVG 210/DAY'), findsOneWidget);

    final bars = tester.widget<MiniBars>(find.byType(MiniBars));
    expect(bars.values, hasLength(21));
    expect(
      bars.summary,
      'Daily spending from November 1 to November 21. Average USD 210 a '
      'day. Today is the highest.',
    );

    for (final title in ['Costco', 'Salary', 'Shell', 'Lunch']) {
      expect(find.text(title), findsOneWidget, reason: title);
    }
    expect(find.text('Groceries · You'), findsOneWidget);
    expect(find.text('Fuel · Sam'), findsOneWidget);
    expect(find.text('Dining out · Joint'), findsOneWidget);
    expect(find.text('−42.80'), findsOneWidget);
    expect(find.text('+3,200.00'), findsOneWidget);
    expect(find.text('Private'), findsNothing);
  });

  testWidgets('a saved entry moves Spent, the bars and Recent at once', (
    tester,
  ) async {
    await pumpHome(tester, transactions: artboardMonth());

    final repository = containerOf(tester).read(transactionsRepositoryProvider);
    final saved = await tester.runAsync(
      () => repository.saveEntries([
        EntryDraft(
          id: 'd1',
          intent: 'expense',
          amountMinor: 1250,
          currency: 'USD',
          accountId: 'acc-visa',
          categoryId: 'dining',
          title: 'Blue Bottle',
          occurredOn: '2026-11-21',
          occurredTime: '20:00',
        ),
      ]),
    );
    expect(saved?.isOk, isTrue, reason: '$saved');
    await tester.pumpAndSettle();

    expect(ledgerValue(tester, 'Spent'), '4,422.50');
    expect(find.text('Blue Bottle'), findsOneWidget);
    final hero = tester.widget<HeroBalance>(find.byType(HeroBalance));
    expect(hero.delta, '+1,227.50 this month');
  });

  testWidgets('a deleted entry stops counting', (tester) async {
    final costco = artboardMonth().firstWhere((t) => t.title == 'Costco');
    await pumpHome(tester, transactions: artboardMonth());
    final repository = containerOf(tester).read(transactionsRepositoryProvider);

    final result = await tester.runAsync(
      () => repository.deleteEntry(costco.id),
    );
    expect(result?.isOk, isTrue, reason: '$result');
    await tester.pumpAndSettle();

    expect(ledgerValue(tester, 'Spent'), '4,367.20');
    expect(find.text('Costco'), findsNothing);
  });

  testWidgets('an empty month shows zeros and an empty Recent', (tester) async {
    await pumpHome(tester);

    expect(ledgerValue(tester, 'Income'), '0.00');
    expect(ledgerValue(tester, 'Spent'), '0.00');
    expect(find.text('No entries yet. Say or type one to start.'), findsOne);
    expect(
      tester.widget<MiniBars>(find.byType(MiniBars)).summary,
      'No spending yet this month.',
    );
  });

  testWidgets('a partner with private accounts makes it "Your view"', (
    tester,
  ) async {
    final services = TestServices(
      accounts: FakeAccountsRepository(
        members: const [
          HouseholdMember(uid: you, displayName: 'You'),
          HouseholdMember(
            uid: sam,
            displayName: 'Sam',
            hasPrivateAccounts: true,
          ),
        ],
        accounts: FakeAccountsRepository.sampleAccounts,
        rate: FxRate.forPair(FxPair.usdIqd, '1705').valueOrNull,
      ),
    );
    await pumpHome(tester, services: services);

    expect(find.text('Your view'), findsOneWidget);
    expect(find.text('Household balance'), findsNothing);
  });

  testWidgets('See all opens Activity; a Recent row opens the entry', (
    tester,
  ) async {
    await pumpHome(tester, transactions: artboardMonth());
    final router = containerOf(tester).read(routerProvider);

    await tester.tap(find.text('See all'));
    await tester.pumpAndSettle();
    expect(router.state.uri.path, AppRoutes.activity);

    router.go(AppRoutes.home);
    await tester.pumpAndSettle();
    final costco = artboardMonth().firstWhere((t) => t.title == 'Costco');
    await tester.ensureVisible(find.text('Costco'));
    await tester.tap(find.text('Costco'));
    await tester.pumpAndSettle();
    expect(router.state.uri.path, startsWith('/entries/'));
    expect(costco.title, 'Costco');
  });

  testWidgets('the avatar pair opens Settings; the nudge opens Ask', (
    tester,
  ) async {
    await pumpHome(tester, transactions: artboardMonth());
    final router = containerOf(tester).read(routerProvider);

    await tester.tap(find.bySemanticsLabel('Settings'));
    await tester.pumpAndSettle();
    expect(find.byType(SettingsScreen), findsOneWidget);

    router.go(AppRoutes.home);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ask').first);
    await tester.pumpAndSettle();
    expect(router.state.uri.path, AppRoutes.ask);
  });

  testWidgets('the chart is one spoken summary, not 21 bars', (tester) async {
    final semantics = tester.ensureSemantics();
    await pumpHome(tester, transactions: artboardMonth());

    expect(
      find.bySemanticsLabel(RegExp('^Daily spending from November 1')),
      findsOneWidget,
    );
    semantics.dispose();
  });

  for (final scale in [1.5, 2.0, 3.0]) {
    testWidgets('builds at ${scale}x text without overflow', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      await pumpHome(tester, transactions: artboardMonth());

      expect(tester.takeException(), isNull);
      expect(find.byType(HeroBalance), findsOneWidget);
    });
  }
}
