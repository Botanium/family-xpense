import 'package:flutter_test/flutter_test.dart';
import 'package:xpense_app/data/transactions_repository.dart';
import 'package:xpense_app/features/capture/manual/manual_entry.dart';
import 'package:xpense_shared/xpense_shared.dart';

const Map<String, Currency> _currencies = {
  'usd': Currency.usd,
  'usd2': Currency.usd,
  'iqd': Currency.iqd,
};

ManualEntryCheck _check(ManualEntryValues values, {EntryDraft? initial}) =>
    checkManualEntry(
      values,
      draftId: 'd1',
      currencyOf: (id) => _currencies[id],
      base: Currency.usd,
      initial: initial,
    );

const _day = '2026-11-22';

void main() {
  group('checkManualEntry', () {
    test('an expense reads into a draft in the account currency', () {
      final check = _check(
        const ManualEntryValues(
          kind: ManualKind.expense,
          occurredOn: _day,
          amountText: '42.80',
          accountId: 'usd',
          categoryId: 'groceries',
          who: 'joint',
          note: '  weekly shop ',
        ),
      );
      expect(check.ok, isTrue);
      final draft = check.draft!;
      expect(draft.intent, 'expense');
      expect(draft.amountMinor, 4280);
      expect(draft.currency, 'USD');
      expect(draft.categoryId, 'groceries');
      expect(draft.who, 'joint');
      expect(draft.occurredOn, _day);
      expect(draft.note, 'weekly shop');
      expect(draft.toAccountId, isNull);
    });

    test('dinars take no decimals', () {
      final check = _check(
        const ManualEntryValues(
          kind: ManualKind.expense,
          occurredOn: _day,
          amountText: '10000.5',
          accountId: 'iqd',
          categoryId: 'dining',
        ),
      );
      expect(check.errors, {ManualField.amount: ManualIssue.invalid});
      final ok = _check(
        const ManualEntryValues(
          kind: ManualKind.expense,
          occurredOn: _day,
          amountText: '10,000',
          accountId: 'iqd',
          categoryId: 'dining',
        ),
      );
      expect(ok.draft!.amountMinor, 10000);
      expect(ok.draft!.currency, 'IQD');
    });

    test('empty fields are named next to themselves', () {
      final check = _check(
        const ManualEntryValues(kind: ManualKind.income, occurredOn: _day),
      );
      expect(check.errors, {
        ManualField.account: ManualIssue.missing,
        ManualField.amount: ManualIssue.missing,
        ManualField.category: ManualIssue.missing,
      });
      final zero = _check(
        const ManualEntryValues(
          kind: ManualKind.income,
          occurredOn: _day,
          amountText: '0',
          accountId: 'usd',
          categoryId: 'salary',
        ),
      );
      expect(zero.errors, {ManualField.amount: ManualIssue.outOfRange});
    });

    test('a transfer needs another account; a typed arrival is an extra', () {
      const base = ManualEntryValues(
        kind: ManualKind.transfer,
        occurredOn: _day,
        amountText: '100',
        accountId: 'usd',
      );
      expect(_check(base).errors, {ManualField.toAccount: ManualIssue.missing});
      expect(_check(base.copyWith(toAccountId: 'usd')).errors, {
        ManualField.toAccount: ManualIssue.sameAccount,
      });
      final same = _check(base.copyWith(toAccountId: 'usd2'));
      expect(same.draft!.toAccountId, 'usd2');
      expect(same.extras.toAmountMinor, isNull);
      final cross = _check(
        base.copyWith(toAccountId: 'iqd', toAmountText: '150000'),
      );
      expect(cross.draft!.intent, 'transfer');
      expect(cross.extras.toAmountMinor, 150000);
      expect(cross.draft!.categoryId, isNull);
      final badArrival = _check(
        base.copyWith(toAccountId: 'iqd', toAmountText: '1.5'),
      );
      expect(badArrival.errors, {ManualField.toAmount: ManualIssue.invalid});
    });

    test('a loan needs a person and takes its direction', () {
      const loan = ManualEntryValues(
        kind: ManualKind.loan,
        occurredOn: _day,
        amountText: '300',
        accountId: 'usd',
        loanDirection: LoanDirection.borrowed,
      );
      expect(_check(loan).errors, {ManualField.person: ManualIssue.missing});
      final draft = _check(loan.copyWith(personName: ' Alex ')).draft!;
      expect(draft.intent, 'loan_taken');
      expect(draft.personName, 'Alex');
      expect(draft.categoryId, isNull);
      for (final d in LoanDirection.values) {
        expect(
          _check(loan.copyWith(loanDirection: d, personName: 'Alex'))
              .draft!
              .intent,
          d.intent,
        );
      }
    });

    test('a category is only kept for expense and income', () {
      const values = ManualEntryValues(
        kind: ManualKind.expense,
        occurredOn: _day,
        amountText: '5',
        accountId: 'usd',
        categoryId: 'groceries',
      );
      final transfer = _check(
        values.copyWith(kind: ManualKind.transfer, toAccountId: 'usd2'),
      );
      expect(transfer.draft!.categoryId, isNull);
    });

    test('a note over 500 characters is refused', () {
      final check = _check(
        ManualEntryValues(
          kind: ManualKind.expense,
          occurredOn: _day,
          amountText: '5',
          accountId: 'usd',
          categoryId: 'groceries',
          note: 'x' * 501,
        ),
      );
      expect(check.errors, {ManualField.note: ManualIssue.tooLong});
    });

    test('a typed rate is stored as manual for the entry day', () {
      const values = ManualEntryValues(
        kind: ManualKind.expense,
        occurredOn: _day,
        amountText: '10000',
        accountId: 'iqd',
        categoryId: 'dining',
        rateAsked: true,
      );
      expect(_check(values).errors, {ManualField.rate: ManualIssue.rateNeeded});
      expect(_check(values.copyWith(rateText: 'abc')).errors, {
        ManualField.rate: ManualIssue.invalid,
      });
      final fx = _check(values.copyWith(rateText: '1,705')).draft!.fx!;
      expect(fx.pair, 'USD/IQD');
      expect(fx.pairRate, '1705');
      expect(fx.source, 'manual');
      expect(fx.asOf, _day);
    });

    test('a prefilled draft keeps what the form does not show', () {
      final initial = EntryDraft(
        id: 'slip-1',
        intent: 'expense',
        amountMinor: 10000,
        currency: 'IQD',
        accountId: 'iqd',
        categoryId: 'dining',
        who: 'me',
        occurredOn: '2026-11-21',
        occurredTime: '13:20',
        title: 'Kebab place',
        note: 'lunch',
        origin: 'parser',
        guessed: const ['categoryId'],
        confidence: DraftConfidence(category: 0.6),
      );
      final values = ManualEntryValues.fromDraft(initial, today: _day);
      expect(values.amountText, '10000');
      expect(values.occurredOn, '2026-11-21');
      expect(values.kind, ManualKind.expense);
      final draft = _check(
        values.copyWith(categoryId: 'groceries'),
        initial: initial,
      ).draft!;
      expect(draft.id, 'd1');
      expect(draft.categoryId, 'groceries');
      expect(draft.title, 'Kebab place');
      expect(draft.origin, 'parser');
      expect(draft.occurredTime, '13:20');
      expect(draft.guessed, ['categoryId']);
    });

    test('a USD amount prefills with its cents', () {
      final values = ManualEntryValues.fromDraft(
        EntryDraft(
          id: 'x',
          intent: 'income',
          amountMinor: 4280,
          currency: 'USD',
        ),
        today: _day,
      );
      expect(values.amountText, '42.80');
      expect(values.kind, ManualKind.income);
    });

    test('a savings move into a goal keeps its intent and goal', () {
      // Codex review, PR #39: prefilling turned it into a plain transfer
      // that then asked for a destination account.
      final initial = EntryDraft(
        id: 'slip-2',
        intent: 'savings_move',
        amountMinor: 20000,
        currency: 'USD',
        accountId: 'usd',
        goalId: 'goal-trip',
      );
      final values = ManualEntryValues.fromDraft(initial, today: _day);
      expect(values.kind, ManualKind.transfer);
      final check = _check(values, initial: initial);
      expect(check.errors, isEmpty);
      expect(check.draft!.intent, 'savings_move');
      expect(check.draft!.goalId, 'goal-trip');
      expect(check.draft!.toAccountId, isNull);

      // Another tab ends it: back on Transfer it is a plain transfer.
      final moved = values
          .copyWith(kind: ManualKind.expense)
          .copyWith(kind: ManualKind.transfer);
      expect(moved.intent, 'transfer');
      expect(_check(moved, initial: initial).errors, {
        ManualField.toAccount: ManualIssue.missing,
      });
    });

    test('a category of the other kind counts as none chosen', () {
      // What the chips show (nothing) is what is checked.
      final check = _check(
        const ManualEntryValues(
          kind: ManualKind.income,
          occurredOn: _day,
          amountText: '5',
          accountId: 'usd',
          categoryId: 'groceries',
        ),
      );
      expect(check.errors, {ManualField.category: ManualIssue.missing});
    });

    test('the default Who follows the account, as the write path does', () {
      expect(defaultWho(joint: true, ownerUid: null, viewerUid: 'u1'), 'joint');
      expect(defaultWho(joint: false, ownerUid: 'u1', viewerUid: 'u1'), 'me');
      expect(defaultWho(joint: false, ownerUid: null, viewerUid: 'u1'), 'me');
      expect(
        defaultWho(joint: false, ownerUid: 'u2', viewerUid: 'u1'),
        'partner',
      );
    });

    test('an adjustment keeps its intent and hides the tabs', () {
      final values = ManualEntryValues.fromDraft(
        EntryDraft(
          id: 'x',
          intent: 'adjustment',
          amountMinor: 100,
          currency: 'USD',
          accountId: 'usd',
        ),
        today: _day,
      );
      expect(values.otherIntent, 'adjustment');
      expect(_check(values).draft!.intent, 'adjustment');
    });
  });

  group('placeFailure', () {
    test('field failures land next to their field', () {
      expect(
        placeFailure(
          const EntryInvalid(
            draftId: 'd1',
            field: 'categoryId',
            issue: EntryIssue.wrongCategoryKind,
          ),
        ),
        isA<ManualFailure>()
            .having((f) => f.field, 'field', ManualField.category)
            .having((f) => f.issue, 'issue', ManualIssue.wrongKind),
      );
      expect(
        placeFailure(
          const EntryRateNeeded(draftId: 'd1', from: 'IQD', to: 'USD'),
        ).field,
        ManualField.rate,
      );
      expect(
        placeFailure(
          const EntryInvalid(
            draftId: 'd1',
            field: 'who',
            issue: EntryIssue.noPartner,
          ),
        ).issue,
        ManualIssue.noPartner,
      );
    });

    test('the rest becomes a toast', () {
      for (final failure in const <TransactionsFailure>[
        TransactionsNotAllowed(),
        TooManyEntries(),
        TransactionConflict(),
        TransactionsUnknown('x'),
        EntryInvalid(
          draftId: 'd1',
          field: 'intent',
          issue: EntryIssue.notMoney,
        ),
      ]) {
        final placed = placeFailure(failure);
        expect(placed.field, isNull);
        expect(placed.toast, failure);
      }
    });
  });

  test('manualDay is the local calendar day', () {
    expect(manualDay(DateTime(2026, 1, 5, 23, 59)), '2026-01-05');
  });
}
