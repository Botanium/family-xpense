// Home's figures (DESIGN_SYSTEM 9, screen 6; BACKLOG S2.5), derived on the
// phone from what the viewer can read. Nothing here is stored: the totals
// are recomputed from the month's transactions every time they change
// (DATA_MODEL 1, "derive, don't store").
//
// Everything is in integer minor units of the household base currency,
// summed from each transaction's stored `baseAmountMinor`, which was fixed
// with that day's rate when it was saved (WP-20). No rate is applied here to
// a transaction; the latest rate is used only for the account balances in
// another currency and for the "other currency" line under the hero.
import 'package:flutter/foundation.dart';
import 'package:xpense_app/data/accounts_repository.dart';
import 'package:xpense_app/data/transactions_repository.dart';
import 'package:xpense_shared/xpense_shared.dart';

/// How many entries Recent shows.
const int homeRecentCount = 4;

/// A calendar month, with the household-local day Home is shown on.
@immutable
final class HomeMonth {
  /// The month of [today] (a local date; the time is ignored).
  new of(DateTime today)
    : year = today.year,
      month = today.month,
      day = today.day;

  /// The year.
  final int year;

  /// The month, 1 to 12.
  final int month;

  /// Today's day of the month, 1 to 31: the last bar of the chart.
  final int day;

  /// The first day, `YYYY-MM-01`, as stored in `occurredOn`.
  String get firstDay => _dayKey(1);

  /// Today, `YYYY-MM-DD`.
  String get today => _dayKey(day);

  String _dayKey(int d) =>
      '${year.toString().padLeft(4, '0')}-'
      '${month.toString().padLeft(2, '0')}-'
      '${d.toString().padLeft(2, '0')}';

  /// The day of the month of a stored `occurredOn` in this month, or null
  /// when it is another month or later than today.
  int? dayOf(String occurredOn) {
    if (occurredOn.length != 10 ||
        !occurredOn.startsWith(firstDay.substring(0, 8))) {
      return null;
    }
    final d = int.tryParse(occurredOn.substring(8));
    if (d == null || d < 1 || d > day) return null;
    return d;
  }

  @override
  bool operator ==(Object other) =>
      other is HomeMonth &&
      other.year == year &&
      other.month == month &&
      other.day == day;

  @override
  int get hashCode => Object.hash(year, month, day);
}

/// Whose an entry is, for its meta line ("You", "Sam", "Joint").
enum HomeWho {
  /// The viewer's.
  you,

  /// The partner's.
  partner,

  /// Both members'.
  joint,
}

/// How a Recent row shows its amount.
enum RecentDirection {
  /// Money in: `+`, income green for income.
  inflow,

  /// Money out: `−`.
  outflow,

  /// Moved between the household's own accounts: no sign.
  move,
}

/// One row of Recent.
@immutable
final class RecentEntry {
  /// Creates a row.
  const new({
    required this.id,
    required this.title,
    required this.type,
    required this.who,
    required this.amountMinor,
    required this.currency,
    required this.direction,
    this.categorySlug,
    this.savings = false,
  });

  /// The transaction id, for the entry detail route.
  final String id;

  /// Merchant or label; empty when the entry has none.
  final String title;

  /// The ledger type.
  final LedgerType type;

  /// The category id (a slug for system categories), when there is one.
  final String? categorySlug;

  /// Whose it is.
  final HomeWho who;

  /// The amount in [currency] minor units, positive.
  final int amountMinor;

  /// The entry's own currency.
  final Currency currency;

  /// In, out or a move.
  final RecentDirection direction;

  /// Whether it is a move to a savings goal.
  final bool savings;

  /// The amount with its sign applied, for display.
  int get signedMinor =>
      direction == RecentDirection.outflow ? -amountMinor : amountMinor;

  @override
  bool operator ==(Object other) =>
      other is RecentEntry &&
      other.id == id &&
      other.title == title &&
      other.type == type &&
      other.categorySlug == categorySlug &&
      other.who == who &&
      other.amountMinor == amountMinor &&
      other.currency == currency &&
      other.direction == direction &&
      other.savings == savings;

  @override
  int get hashCode => Object.hash(
    id,
    title,
    type,
    categorySlug,
    who,
    amountMinor,
    currency,
    direction,
    savings,
  );
}

