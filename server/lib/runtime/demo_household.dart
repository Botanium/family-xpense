/// A fictional two-member household for local runs and tests.
///
/// Used by the throwaway `tryCapture` and `tryQuestion` flows when the
/// server runs with `XPENSE_AGENT_DATA=demo` (no Firestore emulator), and by
/// the unit tests. Dates are relative to `today`, so "this month" always has
/// data. One account and its transactions are private to the partner, so
/// every query also exercises `visibleTo`.
library;

import 'package:xpense_agent/tools/household_reader.dart';
import 'package:xpense_agent/tools/in_memory_reader.dart';
import 'package:xpense_agent/tools/local_day.dart';
import 'package:xpense_shared/xpense_shared.dart';

/// The demo household id.
const demoHid = 'hh_demo';

/// The member the try flows act as.
const demoUid = 'u_dara';

/// The partner.
const demoPartnerUid = 'u_shilan';

/// The demo context map, as the context provider would return it.
const demoContext = <String, dynamic>{
  'uid': demoUid,
  'hid': demoHid,
  'locale': 'en',
  'privacyMode': 'smart',
  'tz': 'Asia/Baghdad',
};

/// Builds the demo household with dates around [today] (`YYYY-MM-DD`).
InMemoryHousehold demoHousehold(String today) {
  const both = [demoUid, demoPartnerUid];
  const daraOnly = [demoUid];
  const shilanOnly = [demoPartnerUid];
  final month = today.substring(0, 8);
  String day(int d) => '$month${d.toString().padLeft(2, '0')}';
  final todayDay = int.parse(today.substring(8));
  // Days of this month up to today, spread out.
  String early(int d) => day(d.clamp(1, todayDay));
  final lastMonth = isoDay(
    parseIsoDay('${month}01')!.subtract(const Duration(days: 1)),
  ).substring(0, 8);

  var n = 0;
  Visible<LedgerTxn> t(
    String type,
    int amount,
    String on,
    String title, {
    String accountId = 'acc_chk',
    String currency = 'USD',
    int? base,
    String? categoryId,
    String whoScope = 'member',
    String? whoUid = demoUid,
    List<String> visibleTo = both,
    String? toAccountId,
  }) => (
    item: LedgerTxn(
      id: 'txn_${++n}',
      type: type,
      amountMinor: amount,
      currency: currency,
      baseAmountMinor: base ?? amount,
      accountId: accountId,
      toAccountId: toAccountId,
      occurredOn: on,
      title: title,
      categoryId: categoryId,
      whoScope: whoScope,
      whoUid: whoScope == 'joint' ? null : whoUid,
    ),
    visibleTo: visibleTo,
  );

  return InMemoryHousehold(
    profile: const HouseholdProfile(
      hid: demoHid,
      baseCurrency: 'USD',
      memberIds: both,
    ),
    members: const [
      HouseholdMember(uid: demoUid, displayName: 'Dara', role: 'owner'),
      HouseholdMember(
        uid: demoPartnerUid,
        displayName: 'Shilan',
        role: 'partner',
      ),
    ],
    accounts: const [
      (
        item: HouseholdAccount(
          id: 'acc_chk',
          name: 'Checking',
          kind: 'bank',
          currency: 'USD',
          scope: 'joint',
          balanceMinor: 412050,
        ),
        visibleTo: both,
      ),
      (
        item: HouseholdAccount(
          id: 'acc_visa',
          name: 'Joint Visa ••4021',
          kind: 'credit',
          currency: 'USD',
          scope: 'joint',
          balanceMinor: -38640,
          order: 1,
        ),
        visibleTo: both,
      ),
      (
        item: HouseholdAccount(
          id: 'acc_cash_iqd',
          name: 'Cash wallet',
          currency: 'IQD',
          scope: 'personal',
          ownerUid: demoUid,
          balanceMinor: 185000,
          order: 2,
        ),
        visibleTo: daraOnly,
      ),
      (
        item: HouseholdAccount(
          id: 'acc_shilan_savings',
          name: 'Shilan savings',
          kind: 'savings',
          currency: 'USD',
          scope: 'personal',
          ownerUid: demoPartnerUid,
          balanceMinor: 900000,
          order: 3,
        ),
        visibleTo: shilanOnly,
      ),
    ],
    categories: [
      for (final c in defaultCategories)
        HouseholdCategory(
          id: c.slug,
          slug: c.slug,
          name: c.nameIn('en'),
          kind: c.kind.wire,
          parentId: c.parentSlug,
        ),
    ],
    people: const [
      (item: HouseholdPerson(id: 'p_alex', name: 'Alex'), visibleTo: both),
    ],
    loans: const [
      (
        item: HouseholdLoan(
          id: 'loan_alex',
          direction: 'given',
          personId: 'p_alex',
          principalMinor: 30000,
          outstandingMinor: 20000,
          currency: 'USD',
          status: 'open',
        ),
        visibleTo: both,
      ),
    ],
    budgets: const [
      (
        item: HouseholdBudget(
          id: 'b_food',
          categoryId: 'food',
          limitMinor: 60000,
        ),
        visibleTo: both,
      ),
    ],
    transactions: [
      t('income', 320000, early(1), 'Salary', categoryId: 'salary'),
      t(
        'expense',
        140000,
        early(1),
        'Rent',
        // D-41 removed the `rent` category; the household files it here.
        categoryId: 'other_expense',
        whoScope: 'joint',
      ),
      t(
        'expense',
        12850,
        early(2),
        'Carrefour',
        categoryId: 'groceries',
        accountId: 'acc_visa',
        whoScope: 'joint',
      ),
      t(
        'expense',
        25000,
        early(3),
        'Bakery and tea',
        categoryId: 'bakery_tea',
        accountId: 'acc_cash_iqd',
        currency: 'IQD',
        base: 1645,
        visibleTo: daraOnly,
      ),
      t(
        'expense',
        9600,
        early(4),
        'Lunch at Abu Afif',
        categoryId: 'dining',
        accountId: 'acc_visa',
      ),
      t(
        'expense',
        8420,
        early(5),
        'Carrefour',
        categoryId: 'groceries',
        accountId: 'acc_visa',
        whoScope: 'joint',
      ),
      t(
        'expense',
        6000,
        early(6),
        'Fuel',
        categoryId: 'fuel',
        whoUid: demoPartnerUid,
      ),
      t(
        'expense',
        30000,
        early(4),
        'Private gift',
        categoryId: 'gifts',
        accountId: 'acc_shilan_savings',
        whoUid: demoPartnerUid,
        visibleTo: shilanOnly,
      ),
      t(
        'expense',
        11200,
        '${lastMonth}12',
        'Carrefour',
        categoryId: 'groceries',
        accountId: 'acc_visa',
        whoScope: 'joint',
      ),
    ],
    fxRates: [FxDay(date: early(1), usdIqd: '1520', kind: 'market')],
  );
}

/// A reader holding only the demo household.
InMemoryHouseholdReader demoReader(String today) =>
    InMemoryHouseholdReader({demoHid: demoHousehold(today)});
