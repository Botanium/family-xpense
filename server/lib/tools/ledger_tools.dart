/// The read-only tools: ledger queries, balances, budgets, loans, rates and
/// entry search (AI_PIPELINE 8).
///
/// Every figure the agent states comes from here, so the arithmetic is done
/// here in integer minor units ("do arithmetic with tools, not in prose").
/// Totals across currencies use each transaction's stored
/// `baseAmountMinor`, which was converted once at save time (DATA_MODEL 1).
library;

import 'package:xpense_agent/auth/xpense_context.dart';
import 'package:xpense_agent/tools/household_reader.dart';
import 'package:xpense_agent/tools/household_snapshot.dart';
import 'package:xpense_agent/tools/local_day.dart';
import 'package:xpense_agent/tools/prepare_entries.dart'
    show parseWrittenAmount;
import 'package:xpense_agent/tools/schemas.dart';
import 'package:xpense_agent/tools/tool_deps.dart';
import 'package:xpense_shared/xpense_shared.dart';

/// The longest range `queryLedger` reads, in days.
const maxQueryDays = 400;

Future<HouseholdSnapshot> _snapshot(XpenseContext c, ToolDeps deps) async {
  final snap = await deps.snapshots.get(c.hid, c.uid);
  if (snap == null) throw const HouseholdUnavailable('household_not_found');
  return snap;
}

/// `queryLedger`.
Future<LedgerResult> queryLedger(
  LedgerQuery q,
  XpenseContext c,
  ToolDeps deps,
) async {
  final snap = await _snapshot(c, deps);
  final today = localToday(deps.clock, c.tz).iso;
  var to = parseIsoDay(q.to) != null ? q.to! : today;
  var from = parseIsoDay(q.from) != null
      ? q.from!
      : '${today.substring(0, 8)}01';
  if (from.compareTo(to) > 0) (from, to) = (to, from);
  if (parseIsoDay(to)!.difference(parseIsoDay(from)!).inDays > maxQueryDays) {
    from = addDays(to, -maxQueryDays);
  }

  // Sequential awaits keep a HouseholdUnavailable unwrapped (a record's
  // `.wait` would wrap it in a ParallelWaitError).
  final read = await deps.reader.transactions(
    c.hid,
    uid: c.uid,
    fromOn: from,
    toOn: to,
  );
  final partialView = await deps.reader.hasHiddenAccounts(c.hid, uid: c.uid);
  // Never a total from a partial read: the model is told the range is too
  // large instead (_rules_ui.prompt).
  if (!read.complete) {
    return LedgerResult(
      currency: snap.baseCurrency,
      metric: q.metric ?? 'sum',
      from: from,
      to: to,
      count: read.items.length,
      rows: [],
      complete: false,
      partialView: partialView,
    );
  }
  final txns = read.items;
  final types = q.types?.isNotEmpty ?? false ? q.types!.toSet() : {'expense'};
  final categoryIds = _expandCategories(q.categories, snap);
  final accountIds = q.accountIds?.toSet();
  final text = q.text?.toLowerCase().trim();
  final partnerUid = snap.partner?.uid;

  bool whoMatches(LedgerTxn t) => switch (q.who ?? 'all') {
    'me' => t.whoScope != 'joint' && t.whoUid == c.uid,
    'partner' => t.whoScope != 'joint' && t.whoUid == partnerUid,
    'joint' => t.whoScope == 'joint',
    _ => true,
  };

  final matching = [
    for (final t in txns)
      if (types.contains(t.type) &&
          (categoryIds == null || categoryIds.contains(t.categoryId)) &&
          (accountIds == null ||
              accountIds.contains(t.accountId) ||
              accountIds.contains(t.toAccountId)) &&
          whoMatches(t) &&
          (text == null ||
              text.isEmpty ||
              t.title.toLowerCase().contains(text) ||
              (t.note?.toLowerCase().contains(text) ?? false)))
        t,
  ];

  final metric = q.metric ?? 'sum';
  final groupBy = q.groupBy ?? 'none';
  int? measure(List<LedgerTxn> ts) => switch (metric) {
    'count' => null,
    'avg' => ts.isEmpty ? 0 : _roundHalfEven(_sum(ts), ts.length),
    _ => _sum(ts),
  };

  final groups = <String, List<LedgerTxn>>{};
  String keyOf(LedgerTxn t) => switch (groupBy) {
    'day' => t.occurredOn,
    'week' => _weekStart(t.occurredOn, snap.profile.weekStart),
    'month' => t.occurredOn.substring(0, 7),
    'category' => _groupCategory(t.categoryId, snap, categoryIds),
    'account' => t.accountId,
    'who' =>
      t.whoScope == 'joint' ? 'joint' : (t.whoUid == c.uid ? 'me' : 'partner'),
    _ => 'all',
  };
  for (final t in matching) {
    groups.putIfAbsent(keyOf(t), () => []).add(t);
  }
  final total = measure(matching);
  final sumTotal = _sum(matching);
  final timeGroup = const {'day', 'week', 'month'}.contains(groupBy);
  var rows = [
    for (final MapEntry(:key, :value) in groups.entries)
      LedgerRow(
        key: key,
        label: _label(groupBy, key, snap),
        amountMinor: measure(value),
        count: value.length,
        share: metric == 'sum' && sumTotal > 0
            ? _share(_sum(value), sumTotal)
            : null,
      ),
  ];
  if (timeGroup) {
    rows.sort((a, b) => a.key.compareTo(b.key));
  } else {
    rows.sort(
      (a, b) => (b.amountMinor ?? b.count).compareTo(a.amountMinor ?? a.count),
    );
  }
  final limit = q.limit ?? 12;
  if (rows.length > limit) {
    rows = timeGroup
        ? rows.sublist(rows.length - limit)
        : rows.sublist(0, limit);
  }

  List<int>? daily;
  if (groupBy == 'day') {
    daily = [];
    for (var d = from; d.compareTo(to) <= 0; d = addDays(d, 1)) {
      daily.add(_sum(groups[d] ?? const []));
    }
    if (daily.length > 62) daily = daily.sublist(daily.length - 62);
  }

  return LedgerResult(
    currency: snap.baseCurrency,
    metric: metric,
    from: from,
    to: to,
    totalMinor: total,
    count: matching.length,
    rows: rows,
    daily: daily,
    complete: true,
    partialView: partialView,
  );
}

