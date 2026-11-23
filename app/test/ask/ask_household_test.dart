// The household Ask uses: built from the app's own household data, so the
// ids on a card are ones the write path can save.
import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xpense_app/app.dart';
import 'package:xpense_app/bootstrap.dart';
import 'package:xpense_app/core/routing/routing.dart';
import 'package:xpense_app/data/accounts_repository.dart';
import 'package:xpense_app/data/accounts_repository_fake.dart';
import 'package:xpense_app/data/household_repository.dart';
import 'package:xpense_app/data/household_repository_fake.dart';
import 'package:xpense_app/data/rules_repository.dart';
import 'package:xpense_app/data/write/ledger_store.dart';
import 'package:xpense_app/data/write/ledger_transactions_repository.dart';
import 'package:xpense_app/features/ask/ask_household.dart';
import 'package:xpense_app/features/ask/ledger_xpense_actions.dart';
import 'package:xpense_shared/xpense_shared.dart';

import '../support/test_app.dart';

void main() {
  _firstRateTest();
  _fakesShareTheLedgerTests();

  test('accounts, partner, base currency and rate come from the app', () {
    final h = xpenseHouseholdFrom(
      membership: const InHousehold(FakeHouseholdRepository.sampleHousehold),
      accounts: const [
        Account(
          id: 'a1',
          name: 'Checking',
          kind: AccountKind.bank,
          currency: Currency.usd,
          scope: AccountScope.personal,
          visibleTo: ['me'],
        ),
        Account(
          id: 'a2',
          name: 'Old cash',
          kind: AccountKind.cash,
          currency: Currency.iqd,
          scope: AccountScope.personal,
          visibleTo: ['me'],
          archived: true,
        ),
      ],
      members: const [
        HouseholdMember(uid: 'me', displayName: 'Dara'),
        HouseholdMember(uid: 'p', displayName: 'Shilan'),
      ],
      viewerUid: 'me',
      latestRate: FxRate.parse('USD/IQD', '1520').valueOrNull,
    );
    expect(h.baseCurrency, 'USD');
    expect([for (final a in h.accounts) a.id], ['a1'], reason: 'not archived');
    expect(h.accounts.single.currency, 'USD');
    expect(h.partnerName, 'Shilan');
    expect(h.latestRate, '1520');
    expect(h.category('groceries')?.name, 'Groceries');
    expect(h.category('other_expense'), isNotNull);
  });

  testWidgets('in the fakes environment a card saves through the write path', (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(390, 1400) * 3
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final services = TestServices(accounts: FakeAccountsRepository.sample())
      ..xpenseActionsFor = connectXpenseActions;
    // The sample household's own account id, as a learned rule.
    await services.rules.learn(
      const RuleLesson(
        kind: RuleKind.merchant,
        pattern: 'Costco',
        categoryId: 'groceries',
        accountId: 'acc-checking',
      ),
    );
    final container = await pumpXpenseApp(tester, services);
    container.read(routerProvider).go(AppRoutes.ask);
    await tester.pumpAndSettle();
    expect(
      container.read(askHouseholdProvider).account('acc-checking'),
      isNotNull,
    );
    await tester.enterText(find.byType(EditableText), 'Costco 42.80');
    await tester.testTextInput.receiveAction(TextInputAction.send);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.text('Saved.'), findsOneWidget);
    expect(services.actions.saved, isEmpty, reason: 'not the fake');
  });
}

