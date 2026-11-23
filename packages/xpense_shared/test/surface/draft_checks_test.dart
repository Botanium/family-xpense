import 'package:test/test.dart';
import 'package:xpense_shared/xpense_shared.dart';

const _refs = HouseholdRefs(
  accountCurrencies: {'acc_chk': 'USD', 'acc_cash': 'IQD'},
  categoryIds: {'dining', 'rent', 'salary'},
  personIds: {'p_alex'},
  loanIds: {'loan_7'},
  goalIds: {'goal_2'},
);

Map<String, Object?> _ok([Map<String, Object?> overrides = const {}]) => {
  'id': 'd1',
  'intent': 'expense',
  'amountMinor': 10000,
  'currency': 'IQD',
  'accountId': 'acc_cash',
  'categoryId': 'dining',
  'occurredOn': '2026-11-22',
  ...overrides,
};

void main() {
  test('a complete draft can be saved', () {
    final check = checkDraft(_ok(), _refs);
    expect(check.issues, isEmpty);
    expect(check.canSave, isTrue);
    expect(check.draft!.amountMinor, 10000);
  });

  test('explicit nulls are tolerated as empty', () {
    final check = checkDraft(_ok({'note': null, 'fx': null}), _refs);
    expect(check.canSave, isTrue);
  });

  group('shape (malformed drafts need the manual form)', () {
    final cases = <String, Object?>{
      'not a map': 'd1',
      'unknown intent': _ok({'intent': 'gift'}),
      'text amount': _ok({'amountMinor': 'ten'}),
      'fractional amount': _ok({'amountMinor': 10.5}),
      'unknown currency': _ok({'currency': 'EUR'}),
      'bad date': _ok({'occurredOn': '22/11/2026'}),
      'bad who': _ok({'who': 'kids'}),
      'guessed not strings': _ok({
        'guessed': [1],
      }),
      'fx without a rate': _ok({
        'fx': {'pair': 'USD/IQD'},
      }),
      'empty id': _ok({'id': ''}),
      // Nested values the generated getters would cast and throw on.
      'confidence as words': _ok({
        'confidence': {'intent': 'high'},
      }),
      'confidence above 1': _ok({
        'confidence': {'category': 1.5},
      }),
      'recurring probability as words': _ok({
        'recurring': {'probability': 'likely'},
      }),
      'recurring day out of range': _ok({
        'recurring': {'dayOfMonth': 32},
      }),
      'recurring unit unknown': _ok({
        'recurring': {'unit': 'year'},
      }),
      'fx base amount as text': _ok({
        'fx': {'pair': 'USD/IQD', 'pairRate': '1705', 'baseAmountMinor': '5'},
      }),
      'duplicate probability as words': _ok({
        'duplicate': {'txnId': 't_1', 'probability': 'maybe'},
      }),
    };
    for (final MapEntry(key: name, value: raw) in cases.entries) {
      test(name, () {
        final check = checkDraft(raw, _refs);
        expect(check.isMalformed, isTrue);
        expect(check.canSave, isFalse);
        expect(check.issues, everyElement(isA<MalformedField>()));
      });
    }

    test('well-formed nested values pass, and their getters read', () {
      final check = checkDraft(
        _ok({
          'confidence': {'intent': 0.9, 'category': 1, 'who': null},
          'recurring': {
            'probability': 0.92,
            'unit': 'month',
            'interval': 1.0,
            'dayOfMonth': 5,
          },
          'fx': {'pair': 'USD/IQD', 'pairRate': '1705', 'baseAmountMinor': 587},
          'duplicate': {'txnId': 't_1', 'probability': 0.8},
        }),
        _refs,
      );
      expect(check.canSave, isTrue);
      expect(check.draft!.confidence!.category, 1.0);
      expect(check.draft!.recurring!.interval, 1);
    });

    test('an amount encoded as 1250.0 is an integer', () {
      expect(checkDraft(_ok({'amountMinor': 1250.0}), _refs).canSave, isTrue);
    });
  });

  group('missing fields', () {
    test('listed fields come first, then empty required ones', () {
      final check = checkDraft(
        _ok({
          'accountId': null,
          'categoryId': null,
          'missing': ['accountId'],
        }),
        _refs,
      );
      expect(check.missing, ['accountId', 'categoryId']);
      expect(check.canSave, isFalse);
    });

    test('a listed field stays missing even with a provisional value', () {
      // The intent question: "loan_given" is a guess until answered.
      final check = checkDraft(
        _ok({
          'intent': 'loan_given',
          'categoryId': null,
          'personName': 'Alex',
          'missing': ['intent'],
        }),
        _refs,
      );
      expect(check.missing, ['intent']);
    });

    test('each intent requires its own fields', () {
      List<String> missing(Map<String, Object?> o) =>
          checkDraft(_ok({'categoryId': null, ...o}), _refs).missing;
      expect(missing({'intent': 'expense'}), ['categoryId']);
      expect(missing({'intent': 'transfer'}), ['toAccountId']);
      expect(missing({'intent': 'savings_move'}), ['toAccountId']);
      expect(missing({'intent': 'savings_move', 'goalId': 'goal_2'}), isEmpty);
      expect(missing({'intent': 'loan_given'}), ['personName']);
      expect(missing({'intent': 'loan_given', 'personId': 'p_alex'}), isEmpty);
      expect(missing({'intent': 'adjustment'}), isEmpty);
    });
  });

  group('household references', () {
    test('unknown ids are reported by field', () {
      final check = checkDraft(
        _ok({'accountId': 'acc_x', 'categoryId': 'cat_x', 'loanId': 'l_x'}),
        _refs,
      );
      expect(check.issues.map((i) => i.field), [
        'accountId',
        'categoryId',
        'loanId',
      ]);
      expect(check.issues.first, isA<UnknownReference>());
    });

    test('amount must be within 1 … 10^12', () {
      expect(
        checkDraft(_ok({'amountMinor': 0}), _refs).issues.single,
        isA<DraftAmountOutOfRange>(),
      );
      expect(
        checkDraft(
          _ok({'amountMinor': maxDraftAmountMinor + 1}),
          _refs,
        ).issues.single,
        isA<DraftAmountOutOfRange>(),
      );
      expect(
        checkDraft(_ok({'amountMinor': maxDraftAmountMinor}), _refs).canSave,
        isTrue,
      );
    });

    test("currency must match the account's", () {
      final issue = checkDraft(_ok({'currency': 'USD'}), _refs).issues.single;
      expect(issue, isA<CurrencyMismatch>());
      expect((issue as CurrencyMismatch).accountCurrency, 'IQD');
    });
  });

  test('a surface with more than 20 drafts cannot be saved', () {
    final ok = checkDrafts([
      for (var i = 0; i < 20; i++) _ok({'id': 'd$i'}),
    ], _refs);
    expect(ok.canSave, isTrue);
    final tooMany = checkDrafts([
      for (var i = 0; i < 21; i++) _ok({'id': 'd$i'}),
    ], _refs);
    expect(tooMany.tooMany, isTrue);
    expect(tooMany.canSave, isFalse);
    expect(checkDrafts(null, _refs).canSave, isFalse);
  });

  // PR #30 review: an account picked on the phone settles a guessed
  // currency; the amount keeps the major units the member wrote.
  // PR #30 review: a transfer never goes to its own account.
  test('a transfer to its own source account cannot be saved', () {
    const refs = HouseholdRefs(
      accountCurrencies: {'acc_chk': 'USD', 'acc_sav': 'USD'},
    );
    Map<String, Object?> transfer(String to) => {
      'id': 'd1',
      'intent': 'transfer',
      'amountMinor': 10000,
      'currency': 'USD',
      'accountId': 'acc_chk',
      'toAccountId': to,
      'occurredOn': '2026-11-22',
    };
    final same = checkDraft(transfer('acc_chk'), refs);
    expect(same.canSave, isFalse);
    expect(same.missing, ['toAccountId']);
    expect(checkDraft(transfer('acc_sav'), refs).canSave, isTrue);
  });

  group('followAccountCurrency', () {
    const guessed = <String, Object?>{
      'id': 'd1',
      'intent': 'expense',
      'amountMinor': 4500,
      'currency': 'USD',
      'accountId': 'acc_cash',
      'guessed': ['accountId', 'currency'],
    };
    const cash = HouseholdRefs(accountCurrencies: {'acc_cash': 'IQD'});

    test('a guessed currency follows the account', () {
      final next = followAccountCurrency(guessed, 'IQD');
      expect(next['currency'], 'IQD');
      expect(next['amountMinor'], 45);
      expect(next['guessed'], ['accountId', 'currency']);
      expect(
        checkDraft(next, cash).issues.whereType<CurrencyMismatch>(),
        isEmpty,
      );
      expect(
        followAccountCurrency({
          ...guessed,
          'amountMinor': 2500000,
        }, 'IQD')['amountMinor'],
        25000,
      );
    });

    test('an amount the account currency cannot hold is asked again', () {
      final next = followAccountCurrency({
        ...guessed,
        'amountMinor': 1250,
        'guessed': ['currency'],
      }, 'IQD');
      expect(next['currency'], 'IQD');
      expect(next.containsKey('amountMinor'), isFalse);
      expect(next['guessed'], ['currency']);
      expect(checkDraft(next, cash).missing, contains('amountMinor'));
    });

    // PR #30 review: the member changes their pick, and back again.
    test('a currency that followed an account follows later picks', () {
      const refs = HouseholdRefs(
        accountCurrencies: {'acc_cash': 'IQD', 'acc_chk': 'USD'},
      );
      var d = followAccountCurrency(guessed, 'IQD');
      for (final (account, currency, amount) in [
        ('acc_chk', 'USD', 4500),
        ('acc_cash', 'IQD', 45),
      ]) {
        d = followAccountCurrency({...d, 'accountId': account}, currency);
        expect((d['currency'], d['amountMinor']), (currency, amount));
        expect(
          checkDraft(d, refs).issues.whereType<CurrencyMismatch>(),
          isEmpty,
        );
      }
    });

    test('dinars to dollars keep the written figure', () {
      final next = followAccountCurrency({
        ...guessed,
        'amountMinor': 25000,
        'currency': 'IQD',
      }, 'USD');
      expect((next['amountMinor'], next['currency']), (2500000, 'USD'));
    });

    test('a written currency, the same currency or no account stays', () {
      final written = <String, Object?>{
        ...guessed,
        'guessed': ['accountId'],
      };
      expect(followAccountCurrency(written, 'IQD'), same(written));
      expect(followAccountCurrency(guessed, 'USD'), same(guessed));
      expect(followAccountCurrency(guessed, null), same(guessed));
    });
  });
}