int _sum(Iterable<LedgerTxn> ts) => ts.fold(0, (s, t) => s + t.baseAmountMinor);

/// Integer division rounded half to even (DATA_MODEL 1).
int _roundHalfEven(int numerator, int denominator) {
  final q = numerator ~/ denominator;
  final r = numerator - q * denominator;
  final twice = 2 * r;
  if (twice < denominator) return q;
  if (twice > denominator) return q + 1;
  return q.isEven ? q : q + 1;
}

/// A share rounded to two decimals, for display only.
double _share(int part, int whole) => (part * 100 / whole).round() / 100;

/// Category filters: slugs or ids; a group includes its sub-categories.
Set<String>? _expandCategories(List<String>? names, HouseholdSnapshot snap) {
  if (names == null || names.isEmpty) return null;
  final out = <String>{};
  for (final name in names) {
    final c = snap.category(name);
    if (c == null) continue;
    out.add(c.id);
    for (final child in snap.categories) {
      if (child.parentId == c.id) out.add(child.id);
    }
  }
  return out;
}

/// The group of a category for `groupBy: category`: the category itself
/// when the query named sub-categories, otherwise its sub-category.
String _groupCategory(
  String? id,
  HouseholdSnapshot snap,
  Set<String>? filter,
) => snap.category(id)?.slug ?? 'uncategorised';

String _label(String groupBy, String key, HouseholdSnapshot snap) =>
    switch (groupBy) {
      'category' => snap.category(key)?.name ?? 'Uncategorised',
      'account' => snap.account(key)?.name ?? 'Private account',
      'who' => switch (key) {
        'me' => snap.me?.displayName ?? 'Me',
        'partner' => snap.partner?.displayName ?? 'Partner',
        _ => 'Joint',
      },
      'none' => 'All',
      _ => key,
    };

