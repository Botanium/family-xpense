import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xpense_app/data/accounts_repository.dart';
import 'package:xpense_app/data/accounts_repository_fake.dart';
import 'package:xpense_app/data/accounts_repository_firebase.dart';
import 'package:xpense_app/data/fx_repository_firebase.dart';
import 'package:xpense_app/features/accounts/account_form.dart';
import 'package:xpense_app/features/accounts/accounts_overview.dart';
import 'package:xpense_shared/xpense_shared.dart';

const String me = FakeAccountsRepository.sampleViewer;
const String sam = FakeAccountsRepository.samplePartner;

final FxRate rate = FxRate.forPair(FxPair.usdIqd, '1705').valueOrNull!;

List<Account> visibleTo(String uid) => [
  for (final a in FakeAccountsRepository.sampleAccounts)
    if (a.visibleTo.contains(uid)) a,
];

const members = [
  HouseholdMember(uid: me, displayName: 'You', hasPrivateAccounts: true),
  HouseholdMember(uid: sam, displayName: 'Sam', hasPrivateAccounts: true),
];

void main() {
  group('buildOverview', () {
    test('sums what the viewer sees in the base currency (artboard 10)', () {
      final overview = buildOverview(
        accounts: visibleTo(me),
        members: members,
        viewerUid: me,
        baseCurrency: Currency.usd,
        rate: rate,
      );
      // 3,940 + 2,615 − 612 + (315,425 IQD ≈ 185.00) + 5,200 + 1,152.
      expect(overview.totalMinor, 1248000);
      expect(overview.unconverted, isEmpty);
      final cash = overview.rows.singleWhere((r) => r.account.id == 'acc-cash');
      expect(cash.baseMinor, 18500);
      // Sam keeps an account private, so this is "Your view".
      expect(overview.complete, isFalse);
      expect(overview.partnerName, 'Sam');
      expect(
        overview.rows.map((r) => r.account.id),
        isNot(contains('acc-sam-private')),
      );
    });

    test("the filters split mine, the partner's and joint", () {
      final overview = buildOverview(
        accounts: visibleTo(me),
        members: members,
        viewerUid: me,
        baseCurrency: Currency.usd,
        rate: rate,
      );
      List<String> ids(AccountsFilter f) =>
          overview.filtered(f).map((r) => r.account.id).toList();
      expect(ids(AccountsFilter.mine), ['acc-checking', 'acc-cash']);
      expect(ids(AccountsFilter.partner), ['acc-sam-checking']);
      expect(ids(AccountsFilter.joint), [
        'acc-visa',
        'acc-emergency',
        'acc-trip',
      ]);
      expect(ids(AccountsFilter.all), hasLength(6));
    });

    test('the partner sees nothing of my private account', () {
      final overview = buildOverview(
        accounts: visibleTo(sam),
        members: members,
        viewerUid: sam,
        baseCurrency: Currency.usd,
        rate: rate,
      );
      expect(
        overview.rows.map((r) => r.account.id),
        isNot(contains('acc-checking')),
      );
      // Everything Sam sees: their own private savings too, not my checking.
      expect(overview.totalMinor, 1248000 - 394000 + 900000);
      expect(overview.complete, isFalse);
      final cash = overview.rows.singleWhere((r) => r.account.id == 'acc-cash');
      expect(cash.owner, AccountOwner.partner);
    });

    test('"Household balance" when nobody keeps anything private', () {
      final overview = buildOverview(
        accounts: visibleTo(me),
        members: const [
          HouseholdMember(
            uid: me,
            displayName: 'You',
            hasPrivateAccounts: true,
          ),
          HouseholdMember(uid: sam, displayName: 'Sam'),
        ],
        viewerUid: me,
        baseCurrency: Currency.usd,
        rate: rate,
      );
      // My own private accounts are in my view, so it is complete.
      expect(overview.complete, isTrue);
    });

    test('without a rate, other currencies stay out of the total', () {
      final overview = buildOverview(
        accounts: visibleTo(me),
        members: members,
        viewerUid: me,
        baseCurrency: Currency.usd,
      );
      expect(overview.totalMinor, 1248000 - 18500);
      expect(overview.unconverted, {Currency.iqd});
    });

    test('archived accounts are in no row and no total', () {
      final accounts = [
        for (final a in visibleTo(me))
          if (a.id == 'acc-visa')
            Account(
              id: a.id,
              name: a.name,
              kind: a.kind,
              currency: a.currency,
              scope: a.scope,
              visibleTo: a.visibleTo,
              balanceMinor: a.balanceMinor,
              archived: true,
            )
          else
            a,
      ];
      final overview = buildOverview(
        accounts: accounts,
        members: members,
        viewerUid: me,
        baseCurrency: Currency.usd,
        rate: rate,
      );
      expect(overview.totalMinor, 1248000 + 61200);
      expect(
        overview.rows.map((r) => r.account.id),
        isNot(contains('acc-visa')),
      );
    });
  });

  group('accountVisibleTo', () {
    test("a private account is its owner's alone", () {
      expect(
        accountVisibleTo(
          scope: AccountScope.personal,
          ownerUid: 'b',
          sharedWithPartner: false,
          memberIds: ['a', 'b'],
        ),
        ['b'],
      );
    });

    test("shared and joint accounts are everyone's, sorted", () {
      expect(
        accountVisibleTo(
          scope: AccountScope.personal,
          ownerUid: 'b',
          sharedWithPartner: true,
          memberIds: ['b', 'a'],
        ),
        ['a', 'b'],
      );
      expect(
        accountVisibleTo(
          scope: AccountScope.joint,
          ownerUid: null,
          sharedWithPartner: false,
          memberIds: ['b', 'a'],
        ),
        ['a', 'b'],
      );
    });
  });

  group('openingBaseAmount', () {
    test('a zero balance needs no rate (Codex review, PR #33)', () {
      expect(
        openingBaseAmount(
          amountMinor: 0,
          currency: Currency.iqd,
          base: Currency.usd,
        ),
        0,
      );
    });

    test('converts a non-zero balance, unsigned, or asks for a rate', () {
      expect(
        openingBaseAmount(
          amountMinor: -250000,
          currency: Currency.iqd,
          base: Currency.usd,
          rate: rate,
        ),
        14663,
      );
      expect(
        openingBaseAmount(
          amountMinor: 250000,
          currency: Currency.iqd,
          base: Currency.usd,
        ),
        isNull,
      );
      expect(
        openingBaseAmount(
          amountMinor: 61200,
          currency: Currency.usd,
          base: Currency.usd,
        ),
        61200,
      );
    });
  });

  group('balanceEffect (DATA_MODEL 3)', () {
    Map<String, Object?> txn(String type, {int sign = 1, String? to}) => {
      'type': type,
      'amountMinor': 500,
      'accountId': 'a',
      'toAccountId': ?to,
      'adjustmentSign': sign,
    };

    test('signs each type on its account', () {
      expect(balanceEffect(txn('expense'), 'a'), -500);
      expect(balanceEffect(txn('income'), 'a'), 500);
      expect(balanceEffect(txn('loan_given'), 'a'), -500);
      expect(balanceEffect(txn('loan_taken'), 'a'), 500);
      expect(balanceEffect(txn('repayment_made'), 'a'), -500);
      expect(balanceEffect(txn('repayment_received'), 'a'), 500);
      expect(balanceEffect(txn('adjustment'), 'a'), 500);
      expect(balanceEffect(txn('adjustment', sign: -1), 'a'), -500);
    });

    test('a transfer leaves one account and arrives in the other', () {
      final t = txn('transfer', to: 'b');
      expect(balanceEffect(t, 'a'), -500);
      expect(balanceEffect(t, 'b'), 500);
      expect(balanceEffect({...t, 'toAmountMinor': 852500}, 'b'), 852500);
      expect(balanceEffect(t, 'c'), 0);
    });
  });

  group('checkAccountForm', () {
    AccountFormCheck check({
      String name = '',
      AccountKind kind = AccountKind.cash,
      Currency currency = Currency.usd,
      String amount = '',
      String rate = '',
      bool needsRate = false,
      AccountScope scope = AccountScope.personal,
      bool shared = false,
    }) => checkAccountForm(
      name: name,
      defaultName: 'Cash',
      kind: kind,
      currency: currency,
      scope: scope,
      shared: shared,
      amountText: amount,
      rateText: rate,
      needsRate: needsRate,
    );

    test('an empty form adds an account named after its kind, at zero', () {
      final draft = check().draft!;
      expect(draft.name, 'Cash');
      expect(draft.openingBalanceMinor, 0);
    });

    test("reads the amount in the currency's decimals", () {
      expect(check(amount: '3,940.50').draft!.openingBalanceMinor, 394050);
      expect(
        check(
          amount: '250,000',
          currency: Currency.iqd,
        ).draft!.openingBalanceMinor,
        250000,
      );
      expect(
        check(amount: '1.5', currency: Currency.iqd).amountInvalid,
        isTrue,
      );
    });

    test("a card's amount is owed, so negative", () {
      expect(
        check(
          amount: '612',
          kind: AccountKind.credit,
        ).draft!.openingBalanceMinor,
        -61200,
      );
    });

    test('the rate is required only when asked, and must read', () {
      expect(
        check(
          amount: '250000',
          currency: Currency.iqd,
          needsRate: true,
        ).rateInvalid,
        isTrue,
      );
      final draft = check(
        amount: '250000',
        currency: Currency.iqd,
        needsRate: true,
        rate: '1,705',
      ).draft!;
      expect(draft.openingRate?.rateString, '1705');
    });

    test('a joint account is never "shared"; names are capped', () {
      expect(
        check(scope: AccountScope.joint, shared: true).draft!.sharedWithPartner,
        isFalse,
      );
      expect(check(name: 'x' * 41).nameTooLong, isTrue);
      expect(check(name: '  Wallet  ').draft!.name, 'Wallet');
    });
  });

  group('reading Firestore documents', () {
    test("an account, with the server's progress", () {
      final account = accountFromFirestore('a1', {
        'name': 'Cash',
        'kind': 'cash',
        'currency': 'IQD',
        'scope': 'personal',
        'ownerUid': 'u',
        'sharedWithPartner': true,
        'visibleTo': ['u', 'p'],
        'balanceMinor': 250000,
        'visibilityAppliedTo': ['u'],
        'visibilitySync': {'done': 18, 'total': 42},
      })!;
      expect(account.currency, Currency.iqd);
      expect(account.sharingInProgress, isTrue);
      expect(account.appliedVisibleTo, ['u']);
      expect(account.sharingDone, 18);
      expect(account.sharingTotal, 42);
    });

    test('an unknown currency makes no account', () {
      expect(accountFromFirestore('a', {'currency': 'EUR'}), isNull);
    });

    test('an entry, signed for the account', () {
      final entry = entryFromFirestore('t', {
        'type': 'adjustment',
        'adjustmentSign': -1,
        'amountMinor': 61200,
        'accountId': 'visa',
        'currency': 'USD',
        'title': '',
        'occurredAt': Timestamp.fromDate(DateTime.utc(2026, 11, 21)),
      }, 'visa')!;
      expect(entry.amountMinor, -61200);
    });

    test("a day's rate", () {
      expect(
        dailyRateFromFirestore('2026-11-22', {
          'usdIqd': '1705',
        })?.rate.rateString,
        '1705',
      );
      expect(dailyRateFromFirestore('2026-11-22', {'usdIqd': 1705}), isNull);
    });
  });
}