/// Everything Home shows, in the household base currency.
@immutable
final class HomeSummary {
  /// Creates a summary.
  const new({
    required this.baseCurrency,
    required this.month,
    required this.balanceMinor,
    required this.balanceComplete,
    required this.unconverted,
    required this.incomeMinor,
    required this.spentMinor,
    required this.savedMinor,
    required this.dailySpentMinor,
    required this.recent,
    this.otherCurrency,
    this.otherBalanceMinor,
    this.partnerName,
  });

  /// The household base currency; every figure but [otherBalanceMinor] is
  /// in it.
  final Currency baseCurrency;

  /// The month shown.
  final HomeMonth month;

  /// The sum of the visible, unarchived accounts.
  final int balanceMinor;

  /// Whether the viewer sees every account: the label is then "Household
  /// balance", otherwise "Your view" (DATA_MODEL 4).
  final bool balanceComplete;

  /// Account currencies left out of [balanceMinor] for want of a rate.
  final Set<Currency> unconverted;

  /// The other currency of the latest rate's pair, for the line under the
  /// hero; null without a rate.
  final Currency? otherCurrency;

  /// [balanceMinor] in [otherCurrency] at the latest rate.
  final int? otherBalanceMinor;

  /// Income this month.
  final int incomeMinor;

  /// Spending this month.
  final int spentMinor;

  /// Moved to savings goals this month.
  final int savedMinor;

  /// Spending per day, from the 1st to today (one value per day).
  final List<int> dailySpentMinor;

  /// The latest entries, newest first.
  final List<RecentEntry> recent;

  /// The partner's display name, when there is one.
  final String? partnerName;

  /// This month's net: income less spending. The hero's delta line.
  int get netMinor => incomeMinor - spentMinor;

  /// Average spending per day so far this month, rounded half up to whole
  /// major units and returned in minor units (`AVG 210/DAY`).
  int get dailyAverageMinor {
    final days = dailySpentMinor.length;
    if (days == 0 || spentMinor <= 0) return 0;
    final perMajor = baseCurrency.minorPerMajor;
    final denominator = days * perMajor;
    final wholeUnits = (spentMinor * 2 + denominator) ~/ (denominator * 2);
    return wholeUnits * perMajor;
  }

  /// The day of the month with the most spending (the latest such day on a
  /// tie), or null when nothing was spent.
  int? get busiestDay {
    int? best;
    var most = 0;
    for (var i = 0; i < dailySpentMinor.length; i++) {
      if (dailySpentMinor[i] > 0 && dailySpentMinor[i] >= most) {
        most = dailySpentMinor[i];
        best = i + 1;
      }
    }
    return best;
  }

  @override
  bool operator ==(Object other) =>
      other is HomeSummary &&
      other.baseCurrency == baseCurrency &&
      other.month == month &&
      other.balanceMinor == balanceMinor &&
      other.balanceComplete == balanceComplete &&
      setEquals(other.unconverted, unconverted) &&
      other.otherCurrency == otherCurrency &&
      other.otherBalanceMinor == otherBalanceMinor &&
      other.incomeMinor == incomeMinor &&
      other.spentMinor == spentMinor &&
      other.savedMinor == savedMinor &&
      listEquals(other.dailySpentMinor, dailySpentMinor) &&
      listEquals(other.recent, recent) &&
      other.partnerName == partnerName;

  @override
  int get hashCode => Object.hash(
    baseCurrency,
    month,
    balanceMinor,
    balanceComplete,
    Object.hashAll(unconverted),
    otherCurrency,
    otherBalanceMinor,
    incomeMinor,
    spentMinor,
    savedMinor,
    Object.hashAll(dailySpentMinor),
    Object.hashAll(recent),
    partnerName,
  );
}

/// Whether [viewerUid] may count [t]: it is visible to them and not
/// deleted. Reads already carry the `visibleTo` filter; this repeats it so a
/// stray document (a cache from another member, a test double) can never
/// leak a partner's private entry into the totals.
bool visibleToViewer(LedgerTransaction t, String viewerUid) =>
    t.visibleTo.contains(viewerUid) && !t.deleted;

