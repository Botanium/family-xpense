import 'package:genkit/genkit.dart';
import 'package:test/test.dart';
import 'package:xpense_agent/runtime/demo_household.dart';
import 'package:xpense_agent/tools/household_reader.dart';
import 'package:xpense_agent/tools/in_memory_reader.dart';
import 'package:xpense_agent/tools/ledger_tools.dart';
import 'package:xpense_agent/tools/prepare_entries.dart';
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
      expect(joint.count, 3); // generator and two Carrefour trips
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

  test('getBalances converts to the base currency', () async {
    final r = await getBalances(BalancesQuery(), dara, demoDeps());
    expect(r.accounts.map((a) => a.accountId), [
      'acc_chk',
      'acc_visa',
      'acc_cash_iqd',
    ]);
    // 4120.50 − 386.40 + 185,000 IQD at 1520 (121.71).
    expect(r.totalBaseMinor, 412050 - 38640 + 12171);
    final mine = await getBalances(
      BalancesQuery(scope: 'mine'),
      dara,
      demoDeps(),
    );
    expect(mine.accounts.single.accountId, 'acc_cash_iqd');
  });

  group('partialView (PR #30 review)', () {
    test('is true when the partner has a private account', () async {
      // Shilan's savings account is private: Dara's total leaves it out.
      // The old check compared two member-filtered lists and said false.
      final r = await getBalances(BalancesQuery(), dara, demoDeps());
      expect(r.partialView, isTrue);
      final q = await queryLedger(LedgerQuery(), dara, demoDeps());
      expect(q.partialView, isTrue);
      final b = await getBudgets(BudgetsQuery(), dara, demoDeps());
      expect(b.partialView, isTrue);
    });

    test('is false when the member sees every account', () async {
      // Every account shared with both members.
      final h = demoHousehold('2026-11-22');
      final shared = InMemoryHousehold(
        profile: h.profile,
        members: h.members,
        categories: h.categories,
        accounts: [
          for (final a in h.accounts)
            (item: a.item, visibleTo: const [demoUid, demoPartnerUid]),
        ],
      );
      final r = await getBalances(
        BalancesQuery(),
        dara,
        demoDeps(reader: InMemoryHouseholdReader({demoHid: shared})),
      );
      expect(r.partialView, isFalse);
    });

    test('an archived private account does not count', () async {
      final h = demoHousehold('2026-11-22');
      final archived = InMemoryHousehold(
        profile: h.profile,
        members: h.members,
        categories: h.categories,
        accounts: [
          for (final a in h.accounts)
            if (a.item.id == 'acc_shilan_savings')
              (
                item: HouseholdAccount(
                  id: a.item.id,
                  name: a.item.name,
                  currency: a.item.currency,
                  scope: a.item.scope,
                  ownerUid: a.item.ownerUid,
                  archived: true,
                ),
                visibleTo: a.visibleTo,
              )
            else if (a.item.id != 'acc_cash_iqd')
              a,
        ],
      );
      final r = await getBalances(
        BalancesQuery(),
        dara,
        demoDeps(reader: InMemoryHouseholdReader({demoHid: archived})),
      );
      expect(r.partialView, isFalse);
    });
  });

  group('budget scope (PR #30 review)', () {
    test('a household budget counts every visible expense', () async {
      final r = await getBudgets(BudgetsQuery(), dara, demoDeps());
      final food = r.budgets.firstWhere((b) => b.budgetId == 'b_food');
      expect(r.month, '2026-11');
      expect(r.complete, isTrue);
      expect(food.label, 'Food');
      expect(food.scope, 'household');
      expect(food.spentMinor, 32515);
      expect(food.remainingMinor, 60000 - 32515);
    });

    test("a personal budget counts only that member's own entries", () async {
      // This month's groceries (128.50 + 84.20) are joint. The old code
      // counted them against Dara's personal budget.
      final r = await getBudgets(BudgetsQuery(), dara, demoDeps());
      final mine = r.budgets.firstWhere(
        (b) => b.budgetId == 'b_dara_groceries',
      );
      expect(mine.scope, 'personal');
      expect(mine.spentMinor, 0);
      expect(mine.remainingMinor, 15000);
      // The partner does not see Dara's personal budget at all.
      final hers = await getBudgets(BudgetsQuery(), shilan, demoDeps());
      expect(hers.budgets.map((b) => b.budgetId), ['b_food']);
    });
  });

  group('archived categories (PR #30 review)', () {
    // Dining out archived after this month's 96.00 lunch was saved.
    InMemoryHouseholdReader archivedDining() {
      final h = demoHousehold('2026-11-22');
      return InMemoryHouseholdReader({
        demoHid: InMemoryHousehold(
          profile: h.profile,
          members: h.members,
          accounts: h.accounts,
          people: h.people,
          budgets: h.budgets,
          transactions: h.transactions,
          fxRates: h.fxRates,
          categories: [
            for (final c in h.categories)
              if (c.slug == 'dining')
                HouseholdCategory(
                  id: c.id,
                  slug: c.slug,
                  name: c.name,
                  kind: c.kind,
                  parentId: c.parentId,
                  archived: true,
                )
              else
                c,
          ],
        ),
      });
    }

    test('past spending in an archived category still counts', () async {
      final deps = demoDeps(reader: archivedDining());
      final food = await queryLedger(
        LedgerQuery(categories: ['food'], groupBy: 'category'),
        dara,
        deps,
      );
      expect(food.totalMinor, 32515);
      expect(
        food.rows.map((r) => r.label),
        containsAll(['Groceries', 'Dining out']),
      );
      final dining = await queryLedger(
        LedgerQuery(categories: ['dining']),
        dara,
        deps,
      );
      expect(dining.totalMinor, 9600);
      final budgets = await getBudgets(BudgetsQuery(), dara, deps);
      expect(
        budgets.budgets.firstWhere((b) => b.budgetId == 'b_food').spentMinor,
        32515,
      );
    });

    test('new entries cannot pick an archived category', () async {
      final out = await prepareEntries(
        PrepareEntriesInput(
          entries: [
            ProposedEntry(
              intent: 'expense',
              amount: '12',
              text: 'dining 12',
              categoryHint: 'dining',
            ),
          ],
        ),
        dara,
        demoDeps(reader: archivedDining(), texts: ['dining 12']),
      );
      expect(out.drafts.single.categoryId, isNull);
    });
  });

  group('truncated reads (PR #30 review)', () {
    // A reader that returns at most 3 transactions per range.
    InMemoryHouseholdReader capped() => InMemoryHouseholdReader({
      demoHid: demoHousehold('2026-11-22'),
    }, maxRangeTransactions: 3);

    test('queryLedger gives no total from a partial read', () async {
      final r = await queryLedger(
        LedgerQuery(categories: ['food'], groupBy: 'category'),
        dara,
        demoDeps(reader: capped()),
      );
      expect(r.complete, isFalse);
      expect(r.totalMinor, isNull);
      expect(r.rows, isEmpty);
      expect(r.daily, isNull);
    });

    test('getBudgets gives no spending from a partial read', () async {
      final r = await getBudgets(
        BudgetsQuery(),
        dara,
        demoDeps(reader: capped()),
      );
      expect(r.complete, isFalse);
      expect(r.budgets.map((b) => b.spentMinor), everyElement(isNull));
      expect(r.budgets.map((b) => b.remainingMinor), everyElement(isNull));
    });

    test('findEntries says its search was partial', () async {
      final r = await findEntries(
        FindEntriesQuery(),
        dara,
        demoDeps(reader: capped()),
      );
      expect(r.complete, isFalse);
    });

    test('a full read is complete', () async {
      final r = await queryLedger(LedgerQuery(), dara, demoDeps());
      expect(r.complete, isTrue);
      expect(r.totalMinor, isNotNull);
    });
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
