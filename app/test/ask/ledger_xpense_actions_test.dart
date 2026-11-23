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
      fx: accounts.fx,
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

  test(
    'only an entry with no rate for its date takes the answered rate',
    () async {
      store.rates
        ..clear()
        ..['2026-11-20'] = DayRate(
          day: '2026-11-20',
          rate: FxRate.forPair(FxPair.usdIqd, '1705').valueOrNull!,
          kind: 'market',
        );
      await actions.setDailyRate('1800');
      EntryDraft dinars(String id, String day) => EntryDraft(
        id: id,
        intent: 'expense',
        amountMinor: 18000,
        currency: 'IQD',
        accountId: 'acc-cash',
        categoryId: 'groceries',
        who: 'me',
        occurredOn: day,
        title: 'Bread',
        origin: 'agent',
      );
      final outcome = await actions.saveDrafts('s1', [
        dinars('d19', '2026-11-19'),
        dinars('d21', '2026-11-21'),
      ]) as DraftsSaved;
      final rates = {
        for (final id in outcome.txnIds)
          store.transactions[id]!['occurredOn']:
              (store.transactions[id]!['fx']! as Map)['pairRate'],
      };
      expect(rates, {'2026-11-19': '1800', '2026-11-21': '1705'});
    },
  );

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
    expect([for (final r in accounts.fx.written) r.rate.rateString], ['1500']);
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

  test("the partner's answer for today replaces a slip's older quote "
      '(Codex review, PR #42)', () async {
    store.rates['2026-11-23'] = DayRate(
      day: '2026-11-23',
      rate: FxRate.forPair(FxPair.usdIqd, '1750').valueOrNull!,
      kind: 'market',
    );
    final household = inner.household;
    final partnerAnswered = LedgerXpenseActions(
      inner: inner,
      transactions: LedgerTransactionsRepository(store),
      fx: accounts.fx,
      readHousehold: () => XpenseHousehold(
        baseCurrency: household.baseCurrency,
        accounts: household.accounts,
        categories: household.categories,
        latestRate: '1750',
        rateEnteredToday: true,
      ),
      clock: _clock,
    );
    final quoted = EntryDraft.fromJson({
      ..._draft(accountId: 'acc-cash').toJson(),
      'amountMinor': 17050,
      'currency': 'IQD',
      'occurredOn': '2026-11-23',
      'fx': FxQuote(
        pair: 'USD/IQD',
        pairRate: '1705',
        baseAmountMinor: 1000,
      ).toJson(),
    });
    final outcome = await partnerAnswered.saveDrafts('s1', [quoted]);
    expect(outcome, isA<DraftsSaved>());
    final txn = store.transactions.values.single;
    expect((txn['fx']! as Map)['pairRate'], '1750');
    expect((txn['fx']! as Map)['asOf'], '2026-11-23');
  });
}