/// Builds Home's figures. Pure, so it is tested without widgets.
///
/// [monthTransactions] are this month's entries and [recentTransactions]
/// the latest ones (either may hold more; both are filtered here).
/// [accounts] are the accounts the viewer can read.
HomeSummary buildHomeSummary({
  required List<LedgerTransaction> monthTransactions,
  required List<LedgerTransaction> recentTransactions,
  required List<Account> accounts,
  required List<HouseholdMember> members,
  required String viewerUid,
  required Currency baseCurrency,
  required HomeMonth month,
  FxRate? rate,
}) {
  var income = 0;
  var spent = 0;
  var saved = 0;
  final daily = List<int>.filled(month.day, 0);
  final counted = <String>{};
  for (final t in monthTransactions) {
    if (!visibleToViewer(t, viewerUid) || !counted.add(t.id)) continue;
    final day = month.dayOf(t.occurredOn);
    if (day == null) continue;
    switch (t.type) {
      case LedgerType.income:
        income += t.baseAmountMinor;
      case LedgerType.expense:
        spent += t.baseAmountMinor;
        daily[day - 1] += t.baseAmountMinor;
      case LedgerType.transfer when t.goalId != null:
        saved += t.baseAmountMinor;
      case _:
        break;
    }
  }

  var balance = 0;
  final unconverted = <Currency>{};
  for (final account in accounts) {
    if (account.archived) continue;
    if (account.currency == baseCurrency) {
      balance += account.balanceMinor;
      continue;
    }
    final converted = rate
        ?.convert(account.balance, baseCurrency)
        .valueOrNull
        ?.minorUnits;
    if (converted == null) {
      unconverted.add(account.currency);
    } else {
      balance += converted;
    }
  }

  Currency? other;
  int? otherBalance;
  if (rate != null &&
      (rate.pair.base == baseCurrency || rate.pair.quote == baseCurrency)) {
    other = rate.pair.base == baseCurrency ? rate.pair.quote : rate.pair.base;
    otherBalance = rate
        .convert(Money(balance, baseCurrency), other)
        .valueOrNull
        ?.minorUnits;
    if (otherBalance == null) other = null;
  }

  final latest = [
    for (final t in {
      for (final t in recentTransactions)
        if (visibleToViewer(t, viewerUid)) t.id: t,
    }.values)
      t,
  ]..sort((a, b) => b.occurredAt.compareTo(a.occurredAt));

  final partner = members.where((m) => m.uid != viewerUid).firstOrNull;
  return HomeSummary(
    baseCurrency: baseCurrency,
    month: month,
    balanceMinor: balance,
    balanceComplete: !members.any(
      (m) => m.uid != viewerUid && m.hasPrivateAccounts,
    ),
    unconverted: unconverted,
    otherCurrency: other,
    otherBalanceMinor: otherBalance,
    incomeMinor: income,
    spentMinor: spent,
    savedMinor: saved,
    dailySpentMinor: daily,
    recent: [
      for (final t in latest.take(homeRecentCount)) _recent(t, viewerUid),
    ],
    partnerName: partner == null || partner.displayName.isEmpty
        ? null
        : partner.displayName,
  );
}

RecentEntry _recent(LedgerTransaction t, String viewerUid) => RecentEntry(
  id: t.id,
  title: t.title,
  type: t.type,
  categorySlug: t.categoryId,
  who: t.whoScope == WhoScope.joint
      ? HomeWho.joint
      : t.whoUid == null || t.whoUid == viewerUid
      ? HomeWho.you
      : HomeWho.partner,
  amountMinor: t.amountMinor,
  currency: t.currency,
  savings: t.type == LedgerType.transfer && t.goalId != null,
  direction: switch (t.type) {
    LedgerType.income ||
    LedgerType.loanTaken ||
    LedgerType.repaymentReceived => RecentDirection.inflow,
    LedgerType.expense ||
    LedgerType.loanGiven ||
    LedgerType.repaymentMade => RecentDirection.outflow,
    LedgerType.transfer => RecentDirection.move,
    LedgerType.adjustment =>
      (t.adjustmentSign ?? 1) < 0
          ? RecentDirection.outflow
          : RecentDirection.inflow,
  },
);
