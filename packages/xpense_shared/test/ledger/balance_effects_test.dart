import 'dart:math';

import 'package:test/test.dart';
import 'package:xpense_shared/xpense_shared.dart';

LedgerLine line(
  LedgerType type, {
  int amount = 100,
  String account = 'a',
  String? to,
  int? toAmount,
  int sign = 1,
  String? loan,
  bool deleted = false,
}) => LedgerLine(
  type: type,
  amountMinor: amount,
  accountId: account,
  toAccountId: to,
  toAmountMinor: toAmount,
  adjustmentSign: sign,
  loanId: loan,
  deleted: deleted,
);

void main() {
  group('effectsOf follows DATA_MODEL 3', () {
    test('money out: expense, loan_given, repayment_made', () {
      for (final type in [
        LedgerType.expense,
        LedgerType.loanGiven,
        LedgerType.repaymentMade,
      ]) {
        expect(effectsOf(line(type)).accounts, {'a': -100}, reason: type.wire);
      }
    });

    test('money in: income, loan_taken, repayment_received', () {
      for (final type in [
        LedgerType.income,
        LedgerType.loanTaken,
        LedgerType.repaymentReceived,
      ]) {
        expect(effectsOf(line(type)).accounts, {'a': 100}, reason: type.wire);
      }
    });

    test('a transfer moves the same amount between two accounts', () {
      expect(effectsOf(line(LedgerType.transfer, to: 'b')).accounts, {
        'a': -100,
        'b': 100,
      });
    });

    test('a cross-currency transfer adds toAmountMinor', () {
      // 100.00 USD out, 170,500 IQD in.
      final effects = effectsOf(
        line(LedgerType.transfer, amount: 10000, to: 'iqd', toAmount: 170500),
      );
      expect(effects.accounts, {'a': -10000, 'iqd': 170500});
    });

    test('an adjustment takes its sign', () {
      expect(effectsOf(line(LedgerType.adjustment)).accounts, {'a': 100});
      expect(effectsOf(line(LedgerType.adjustment, sign: -1)).accounts, {
        'a': -100,
      });
    });

    test('loan events move the loan total', () {
      expect(effectsOf(line(LedgerType.loanGiven, loan: 'l')).loans, {
        'l': 100,
      });
      expect(effectsOf(line(LedgerType.loanTaken, loan: 'l')).loans, {
        'l': 100,
      });
      expect(effectsOf(line(LedgerType.repaymentReceived, loan: 'l')).loans, {
        'l': -100,
      });
      expect(effectsOf(line(LedgerType.repaymentMade, loan: 'l')).loans, {
        'l': -100,
      });
      expect(effectsOf(line(LedgerType.expense, loan: 'l')).loans, isEmpty);
    });

    test('a deleted line, or none, moves nothing', () {
      expect(effectsOf(line(LedgerType.expense, deleted: true)).isEmpty, true);
      expect(effectsOf(null).isEmpty, true);
    });
  });

  group('effectDelta', () {
    test('an edit applies only the difference', () {
      final before = line(LedgerType.expense);
      final after = line(LedgerType.expense, amount: 150);
      expect(effectDelta(before, after).accounts, {'a': -50});
    });

    test('moving an entry to another account moves its effect', () {
      final before = line(LedgerType.expense);
      final after = line(LedgerType.expense, account: 'b');
      expect(effectDelta(before, after).accounts, {'a': 100, 'b': -100});
    });

    test('a delete reverses, a restore re-applies', () {
      final live = line(LedgerType.transfer, to: 'b');
      final gone = live.withDeleted(deleted: true);
      expect(effectDelta(live, gone), -effectsOf(live));
      expect(effectDelta(gone, live), effectsOf(live));
    });

    test('no change is empty', () {
      final l = line(LedgerType.income);
      expect(effectDelta(l, l).isEmpty, true);
    });
  });

  test('random edits keep running increments equal to ledgerTotals', () {
    final random = Random(7);
    final accounts = ['a', 'b', 'c'];
    final ledger = <int, LedgerLine>{};
    var running = BalanceEffects.none;
    LedgerLine randomLine() {
      final type = LedgerType.values[random.nextInt(LedgerType.values.length)];
      final account = accounts[random.nextInt(3)];
      final to = type == LedgerType.transfer
          ? accounts.where((x) => x != account).elementAt(random.nextInt(2))
          : null;
      return line(
        type,
        amount: 1 + random.nextInt(5000),
        account: account,
        to: to,
        toAmount: to != null && random.nextBool()
            ? 1 + random.nextInt(9)
            : null,
        sign: random.nextBool() ? 1 : -1,
        loan: random.nextBool() ? 'loan${random.nextInt(2)}' : null,
      );
    }

    for (var step = 0; step < 500; step++) {
      final id = random.nextInt(40);
      final before = ledger[id];
      final LedgerLine after;
      if (before != null && random.nextInt(4) == 0) {
        after = before.withDeleted(deleted: !before.deleted);
      } else {
        after = randomLine();
      }
      running = running + effectDelta(before, after);
      ledger[id] = after;
      expect(running, ledgerTotals(ledger.values), reason: 'step $step');
    }
  });

  group('LedgerLine.fromFields', () {
    test('reads a stored transfer', () {
      final read = LedgerLine.fromFields({
        'type': 'transfer',
        'amountMinor': 10000,
        'accountId': 'usd',
        'toAccountId': 'iqd',
        'toAmountMinor': 170500,
        'deletedAt': null,
      });
      expect(
        read,
        line(
          LedgerType.transfer,
          amount: 10000,
          account: 'usd',
          to: 'iqd',
          toAmount: 170500,
        ),
      );
    });

    test('reads an adjustment sign and a loan', () {
      final read = LedgerLine.fromFields({
        'type': 'adjustment',
        'amountMinor': 5,
        'accountId': 'a',
        'adjustmentSign': -1,
        'loanId': 'l',
      })!;
      expect(read.adjustmentSign, -1);
      expect(read.loanId, 'l');
    });

    test('any deletedAt value counts as deleted', () {
      final read = LedgerLine.fromFields({
        'type': 'expense',
        'amountMinor': 5,
        'accountId': 'a',
        'deletedAt': DateTime.utc(2026),
      })!;
      expect(read.deleted, true);
    });

    test('rejects malformed transactions', () {
      expect(LedgerLine.fromFields({'type': 'gift'}), isNull);
      expect(
        LedgerLine.fromFields({
          'type': 'expense',
          'amountMinor': 0,
          'accountId': 'a',
        }),
        isNull,
      );
      expect(
        LedgerLine.fromFields({'type': 'expense', 'amountMinor': 5}),
        isNull,
      );
    });
  });

  test('uuidV7 sets version and variant and sorts by time', () {
    final random = Random(1);
    final a = uuidV7(DateTime.utc(2026, 11, 23), random);
    final b = uuidV7(DateTime.utc(2026, 11, 24), random);
    expect(
      a,
      matches(
        RegExp(
          '^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-'
          r'[0-9a-f]{12}$',
        ),
      ),
    );
    expect(a.compareTo(b), lessThan(0));
  });
}
