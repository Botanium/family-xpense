/// The balance-effect table (DATA_MODEL 3): how one transaction moves the
/// two stored aggregates, `account.balanceMinor` and
/// `loan.outstandingMinor`.
///
/// The phone's write path applies these effects as `FieldValue.increment`s
/// in the same batch as the transaction; the server's nightly reconcile
/// (`/jobs/reconcile`) sums them over the whole ledger and corrects drift.
/// Both read this one table, so they cannot disagree.
library;

import 'package:meta/meta.dart';
import 'package:xpense_shared/taxonomy/intents.dart';

/// The fields of a stored transaction that move balances.
@immutable
final class LedgerLine {
  /// Creates a line. [amountMinor] is positive; the sign comes from [type]
  /// (and, for an adjustment, [adjustmentSign]).
  const new({
    required this.type,
    required this.amountMinor,
    required this.accountId,
    this.toAccountId,
    this.toAmountMinor,
    this.adjustmentSign = 1,
    this.loanId,
    this.deleted = false,
  });

  /// Reads a stored transaction (`transactions/{id}`, DATA_MODEL 2.5), or
  /// null when it has no known type, no positive amount or no account.
  ///
  /// A transaction whose `deletedAt` is set reads as [deleted]; any value
  /// other than null counts, so a pending server timestamp does too.
  static LedgerLine? fromFields(Map<String, Object?> data) {
    final type = switch (data['type']) {
      final String wire => LedgerType.tryParse(wire),
      _ => null,
    };
    final amount = data['amountMinor'];
    final accountId = data['accountId'];
    if (type == null || amount is! int || amount <= 0 || accountId is! String) {
      return null;
    }
    final toAmount = data['toAmountMinor'];
    return LedgerLine(
      type: type,
      amountMinor: amount,
      accountId: accountId,
      toAccountId: switch (data['toAccountId']) {
        final String id => id,
        _ => null,
      },
      toAmountMinor: toAmount is int && toAmount > 0 ? toAmount : null,
      adjustmentSign: data['adjustmentSign'] == -1 ? -1 : 1,
      loanId: switch (data['loanId']) {
        final String id => id,
        _ => null,
      },
      deleted: data['deletedAt'] != null,
    );
  }

  /// The ledger type.
  final LedgerType type;

  /// The amount in minor units of the [accountId] account; positive.
  final int amountMinor;

  /// The account money leaves (or enters, for income-like types).
  final String accountId;

  /// The destination account of a transfer.
  final String? toAccountId;

  /// What arrives in [toAccountId] when the two accounts' currencies
  /// differ; null means [amountMinor].
  final int? toAmountMinor;

  /// `1` or `-1`: the direction of an `adjustment`.
  final int adjustmentSign;

  /// The loan a loan event or repayment belongs to.
  final String? loanId;

  /// Whether the transaction is soft-deleted; a deleted line moves nothing.
  final bool deleted;

  /// This line, deleted or not.
  LedgerLine withDeleted({required bool deleted}) => LedgerLine(
    type: type,
    amountMinor: amountMinor,
    accountId: accountId,
    toAccountId: toAccountId,
    toAmountMinor: toAmountMinor,
    adjustmentSign: adjustmentSign,
    loanId: loanId,
    deleted: deleted,
  );

  @override
  bool operator ==(Object other) =>
      other is LedgerLine &&
      other.type == type &&
      other.amountMinor == amountMinor &&
      other.accountId == accountId &&
      other.toAccountId == toAccountId &&
      other.toAmountMinor == toAmountMinor &&
      other.adjustmentSign == adjustmentSign &&
      other.loanId == loanId &&
      other.deleted == deleted;

  @override
  int get hashCode => Object.hash(
    type,
    amountMinor,
    accountId,
    toAccountId,
    toAmountMinor,
    adjustmentSign,
    loanId,
    deleted,
  );

  @override
  String toString() => 'LedgerLine(${type.wire}, $accountId)';
}

/// Signed changes to account balances and loan totals, each in the minor
/// units of that account's or loan's currency. Entries that net to zero are
/// left out, so [isEmpty] means "nothing to write".
@immutable
final class BalanceEffects {
  /// Creates effects, dropping zero entries.
  new({Map<String, int> accounts = const {}, Map<String, int> loans = const {}})
    : accounts = Map.unmodifiable(_nonZero(accounts)),
      loans = Map.unmodifiable(_nonZero(loans));

  /// No change.
  static final BalanceEffects none = BalanceEffects();

  /// Change to `accounts/{id}.balanceMinor`, by account id.
  final Map<String, int> accounts;

  /// Change to `loans/{id}.outstandingMinor`, by loan id.
  final Map<String, int> loans;

  /// Whether nothing changes.
  bool get isEmpty => accounts.isEmpty && loans.isEmpty;

  /// The change to account [id] (zero when untouched).
  int account(String id) => accounts[id] ?? 0;

