// What Activity shows, as plain values (DESIGN_SYSTEM screen 16; BACKLOG
// S2.4): the filters, the day groups with their net, the search over the
// loaded window, and when a search reads like a question for Ask. No
// widgets here, so all of it is unit-tested.
import 'package:flutter/foundation.dart';
import 'package:xpense_app/data/activity_feed.dart';
import 'package:xpense_app/data/transactions_repository.dart';
import 'package:xpense_shared/xpense_shared.dart';

/// The filter bar of Activity, in order.
enum ActivityFilter {
  /// Every entry.
  all,

  /// Money spent: expenses.
  out,

  /// Money received: income.
  inflow,

  /// Loans and repayments, both ways.
  loans,

  /// The member's own entries.
  you,

  /// The partner's entries; shown only once the partner has joined.
  partner;

  /// The ledger types of the loans filter.
  static const Set<LedgerType> loanTypes = {
    LedgerType.loanGiven,
    LedgerType.loanTaken,
    LedgerType.repaymentReceived,
    LedgerType.repaymentMade,
  };

  /// The feed query for this filter, the newest [limit] entries. Null when
  /// the filter needs a member that is not known ([partner] before they
  /// join, or no viewer).
  ActivityQuery? query({
    required int limit,
    required String? viewerUid,
    required String? partnerUid,
  }) => switch (this) {
    all => ActivityQuery(limit: limit),
    out => ActivityQuery(limit: limit, types: const {LedgerType.expense}),
    inflow => ActivityQuery(limit: limit, types: const {LedgerType.income}),
    loans => ActivityQuery(limit: limit, types: loanTypes),
    you =>
      viewerUid == null ? null : ActivityQuery(limit: limit, whoUid: viewerUid),
    partner =>
      partnerUid == null
          ? null
          : ActivityQuery(limit: limit, whoUid: partnerUid),
  };
}

/// How a row's amount reads: spent shows a minus, income a plus in green;
/// moves, loans and corrections show the bare amount.
enum AmountSign {
  /// `−42.80`.
  minus,

  /// `+3,200.00`, income green.
  plus,

  /// `300.00`.
  none,
}

/// The sign of [txn]'s amount on its row.
AmountSign amountSignOf(LedgerTransaction txn) => switch (txn.type) {
  LedgerType.expense => AmountSign.minus,
  LedgerType.income => AmountSign.plus,
  _ => AmountSign.none,
};

/// What [txn] adds to its day's net, in the base currency: income adds,
/// spending subtracts, moves and loans leave it alone (as on artboard 16).
int netEffectOf(LedgerTransaction txn) => switch (txn.type) {
  LedgerType.income => txn.baseAmountMinor,
  LedgerType.expense => -txn.baseAmountMinor,
  _ => 0,
};

/// One day of Activity.
@immutable
final class ActivityDay {
  /// Creates the group.
  const new({
    required this.day,
    required this.entries,
    required this.netMinor,
    required this.hasNet,
  });

  /// The household-local day, `YYYY-MM-DD`.
  final String day;

  /// Its entries, newest first.
  final List<LedgerTransaction> entries;

  /// Income minus spending, in base minor units.
  final int netMinor;

  /// Whether any entry counts towards the net (otherwise no net is shown).
  final bool hasNet;

  @override
  bool operator ==(Object other) =>
      other is ActivityDay &&
      other.day == day &&
      listEquals(other.entries, entries) &&
      other.netMinor == netMinor &&
      other.hasNet == hasNet;

  @override
  int get hashCode =>
      Object.hash(day, Object.hashAll(entries), netMinor, hasNet);
}

