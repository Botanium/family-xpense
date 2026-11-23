// Ask saves through the transaction write path (WP-20).
import 'package:flutter_test/flutter_test.dart';
import 'package:xpense_app/a2ui/testing/fake_xpense_actions.dart';
import 'package:xpense_app/a2ui/xpense_surface_host.dart';
import 'package:xpense_app/bootstrap.dart';
import 'package:xpense_app/data/transactions_repository.dart';
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

void main() {
  late FakeXpenseActions inner;
  late LedgerXpenseActions actions;

  setUp(() {
    inner = FakeXpenseActions();
    actions = LedgerXpenseActions(
      inner: inner,
      transactions: memoryTransactions(),
      readHousehold: () => inner.household,
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

  test('the rest goes to the inner actions', () async {
    expect(actions.household, same(inner.household));
    await actions.setDailyRate('1500');
    expect(inner.household.latestRate, '1500');
  });
}
