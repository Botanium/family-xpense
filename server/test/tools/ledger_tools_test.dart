import 'package:genkit/genkit.dart';
import 'package:test/test.dart';
import 'package:xpense_agent/runtime/demo_household.dart';
import 'package:xpense_agent/tools/household_reader.dart';
import 'package:xpense_agent/tools/ledger_tools.dart';
import 'package:xpense_agent/tools/schemas.dart';
import 'package:xpense_agent/tools/xpense_tools.dart';

import 'support.dart';

void main() {
  group('queryLedger', () {
    test(
      'food this month, by category, from what the member can see',
      () async {
        final r = await queryLedger(
          LedgerQuery(categories: ['food'], groupBy: 'category'),
          dara,
          demoDeps(),
        );
        expect(r.from, '2026-11-01');
        expect(r.to, '2026-11-22');
        expect(r.currency, 'USD');
        // 128.50 + 84.20 groceries, 96.00 dining, 25,000 IQD bakery (16.45).
        expect(r.totalMinor, 12850 + 8420 + 9600 + 1645);
        expect(r.count, 4);
        expect(r.rows.map((x) => x.key), ['groceries', 'dining', 'bakery_tea']);
        expect(r.rows.first.amountMinor, 21270);
        expect(r.rows.first.label, 'Groceries');
        expect(r.rows.first.share, 0.65);
      },
    );

    test("the partner's private entries stay private", () async {
      final mine = await queryLedger(
        LedgerQuery(categories: ['gifts']),
        dara,
        demoDeps(),
      );
      expect(mine.count, 0);
      final hers = await queryLedger(
        LedgerQuery(categories: ['gifts']),
        shilan,
        demoDeps(),
      );
      expect(hers.totalMinor, 30000);
      // The partner also cannot see Dara's personal cash wallet.
      final bakery = await queryLedger(
        LedgerQuery(categories: ['bakery_tea']),
        shilan,
        demoDeps(),
      );
      expect(bakery.count, 0);
    });

    test('who, types and text filters', () async {
      final joint = await queryLedger(
        LedgerQuery(who: 'joint'),
        dara,
        demoDeps(),
      );
      expect(joint.count, 3); // rent and two Carrefour trips
      final partner = await queryLedger(
        LedgerQuery(who: 'partner'),
        dara,
        demoDeps(),
      );
      expect(partner.totalMinor, 6000); // fuel
      final income = await queryLedger(
        LedgerQuery(types: ['income']),
        dara,
        demoDeps(),
      );
      expect(income.totalMinor, 320000);
      final carrefour = await queryLedger(
        LedgerQuery(text: 'carrefour', from: '2026-10-01'),
        dara,
        demoDeps(),
      );
      expect(carrefour.count, 3);
    });

    test('daily series, count and average', () async {
      final daily = await queryLedger(
        LedgerQuery(groupBy: 'day', from: '2026-11-01', to: '2026-11-07'),
        dara,
        demoDeps(),
      );
      expect(daily.daily, hasLength(7));
      expect(daily.daily!.first, 140000);
      final count = await queryLedger(
        LedgerQuery(metric: 'count'),
        dara,
        demoDeps(),
      );
      expect(count.totalMinor, isNull);
      expect(count.count, 6); // expenses only; the private gift is hidden
      final avg = await queryLedger(
        LedgerQuery(metric: 'avg', categories: ['groceries']),
        dara,
        demoDeps(),
      );
      expect(avg.totalMinor, 10635); // (12850 + 8420) / 2
    });

    test('a reversed range is put in order and capped', () async {
      final r = await queryLedger(
        LedgerQuery(from: '2026-11-22', to: '2020-01-01'),
        dara,
        demoDeps(),
      );
      expect(r.to, '2026-11-22');
      expect(r.from, '2025-10-18');
    });
  });

  test(
    'getBalances converts to the base currency and flags a partial view',
    () async {
      final r = await getBalances(BalancesQuery(), dara, demoDeps());
      expect(r.accounts.map((a) => a.accountId), [
        'acc_chk',
        'acc_visa',
        'acc_cash_iqd',
      ]);
      // 4120.50 − 386.40 + 185,000 IQD at 1520 (121.71).
      expect(r.totalBaseMinor, 412050 - 38640 + 12171);
      expect(r.partialView, isFalse);
      final mine = await getBalances(
        BalancesQuery(scope: 'mine'),
        dara,
        demoDeps(),
      );
      expect(mine.accounts.single.accountId, 'acc_cash_iqd');
    },
  );

  test('getBudgets sums food including sub-categories', () async {
    final r = await getBudgets(BudgetsQuery(), dara, demoDeps());
    final food = r.budgets.single;
    expect(r.month, '2026-11');
    expect(food.label, 'Food');
    expect(food.spentMinor, 32515);
    expect(food.remainingMinor, 60000 - 32515);
  });

  test('findLoans, getFxRate and findEntries', () async {
    final loans = await findLoans(LoansQuery(person: 'alex'), dara, demoDeps());
    expect(loans.loans.single.outstandingMinor, 20000);
    expect(loans.loans.single.personName, 'Alex');

    final fx = await getFxRate(FxRateQuery(), dara, demoDeps());
    expect(fx.rate, '1520');
    expect(fx.asOf, '2026-11-01');

    final found = await findEntries(
      FindEntriesQuery(text: 'carrefour', amount: '84.20'),
      dara,
      demoDeps(),
    );
    expect(found.items.single.amountMinor, 8420);
    expect(found.items.single.subtitle, 'Groceries · Joint Visa ••4021');
  });

  group('tool actions', () {
    test('read the household from the context, never from input', () async {
      final ai = Genkit();
      final reader = demoReader('2026-11-22');
      final tools = defineXpenseTools(ai, demoDeps(reader: reader));
      expect(tools.map((t) => t.name), XpenseToolNames.all);
      final query = tools.firstWhere((t) => t.name == 'queryLedger');
      final out = await query.run(
        LedgerQuery(categories: ['food']),
        context: demoContext,
      );
      final result = out.result as ToolResponseResult<LedgerResult>;
      expect(result.output.count, 4);
      expect(reader.calls, everyElement(endsWith(':$demoHid')));
      await expectLater(
        query.run(LedgerQuery(categories: ['food'])),
        throwsA(
          isA<GenkitException>().having(
            (e) => e.message,
            'message',
            contains('missing_context'),
          ),
        ),
      );
    });

    test('an unreachable backend fails the call instead of guessing', () async {
      final ai = Genkit();
      final reader = demoReader('2026-11-22')..failing.add('transactions');
      final tools = defineXpenseTools(ai, demoDeps(reader: reader));
      final query = tools.firstWhere((t) => t.name == 'queryLedger');
      await expectLater(
        query.run(LedgerQuery(), context: demoContext),
        throwsA(isA<GenkitException>()),
      );
      expect(const HouseholdUnavailable('x').toString(), contains('x'));
    });
  });
}
