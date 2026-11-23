// Ask saves through the transaction write path (WP-20).
import 'package:clock/clock.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xpense_app/a2ui/testing/fake_xpense_actions.dart';
import 'package:xpense_app/a2ui/xpense_surface_host.dart';
import 'package:xpense_app/bootstrap.dart';
import 'package:xpense_app/data/accounts_repository_fake.dart';
import 'package:xpense_app/data/transactions_repository.dart';
import 'package:xpense_app/data/write/ledger_store.dart';
import 'package:xpense_app/data/write/ledger_transactions_repository.dart';
import 'package:xpense_app/data/write/memory_ledger_store.dart';
import 'package:xpense_app/features/ask/ledger_xpense_actions.dart';
import 'package:xpense_shared/xpense_shared.dart';

EntryDraft _draft({String accountId = 'acc-checking'}) => EntryDraft(
  id: 'd1',
  intent: 'expense',
  amountMinor: 4280,
  currency: 'USD',
  accountId: accountId,
  categoryId: 'groceries',
  who: 'me',
  occurredOn: '2026-11-22',
  title: 'Costco',
  origin: 'decisions',
);

final _clock = Clock.fixed(DateTime(2026, 11, 23, 12));

void main() {
  late FakeXpenseActions inner;
  late FakeAccountsRepository accounts;
  late MemoryLedgerStore store;
  late LedgerXpenseActions actions;

  setUp(() {
    inner = FakeXpenseActions();
    accounts = FakeAccountsRepository.sample();
    store = sampleLedgerStore(clock: _clock);
    actions = LedgerXpenseActions(
      inner: inner,
      transactions: LedgerTransactionsRepository(store),
      accounts: accounts,
      readHousehold: () => inner.household,
      clock: _clock,
    );
  });

  test('a card saves through saveEntries, not the in-memory fake', () async {
    final outcome = await actions.saveDrafts('s1', [_draft()]);
    expect(outcome, isA<DraftsSaved>());
    final saved = outcome as DraftsSaved;
    expect(saved.txnIds, hasLength(1));
    expect(inner.saved, isEmpty);
    expect(inner.calls.where((c) => c.method == 'saveDrafts'), isEmpty);
  });

  test('Undo undoes that save once', () async {
    final saved = await actions.saveDrafts('s1', [_draft()]) as DraftsSaved;
    await actions.undoSave(saved.groupId);
    expect(() => actions.undoSave(saved.groupId), throwsStateError);
  });

  test('a refused draft is a failed save; nothing is written', () async {
    final outcome = await actions.saveDrafts('s1', [
      _draft(accountId: 'acc_missing'),
    ]);
    expect(outcome, isA<SaveFailed>());
    expect((outcome as SaveFailed).reason, SaveFailure.invalid);
  });

  test('failures map to what the card can say', () {
    expect(saveFailureOf(const TransactionsNotAllowed()), SaveFailure.denied);
    expect(saveFailureOf(const TooManyEntries()), SaveFailure.invalid);
    expect(saveFailureOf(const TransactionsUnknown('x')), SaveFailure.unknown);
  });

  test('the household is the one read, until a rate is answered', () {
    expect(actions.household, same(inner.household));
  });

  test("a rate answer is saved as today's rate, not in the fake", () async {
    await actions.setDailyRate('1500');
    expect([for (final r in accounts.dailyRates) r.rateString], ['1500']);
    expect(inner.calls.where((c) => c.method == 'setDailyRate'), isEmpty);
    expect(actions.household.latestRate, '1500');
    expect(actions.household.rateEnteredToday, isTrue, reason: 'no prompt');
  });

  test('after a rate answer, a card quoted at an older rate saves at the '
      "day's rate", () async {
    await actions.setDailyRate('1500');
    // The same Firestore collection the write path reads.
    store.rates['2026-11-23'] = DayRate(
      day: '2026-11-23',
      rate: FxRate.forPair(FxPair.usdIqd, '1500').valueOrNull!,
      kind: 'market',
    );
    final outcome = await actions.saveDrafts('s1', [
      EntryDraft(
        id: 'd2',
        intent: 'expense',
        amountMinor: 15000,
        currency: 'IQD',
        accountId: 'acc-cash',
        categoryId: 'groceries',
        who: 'me',
        occurredOn: '2026-11-23',
        title: 'Bread',
        origin: 'agent',
        fx: FxQuote(pair: 'USD/IQD', pairRate: '1705', baseAmountMinor: 880),
      ),
    ]) as DraftsSaved;
    final stored = store.transactions[outcome.txnIds.single]!;
    expect((stored['fx']! as Map)['pairRate'], '1500');
    expect(stored['baseAmountMinor'], 1000);
  });
}