void _firstRateTest() {
  testWidgets('a new household with no rate: the slip asks for the first '
      'rate, and the dinar entry then saves', (tester) async {
    tester.view
      ..physicalSize = const Size(390, 1400) * 3
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    // No rate anywhere: not in the household's data, not in the ledger.
    final accounts = FakeAccountsRepository(
      accounts: FakeAccountsRepository.sampleAccounts,
    );
    final services = TestServices(accounts: accounts);
    final store = sampleLedgerStore(clock: services.clock.clock)..rates.clear();
    // One fxRates collection in Firestore: what the member enters is what
    // the write path reads.
    final linked = accounts.fx.watchRates().listen((rates) {
      for (final r in rates) {
        store.rates[r.day] = DayRate(day: r.day, rate: r.rate, kind: 'market');
      }
    });
    // Not awaited: cancelling the fake's async* stream mid-wait never
    // completes.
    addTearDown(() => unawaited(linked.cancel()));
    services.xpenseActionsFor = (ref) {
      ref.listen(askHouseholdProvider, (_, _) {});
      return LedgerXpenseActions(
        inner: services.actions,
        transactions: LedgerTransactionsRepository(store),
        fx: accounts.fx,
        readHousehold: () => ref.read(askHouseholdProvider),
        clock: services.clock.clock,
      );
    };
    await services.rules.learn(
      const RuleLesson(
        kind: RuleKind.merchant,
        pattern: 'samoon',
        categoryId: 'groceries',
        accountId: 'acc-cash',
      ),
    );
    final container = await pumpXpenseApp(tester, services);
    container.read(routerProvider).go(AppRoutes.ask);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(EditableText), 'Samoon 10000 dinars');
    await tester.testTextInput.receiveAction(TextInputAction.send);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(
      find.text("Enter today's dollar rate to save this."),
      findsOneWidget,
    );

    await tester.tap(find.text('Enter rate'));
    // The glass sheet never settles; let it finish sliding in.
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    for (final key in ['1', '5', '0', '0']) {
      await tester.tap(find.text(key).last);
      await tester.pump();
    }
    await tester.tap(find.text('Save').last);
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect([for (final r in accounts.fx.written) r.rate.rateString], ['1500']);
    expect(find.text('Enter rate'), findsNothing);

    await tester.tap(find.text('Save'));
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('Saved.'), findsOneWidget);
    final saved = store.transactions.values.single;
    expect(saved['currency'], 'IQD');
    expect(saved['baseAmountMinor'], 667, reason: '10,000 / 1,500');
  });
}

void _fakesShareTheLedgerTests() {
  test('in fakes, accounts, members and rates reach the ledger', () async {
    final clock = Clock.fixed(DateTime(2026, 11, 22, 9));
    final store = sampleLedgerStore(clock: clock);
    final accounts = FakeAccountsRepository.sample(ledger: store, clock: clock);
    await accounts.fx.setRate(
      '2026-11-22',
      FxRate.forPair(FxPair.usdIqd, '1800').valueOrNull!,
    );
    expect(store.rates['2026-11-22']?.rate.rateString, '1800');
    final created = await accounts.create(
      const AccountDraft(
        name: 'Wallet',
        kind: AccountKind.cash,
        currency: Currency.iqd,
        scope: AccountScope.personal,
      ),
    );
    final id = (created as Ok<String, AccountsFailure>).value;
    expect(store.accounts[id]?.currency, Currency.iqd);
    accounts.setMembers(const [
      HouseholdMember(
        uid: FakeAccountsRepository.sampleViewer,
        displayName: 'You',
      ),
    ]);
    expect(store.householdInfo?.memberIds, [
      FakeAccountsRepository.sampleViewer,
    ]);
  });

  testWidgets('in fakes, a rate changed on the slip is the rate saved', (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(390, 1400) * 3
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final clock = TestClock();
    final store = sampleLedgerStore(clock: clock.clock);
    // As bootstrap wires the fakes build: one store behind both.
    final accounts = FakeAccountsRepository.sample(
      ledger: store,
      clock: clock.clock,
    );
    final services = TestServices(accounts: accounts);
    services.clock.now = clock.now;
    services.xpenseActionsFor = (ref) {
      ref.listen(askHouseholdProvider, (_, _) {});
      return LedgerXpenseActions(
        inner: services.actions,
        transactions: LedgerTransactionsRepository(store),
        fx: accounts.fx,
        readHousehold: () => ref.read(askHouseholdProvider),
        clock: services.clock.clock,
      );
    };
    await services.rules.learn(
      const RuleLesson(
        kind: RuleKind.merchant,
        pattern: 'samoon',
        categoryId: 'groceries',
        accountId: 'acc-cash',
      ),
    );
    final container = await pumpXpenseApp(tester, services);
    container.read(routerProvider).go(AppRoutes.ask);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(EditableText), 'Samoon 18000 dinars');
    await tester.testTextInput.receiveAction(TextInputAction.send);
    await tester.pumpAndSettle();

    // The sample's 1,705 is offered; the member changes it to 1,800.
    await tester.tap(find.text('Change'));
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    for (final key in ['⌫', '⌫', '⌫', '⌫', '1', '8', '0', '0']) {
      await tester.tap(find.text(key).last);
      await tester.pump();
    }
    await tester.tap(find.text('Save').last);
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.tap(find.text('Save'));
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(find.text('Saved.'), findsOneWidget);
    final saved = store.transactions.values.single;
    expect((saved['fx']! as Map)['pairRate'], '1800');
    expect(saved['baseAmountMinor'], 1000);
  });
}