/// Groups [entries] (newest first) by `occurredOn`, keeping order.
List<ActivityDay> groupByDay(List<LedgerTransaction> entries) {
  final days = <ActivityDay>[];
  var start = 0;
  for (var i = 1; i <= entries.length; i++) {
    if (i < entries.length &&
        entries[i].occurredOn == entries[start].occurredOn) {
      continue;
    }
    final slice = entries.sublist(start, i);
    var net = 0;
    var counted = false;
    for (final t in slice) {
      if (t.type == LedgerType.income || t.type == LedgerType.expense) {
        counted = true;
        net += netEffectOf(t);
      }
    }
    days.add(
      ActivityDay(
        day: entries[start].occurredOn,
        entries: slice,
        netMinor: net,
        hasNet: counted,
      ),
    );
    start = i;
  }
  return days;
}

/// One line of the Activity list: a day header or an entry. The list is
/// flat so it builds lazily however long the window is.
@immutable
sealed class ActivityItem {
  const new();
}

/// The header of [day].
final class ActivityDayHeader extends ActivityItem {
  /// Creates the header.
  const new(this.day);

  /// The day.
  final ActivityDay day;
}

/// An entry row; [last] is the last row of its day (no hairline under it).
final class ActivityEntryItem extends ActivityItem {
  /// Creates the row.
  const new(this.txn, {required this.last});

  /// The entry.
  final LedgerTransaction txn;

  /// Whether it ends its day.
  final bool last;
}

/// The flat list for [days].
List<ActivityItem> flatten(List<ActivityDay> days) => [
  for (final day in days) ...[
    ActivityDayHeader(day),
    for (final (i, t) in day.entries.indexed)
      ActivityEntryItem(t, last: i == day.entries.length - 1),
  ],
];

/// The words of an entry search matches against: title, note, category
/// name, counterparty and the amount as shown (`42.80`, `1,400.00`,
/// `1400.00`).
@immutable
final class SearchText {
  /// Creates the text for [txn]; [categoryName] is its category's name.
  factory of(LedgerTransaction txn, {String? categoryName}) {
    final exponent = txn.currency.exponent;
    final amount = _amount(txn.amountMinor, exponent);
    return SearchText._(
      [
        txn.title,
        txn.note ?? '',
        categoryName ?? '',
        txn.personName ?? '',
      ].join('\n').toLowerCase(),
      amount,
    );
  }

  const new _(this.words, this.amount);

  /// Lower-cased title, note, category and counterparty.
  final String words;

  /// The amount without grouping, such as `1400.00`.
  final String amount;

  static String _amount(int minor, int exponent) {
    if (exponent == 0) return '$minor';
    var divisor = 1;
    for (var i = 0; i < exponent; i++) {
      divisor *= 10;
    }
    final fraction = (minor % divisor).toString().padLeft(exponent, '0');
    return '${minor ~/ divisor}.$fraction';
  }
}

/// Whether [text] matches [query]: every word of the query appears in the
/// entry's words, or the query is a number found in its amount.
bool searchMatches(SearchText text, String query) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return true;
  final numeric = q.replaceAll(',', '');
  if (RegExp(r'^\d+(\.\d*)?$').hasMatch(numeric)) {
    if (text.amount.startsWith(numeric) || text.amount.contains(numeric)) {
      return true;
    }
  }
  for (final word in q.split(RegExp(r'\s+'))) {
    if (!text.words.contains(word)) return false;
  }
  return true;
}

const Set<String> _questionStarts = {
  'how',
  'what',
  "what's",
  'whats',
  'when',
  'where',
  'why',
  'who',
  'whom',
  'which',
  'did',
  'do',
  'does',
  'is',
  'are',
  'was',
  'were',
  'can',
  'could',
  'should',
  'will',
  'would',
  'have',
  'has',
  'show',
  'compare',
  'list',
  'tell',
  'give',
  'summarize',
  'summarise',
  'explain',
  'total',
};

/// Whether [text] reads like a question for Ask rather than a search: it
/// ends with `?`, or it has three words or more and starts like a question
/// or a request ("how much did we spend on food", "show me June").
bool looksLikeQuestion(String text) {
  final t = text.trim();
  if (t.isEmpty) return false;
  if (t.endsWith('?')) return t.length > 1;
  final words = t.toLowerCase().split(RegExp(r'\s+'));
  return words.length >= 3 && _questionStarts.contains(words.first);
}