  /// The change to loan [id] (zero when untouched).
  int loan(String id) => loans[id] ?? 0;

  /// Both changes together.
  BalanceEffects operator +(BalanceEffects other) => BalanceEffects(
    accounts: _sum(accounts, other.accounts, 1),
    loans: _sum(loans, other.loans, 1),
  );

  /// This change followed by undoing [other].
  BalanceEffects operator -(BalanceEffects other) => BalanceEffects(
    accounts: _sum(accounts, other.accounts, -1),
    loans: _sum(loans, other.loans, -1),
  );

  /// The reverse change.
  BalanceEffects operator -() => none - this;

  @override
  bool operator ==(Object other) =>
      other is BalanceEffects &&
      _mapEquals(other.accounts, accounts) &&
      _mapEquals(other.loans, loans);

  @override
  int get hashCode => Object.hash(
    Object.hashAllUnordered(accounts.entries.map((e) => (e.key, e.value))),
    Object.hashAllUnordered(loans.entries.map((e) => (e.key, e.value))),
  );

  @override
  String toString() => 'BalanceEffects(accounts: $accounts, loans: $loans)';

  static Map<String, int> _nonZero(Map<String, int> map) => {
    for (final e in map.entries)
      if (e.value != 0) e.key: e.value,
  };

  static Map<String, int> _sum(
    Map<String, int> a,
    Map<String, int> b,
    int sign,
  ) {
    final result = {...a};
    for (final e in b.entries) {
      result[e.key] = (result[e.key] ?? 0) + sign * e.value;
    }
    return result;
  }

  static bool _mapEquals(Map<String, int> a, Map<String, int> b) =>
      a.length == b.length && a.entries.every((e) => b[e.key] == e.value);
}

/// The sign of [type] on its `accountId` (DATA_MODEL 3): `-1` when money
/// leaves, `1` when it arrives. An adjustment takes [adjustmentSign].
int accountSign(LedgerType type, {int adjustmentSign = 1}) => switch (type) {
  LedgerType.expense ||
  LedgerType.loanGiven ||
  LedgerType.repaymentMade ||
  LedgerType.transfer => -1,
  LedgerType.income ||
  LedgerType.loanTaken ||
  LedgerType.repaymentReceived => 1,
  LedgerType.adjustment => adjustmentSign < 0 ? -1 : 1,
};

/// The sign of [type] on its loan's `outstandingMinor`: lending or
/// borrowing raises what is outstanding, a repayment lowers it, and other
/// types leave it alone.
int loanSign(LedgerType type) => switch (type) {
  LedgerType.loanGiven || LedgerType.loanTaken => 1,
  LedgerType.repaymentReceived || LedgerType.repaymentMade => -1,
  LedgerType.expense ||
  LedgerType.income ||
  LedgerType.transfer ||
  LedgerType.adjustment => 0,
};

/// What [line] does to balances and loan totals (DATA_MODEL 3). A deleted
/// line, or null, does nothing.
///
/// | Type | `accountId` | `toAccountId` |
/// |---|---|---|
/// | expense, loan_given, repayment_made | − amount | |
/// | income, loan_taken, repayment_received | + amount | |
/// | transfer | − amount | + `toAmountMinor` (or amount) |
/// | adjustment | ± amount (`adjustmentSign`) | |
///
/// The loan named by `loanId` moves by [loanSign]: + amount for
/// loan_given and loan_taken, − amount for either repayment.
BalanceEffects effectsOf(LedgerLine? line) {
  if (line == null || line.deleted) return BalanceEffects.none;
  final accounts = <String, int>{
    line.accountId:
        accountSign(line.type, adjustmentSign: line.adjustmentSign) *
        line.amountMinor,
  };
  final to = line.toAccountId;
  if (line.type == LedgerType.transfer && to != null) {
    accounts[to] =
        (accounts[to] ?? 0) + (line.toAmountMinor ?? line.amountMinor);
  }
  final loanId = line.loanId;
  final loanDelta = loanSign(line.type) * line.amountMinor;
  return BalanceEffects(
    accounts: accounts,
    loans: {if (loanId != null && loanDelta != 0) loanId: loanDelta},
  );
}

/// The increments that turn the effects of [before] into those of [after]:
/// a save is `(null, line)`, a soft delete `(line, deleted line)`, an edit
/// `(old, new)`. Applying it keeps balances equal to [ledgerTotals].
BalanceEffects effectDelta(LedgerLine? before, LedgerLine? after) =>
    effectsOf(after) - effectsOf(before);

/// The balances and loan totals [lines] add up to, as the reconcile job
/// recomputes them. Accounts and loans with no live lines are left out
/// (their total is zero).
BalanceEffects ledgerTotals(Iterable<LedgerLine> lines) =>
    lines.fold(BalanceEffects.none, (sum, line) => sum + effectsOf(line));
