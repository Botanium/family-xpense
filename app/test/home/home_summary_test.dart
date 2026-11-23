import 'package:flutter_test/flutter_test.dart';
import 'package:xpense_app/data/accounts_repository.dart';
import 'package:xpense_app/data/accounts_repository_fake.dart';
import 'package:xpense_app/data/transactions_repository.dart';
import 'package:xpense_app/features/home/home_summary.dart';
import 'package:xpense_shared/xpense_shared.dart';

import 'home_test_data.dart';

void main() {
  final month = HomeMonth.of(today);
  final rate = FxRate.forPair(FxPair.usdIqd, '1705').valueOrNull;
  const members = [
    HouseholdMember(uid: you, displayName: 'You'),
    HouseholdMember(uid: sam, displayName: 'Sam'),
  ];
  final visibleAccounts = [
    for (final a in FakeAccountsRepository.sampleAccounts)
      if (a.visibleTo.contains(you)) a,
  ];

  HomeSummary build(
    List<LedgerTransaction> month_, {
    List<LedgerTransaction>? recent,
    List<Account>? accounts,
    List<HouseholdMember> people = members,
    FxRate? fx,
    bool withRate = true,
  }) => buildHomeSummary(
    monthTransactions: month_,
    recentTransactions: recent ?? month_,
    accounts: accounts ?? visibleAccounts,
    members: people,
    viewerUid: you,
    baseCurrency: Currency.usd,
    month: month,
    rate: withRate ? (fx ?? rate) : null,
  );

  group('HomeMonth', () {
    test('names the first day and today as stored', () {
      expect(month.firstDay, '2026-11-01');
      expect(month.today, '2026-11-21');
    });

    test('places a stored day in the month, up to today', () {
      expect(month.dayOf('2026-11-01'), 1);
      expect(month.dayOf('2026-11-21'), 21);
      expect(month.dayOf('2026-11-22'), isNull, reason: 'after today');
      expect(month.dayOf('2026-10-21'), isNull, reason: 'another month');
      expect(month.dayOf('2025-11-21'), isNull, reason: 'another year');
      expect(month.dayOf(''), isNull);
    });
  });

  group('month totals', () {
    test('the artboard month: income, spent, saved and the net', () {
      final s = build(artboardMonth());
      expect(s.incomeMinor, 565000);
      expect(s.spentMinor, 441000);
      expect(s.savedMinor, 65000);
      expect(s.netMinor, 124000);
      expect(s.dailyAverageMinor, 21000);
    });

    test('sums the stored base amount, never the entry amount', () {
      // IQD 10,000 saved at 5.87 dollars; today's rate would give 5.86.
      final s = build([
        txn(
          type: LedgerType.expense,
          cents: 10000,
          baseCents: 587,
          currency: Currency.iqd,
          account: 'acc-cash',
        ),
      ]);
      expect(s.spentMinor, 587);
      expect(s.dailySpentMinor.first, 587);
    });

    test("leaves out a partner's private entry even if it is passed in", () {
      final s = build([
        txn(type: LedgerType.expense, cents: 1000),
        txn(
          type: LedgerType.expense,
          cents: 50000,
          visibleTo: const [sam],
          who: sam,
        ),
        txn(
          type: LedgerType.income,
          cents: 70000,
          visibleTo: const [sam],
          who: sam,
        ),
      ]);
      expect(s.spentMinor, 1000);
      expect(s.incomeMinor, 0);
      expect(s.recent, hasLength(1));
    });

    test('leaves out deleted entries, other months and later days', () {
      final s = build([
        txn(type: LedgerType.expense, cents: 1000, day: 3),
        txn(
          type: LedgerType.expense,
          cents: 2000,
          day: 3,
          deletedAt: DateTime.utc(2026, 11, 4),
        ),
        txn(type: LedgerType.expense, cents: 4000, day: 30, month: 10),
        txn(type: LedgerType.expense, cents: 8000, day: 25),
      ]);
      expect(s.spentMinor, 1000);
    });

    test('counts an entry passed twice once', () {
      final t = txn(type: LedgerType.expense, cents: 1000);
      final s = build([t, t]);
      expect(s.spentMinor, 1000);
    });

    test('saved is moves to goals; other transfers, loans and adjustments '
        'are not income, spending or saving', () {
      final s = build([
        txn(
          type: LedgerType.transfer,
          cents: 5000,
          toAccount: 'acc-trip',
          goalId: 'goal-trip',
        ),
        txn(type: LedgerType.transfer, cents: 7000, toAccount: 'acc-cash'),
        txn(type: LedgerType.loanGiven, cents: 9000),
        txn(type: LedgerType.loanTaken, cents: 9000),
        txn(type: LedgerType.repaymentMade, cents: 9000),
        txn(type: LedgerType.repaymentReceived, cents: 9000),
        txn(type: LedgerType.adjustment, cents: 9000, adjustmentSign: -1),
      ]);
      expect(s.savedMinor, 5000);
      expect(s.incomeMinor, 0);
      expect(s.spentMinor, 0);
    });

    test('a month that spent more than it earned has a negative net', () {
      final s = build([
        txn(type: LedgerType.income, cents: 1000),
        txn(type: LedgerType.expense, cents: 2500),
      ]);
      expect(s.netMinor, -1500);
    });
  });

  group('daily bars', () {
    test('one bar per day from the 1st to today, spending only', () {
      final s = build(artboardMonth());
      expect(s.dailySpentMinor, hasLength(21));
      expect(s.dailySpentMinor.first, 18 * 790);
      expect(s.dailySpentMinor[4], 22 * 790, reason: 'IQD lunch included');
      expect(s.dailySpentMinor.last, 62 * 790 + 180);
      expect(s.dailySpentMinor.fold<int>(0, (a, b) => a + b), s.spentMinor);
    });

    test('the busiest day is the latest of the highest', () {
      expect(build(artboardMonth()).busiestDay, 21);
      final tie = build([
        txn(type: LedgerType.expense, cents: 500, day: 4),
        txn(type: LedgerType.expense, cents: 500, day: 9),
      ]);
      expect(tie.busiestDay, 9);
      expect(build(const []).busiestDay, isNull);
    });

    test('the average rounds half up to whole dollars', () {
      // 21 days: 10.50 a day rounds to 11; 10.49 to 10.
      expect(
        build([txn(type: LedgerType.expense, cents: 22050)]).dailyAverageMinor,
        1100,
      );
      expect(
        build([txn(type: LedgerType.expense, cents: 22029)]).dailyAverageMinor,
        1000,
      );
      expect(build(const []).dailyAverageMinor, 0);
    });
  });

  group('balance', () {
    test('sums the visible accounts at the latest rate: 12,480.00', () {
      final s = build(const []);
      expect(s.balanceMinor, 1248000);
      expect(s.balanceComplete, isTrue);
      expect(s.unconverted, isEmpty);
    });

    test('shows the balance in the other currency of the rate', () {
      final s = build(const []);
      expect(s.otherCurrency, Currency.iqd);
      // 12,480 × 1,705.
      expect(s.otherBalanceMinor, 21278400);
    });

    test('without a rate, dinar accounts are named, not guessed', () {
      final s = build(const [], withRate: false);
      expect(s.balanceMinor, 1248000 - 18500);
      expect(s.unconverted, {Currency.iqd});
      expect(s.otherCurrency, isNull);
      expect(s.otherBalanceMinor, isNull);
    });

    test('archived accounts are left out', () {
      final archived = <Account>[
        for (final a in visibleAccounts)
          if (a.id == 'acc-trip')
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
      expect(
        build(const [], accounts: archived).balanceMinor,
        1248000 - 115200,
      );
    });

    test('a partner with private accounts makes it "Your view"', () {
      final s = build(
        const [],
        people: const [
          HouseholdMember(uid: you, displayName: 'You'),
          HouseholdMember(
            uid: sam,
            displayName: 'Sam',
            hasPrivateAccounts: true,
          ),
        ],
      );
      expect(s.balanceComplete, isFalse);
    });
  });

  group('recent', () {
    test('the latest four, newest first, with whose and which way', () {
      final s = build(artboardMonth());
      expect(
        [for (final r in s.recent) r.title],
        ['Costco', 'Salary', 'Shell', 'Lunch'],
      );
      final [costco, salary, shell, lunch] = s.recent;
      expect(costco.signedMinor, -4280);
      expect(costco.who, HomeWho.you);
      expect(salary.direction, RecentDirection.inflow);
      expect(salary.signedMinor, 320000);
      expect(shell.who, HomeWho.partner);
      expect(lunch.who, HomeWho.joint);
      expect(s.partnerName, 'Sam');
    });

    test('directions by type', () {
      RecentDirection of(LedgerType type, {int? sign}) =>
          build([txn(type: type, cents: 100, adjustmentSign: sign)])
              .recent
              .single
              .direction;
      expect(of(LedgerType.expense), RecentDirection.outflow);
      expect(of(LedgerType.loanGiven), RecentDirection.outflow);
      expect(of(LedgerType.repaymentMade), RecentDirection.outflow);
      expect(of(LedgerType.income), RecentDirection.inflow);
      expect(of(LedgerType.loanTaken), RecentDirection.inflow);
      expect(of(LedgerType.repaymentReceived), RecentDirection.inflow);
      expect(of(LedgerType.transfer), RecentDirection.move);
      expect(of(LedgerType.adjustment, sign: -1), RecentDirection.outflow);
      expect(of(LedgerType.adjustment, sign: 1), RecentDirection.inflow);
    });

    test('a move to a goal is marked as savings', () {
      final s = build([
        txn(type: LedgerType.transfer, cents: 100, goalId: 'g'),
        txn(type: LedgerType.transfer, cents: 100, hour: 10),
      ]);
      expect([for (final r in s.recent) r.savings], [false, true]);
    });

    test('Recent is not limited to this month', () {
      final last = txn(
        type: LedgerType.expense,
        cents: 100,
        month: 10,
        day: 30,
        title: 'October',
      );
      final s = build(const [], recent: [last]);
      expect(s.recent.single.title, 'October');
      expect(s.spentMinor, 0);
    });
  });
}