String _weekStart(String day, String weekStart) {
  final d = parseIsoDay(day)!;
  final startDow = switch (weekStart) {
    'sun' => DateTime.sunday,
    'mon' => DateTime.monday,
    _ => DateTime.saturday,
  };
  final back = (d.weekday - startDow) % 7;
  return isoDay(d.subtract(Duration(days: back)));
}

/// `getBalances`.
Future<BalancesResult> getBalances(
  BalancesQuery q,
  XpenseContext c,
  ToolDeps deps,
) async {
  final snap = await _snapshot(c, deps);
  final partnerUid = snap.partner?.uid;
  final scope = q.scope ?? 'all';
  final accounts = [
    for (final a in snap.accounts)
      if (switch (scope) {
        'mine' => a.scope == 'personal' && a.ownerUid == c.uid,
        'partner' => a.scope == 'personal' && a.ownerUid == partnerUid,
        'joint' => a.scope == 'joint',
        _ => true,
      })
        a,
  ];
  final base = Currency.tryParse(snap.baseCurrency);
  int? total = 0;
  FxRate? rate;
  final needsRate = accounts.any((a) => a.currency != snap.baseCurrency);
  if (needsRate) {
    final day = await deps.reader.fxRateOn(
      c.hid,
      localToday(deps.clock, c.tz).iso,
    );
    if (day != null) {
      if (FxRate.parse('USD/IQD', day.usdIqd) case Ok(:final value)) {
        rate = value;
      }
    }
  }
  for (final a in accounts) {
    final cur = Currency.tryParse(a.currency);
    if (total == null || cur == null || base == null) {
      total = null;
      continue;
    }
    switch (toBaseAmount(Money(a.balanceMinor, cur), base, rate: rate)) {
      case Ok(:final value):
        total = total + value.minorUnits;
      case Err():
        total = null;
    }
  }
  // Private partner accounts are in neither the snapshot nor the total;
  // ask the reader, which alone sees them, whether any exist.
  final partialView = await deps.reader.hasHiddenAccounts(c.hid, uid: c.uid);
  return BalancesResult(
    baseCurrency: snap.baseCurrency,
    accounts: [
      for (final a in accounts)
        AccountBalance(
          accountId: a.id,
          name: a.name,
          currency: a.currency,
          balanceMinor: a.balanceMinor,
          scope: a.scope,
        ),
    ],
    totalBaseMinor: total,
    partialView: partialView,
  );
}

/// `getBudgets`.
Future<BudgetsResult> getBudgets(
  BudgetsQuery q,
  XpenseContext c,
  ToolDeps deps,
) async {
  final snap = await _snapshot(c, deps);
  final thisMonth = localToday(deps.clock, c.tz).iso.substring(0, 7);
  final month = RegExp(r'^\d{4}-\d{2}$').hasMatch(q.month ?? '')
      ? q.month!
      : thisMonth;
  final first = '$month-01';
  final next = parseIsoDay(first)!;
  final last = isoDay(
    DateTime.utc(next.year, next.month + 1).subtract(const Duration(days: 1)),
  );
  final budgets = await deps.reader.budgets(c.hid, uid: c.uid);
  final read = await deps.reader.transactions(
    c.hid,
    uid: c.uid,
    fromOn: first,
    toOn: last,
  );
  final partialView = await deps.reader.hasHiddenAccounts(c.hid, uid: c.uid);
  final expenses = [
    for (final t in read.items)
      if (t.type == 'expense') t,
  ];
  return BudgetsResult(
    month: month,
    currency: snap.baseCurrency,
    complete: read.complete,
    partialView: partialView,
    budgets: [
      for (final b in budgets)
        () {
          final ids = b.categoryId == 'total'
              ? null
              : _expandCategories([b.categoryId], snap);
          // A personal budget limits one member's own spending: their
          // member entries, not joint ones and not the partner's
          // (DATA_MODEL 2.10).
          final spent = read.complete
              ? _sum([
                  for (final t in expenses)
                    if ((ids == null || ids.contains(t.categoryId)) &&
                        (!b.isPersonal ||
                            (t.whoScope != 'joint' && t.whoUid == b.scope)))
                      t,
                ])
              : null;
          return BudgetStatus(
            budgetId: b.id,
            label: b.categoryId == 'total'
                ? 'Total'
                : snap.category(b.categoryId)?.name ?? b.categoryId,
            limitMinor: b.limitMinor,
            scope: b.isPersonal ? 'personal' : 'household',
            spentMinor: spent,
            remainingMinor: spent == null ? null : b.limitMinor - spent,
          );
        }(),
    ],
  );
}

/// `findLoans`.
Future<LoansResult> findLoans(
  LoansQuery q,
  XpenseContext c,
  ToolDeps deps,
) async {
  final snap = await _snapshot(c, deps);
  final status = q.status ?? 'open';
  final person = q.person?.toLowerCase().trim();
  final loans = await deps.reader.loans(c.hid, uid: c.uid);
  return LoansResult(
    loans: [
      for (final l in loans)
        if ((status == 'all' || l.status == status) &&
            (person == null ||
                person.isEmpty ||
                _personMatches(snap.person(l.personId), person)))
          LoanInfo(
            loanId: l.id,
            direction: l.direction,
            personName: snap.person(l.personId)?.name ?? 'Someone',
            principalMinor: l.principalMinor,
            outstandingMinor: l.outstandingMinor,
            currency: l.currency,
            status: l.status,
            dueOn: l.dueOn,
          ),
    ],
  );
}

bool _personMatches(HouseholdPerson? p, String query) =>
    p != null &&
    (p.name.toLowerCase().contains(query) ||
        p.aliases.any((a) => a.toLowerCase().contains(query)));

/// `getFxRate`.
Future<FxRateResult> getFxRate(
  FxRateQuery q,
  XpenseContext c,
  ToolDeps deps,
) async {
  final day = parseIsoDay(q.date) != null
      ? q.date!
      : localToday(deps.clock, c.tz).iso;
  final rate = await deps.reader.fxRateOn(c.hid, day);
  return FxRateResult(
    pair: 'USD/IQD',
    rate: rate?.usdIqd,
    source: rate?.kind,
    asOf: rate?.date,
  );
}

/// `findEntries`: at most 10 matches, newest first.
Future<FoundEntries> findEntries(
  FindEntriesQuery q,
  XpenseContext c,
  ToolDeps deps,
) async {
  final snap = await _snapshot(c, deps);
  final today = localToday(deps.clock, c.tz).iso;
  final to = parseIsoDay(q.to) != null ? q.to! : today;
  final from = parseIsoDay(q.from) != null ? q.from! : addDays(to, -60);
  final read = await deps.reader.transactions(
    c.hid,
    uid: c.uid,
    fromOn: from,
    toOn: to,
  );
  final txns = read.items;
  final text = q.text?.toLowerCase().trim();
  final amount = parseWrittenAmount(q.amount);
  bool amountMatches(LedgerTxn t) {
    if (amount == null) return true;
    final cur = Currency.tryParse(t.currency);
    if (cur == null) return false;
    return Money(t.amountMinor, cur).toMajorString() ==
        Money.parseMajor(
          amount.toString(),
          cur,
        ).fold((m) => m.toMajorString(), (_) => '');
  }

  final found = [
    for (final t in txns)
      if (amountMatches(t) &&
          (text == null ||
              text.isEmpty ||
              t.title.toLowerCase().contains(text) ||
              (t.note?.toLowerCase().contains(text) ?? false) ||
              (snap.category(t.categoryId)?.name.toLowerCase().contains(text) ??
                  false)))
        t,
  ].take(10);
  return FoundEntries(
    complete: read.complete,
    items: [
      for (final t in found)
        FoundEntry(
          txnId: t.id,
          title: t.title,
          subtitle: [
            ?snap.category(t.categoryId)?.name,
            snap.account(t.accountId)?.name ?? 'Private account',
          ].join(' · '),
          amountMinor: t.amountMinor,
          currency: t.currency,
          type: t.type,
          occurredOn: t.occurredOn,
        ),
    ],
  );
}
