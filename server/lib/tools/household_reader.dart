/// Read-only access to one household's data, as the agent tools need it.
///
/// The tools never touch Firestore directly: they read through
/// [HouseholdReader], whose Firestore implementation lives in `lib/runtime/`
/// (the only module besides `lib/admin/` that may import
/// `google_cloud_firestore`). Every method that returns member-scoped
/// documents takes the calling member's uid and returns only documents whose
/// `visibleTo` contains it (DATA_MODEL 4), so a tool can never see a
/// partner's private account.
library;

import 'package:meta/meta.dart';

/// `households/{hid}` (DATA_MODEL 2.2), the fields the agent uses.
@immutable
final class HouseholdProfile {
  /// Creates a profile.
  const new({
    required this.hid,
    required this.baseCurrency,
    required this.memberIds,
    this.timeZone = 'Asia/Baghdad',
    this.weekStart = 'sat',
    this.rateKind = 'market',
  });

  /// The household id.
  final String hid;

  /// `USD` or `IQD`.
  final String baseCurrency;

  /// IANA time zone.
  final String timeZone;

  /// Member uids (at most two).
  final List<String> memberIds;

  /// `sat`, `sun` or `mon`.
  final String weekStart;

  /// `official` or `market`: the household's label for its daily rate.
  final String rateKind;
}

/// `members/{uid}` (DATA_MODEL 2.3).
@immutable
final class HouseholdMember {
  /// Creates a member.
  const new({required this.uid, required this.displayName, this.role});

  /// The member's uid.
  final String uid;

  /// Display name. Goes into the model prompt only, never into the context
  /// map or logs.
  final String displayName;

  /// `owner` or `partner`.
  final String? role;
}

/// `accounts/{accountId}` (DATA_MODEL 2.4).
@immutable
final class HouseholdAccount {
  /// Creates an account.
  const new({
    required this.id,
    required this.name,
    required this.currency,
    required this.scope,
    this.kind = 'cash',
    this.ownerUid,
    this.balanceMinor = 0,
    this.archived = false,
    this.order = 0,
  });

  /// The account id.
  final String id;

  /// Display name.
  final String name;

  /// `cash`, `bank`, `credit`, `savings` or `other`.
  final String kind;

  /// `USD` or `IQD`.
  final String currency;

  /// `personal` or `joint`.
  final String scope;

  /// The owner when personal.
  final String? ownerUid;

  /// The maintained balance, in minor units of [currency].
  final int balanceMinor;

  /// Whether the account is archived.
  final bool archived;

  /// List order.
  final int order;
}

/// `categories/{categoryId}` (DATA_MODEL 2.6).
@immutable
final class HouseholdCategory {
  /// Creates a category.
  const new({
    required this.id,
    required this.slug,
    required this.name,
    required this.kind,
    this.parentId,
    this.archived = false,
  });

  /// The category id.
  final String id;

  /// Stable slug, e.g. `groceries`.
  final String slug;

  /// English name.
  final String name;

  /// `expense` or `income`.
  final String kind;

  /// The group's id, for a sub-category.
  final String? parentId;

  /// Whether the category is archived.
  final bool archived;
}

/// `people/{personId}` (DATA_MODEL 2.7).
@immutable
final class HouseholdPerson {
  /// Creates a person.
  const new({required this.id, required this.name, this.aliases = const []});

  /// The person id.
  final String id;

  /// Name.
  final String name;

  /// Other names the household uses.
  final List<String> aliases;
}

/// `loans/{loanId}` (DATA_MODEL 2.8).
@immutable
final class HouseholdLoan {
  /// Creates a loan.
  const new({
    required this.id,
    required this.direction,
    required this.personId,
    required this.principalMinor,
    required this.outstandingMinor,
    required this.currency,
    required this.status,
    this.startedOn,
    this.dueOn,
  });

  /// The loan id.
  final String id;

  /// `given` or `taken`.
  final String direction;

  /// The counterparty.
  final String personId;

  /// The amount lent or borrowed.
  final int principalMinor;

  /// What is still owed.
  final int outstandingMinor;

  /// `USD` or `IQD`.
  final String currency;

  /// `open` or `closed`.
  final String status;

  /// Start date, `YYYY-MM-DD`.
  final String? startedOn;

  /// Due date, `YYYY-MM-DD`.
  final String? dueOn;
}

/// `budgets/{budgetId}` (DATA_MODEL 2.10).
@immutable
final class HouseholdBudget {
  /// Creates a budget.
  const new({
    required this.id,
    required this.categoryId,
    required this.limitMinor,
    this.scope = householdBudgetScope,
  });

  /// The budget id.
  final String id;

  /// A category id, or `total`.
  final String categoryId;

  /// Monthly limit in base-currency minor units.
  final int limitMinor;

  /// [householdBudgetScope], or the uid of the member whose own spending
  /// the budget limits (DATA_MODEL 2.10).
  final String scope;

  /// Whether the budget limits one member's own spending.
  bool get isPersonal => scope != householdBudgetScope;
}

/// `budgets.scope` for a budget over the household's spending.
const householdBudgetScope = 'household';

/// A saved transaction (DATA_MODEL 2.5), the fields the tools read.
@immutable
final class LedgerTxn {
  /// Creates a transaction.
  const new({
    required this.id,
    required this.type,
    required this.amountMinor,
    required this.currency,
    required this.baseAmountMinor,
    required this.accountId,
    required this.occurredOn,
    required this.title,
    this.toAccountId,
    this.categoryId,
    this.whoUid,
    this.whoScope,
    this.note,
    this.personId,
    this.loanId,
  });

  /// The transaction id.
  final String id;

  /// Ledger type.
  final String type;

  /// Amount in minor units of [currency], always positive.
  final int amountMinor;

  /// `USD` or `IQD`.
  final String currency;

  /// The amount in the household base currency.
  final int baseAmountMinor;

  /// The account money left (or entered).
  final String accountId;

  /// The destination account of a transfer.
  final String? toAccountId;

  /// The category id.
  final String? categoryId;

  /// The member the entry belongs to, when `whoScope == member`.
  final String? whoUid;

  /// `member` or `joint`.
  final String? whoScope;

  /// Household-local date, `YYYY-MM-DD`.
  final String occurredOn;

  /// Merchant or short label.
  final String title;

  /// Free-text note.
  final String? note;

  /// Counterparty for loans and repayments.
  final String? personId;

  /// The loan this entry belongs to.
  final String? loanId;
}

/// The transactions of a date range.
@immutable
final class TxnRead {
  /// Creates a read.
  const new(this.items, {this.complete = true});

  /// The transactions, newest first.
  final List<LedgerTxn> items;

  /// False when the range held more transactions than one read may return
  /// ([HouseholdReader.maxRangeTransactions]); [items] is then a part of the
  /// range, and no total may be presented as complete from it.
  final bool complete;
}

/// `fxRates/{yyyy-mm-dd}` (DATA_MODEL 2.13).
@immutable
final class FxDay {
  /// Creates a rate.
  const new({required this.date, required this.usdIqd, required this.kind});

  /// The household-local day of the rate.
  final String date;

  /// IQD per USD, a decimal string.
  final String usdIqd;

  /// `official` or `market`.
  final String kind;
}

/// Read-only household data for the agent tools.
///
/// Implementations return only what the calling member (`uid`) may see
/// (`visibleTo`), never soft-deleted transactions, and throw
/// [HouseholdUnavailable] when the backend cannot be reached.
abstract interface class HouseholdReader {
  /// The household document, or null when it does not exist.
  Future<HouseholdProfile?> profile(String hid);

  /// The household's members.
  Future<List<HouseholdMember>> members(String hid);

  /// Accounts visible to [uid], archived ones included.
  Future<List<HouseholdAccount>> accounts(String hid, {required String uid});

  /// Every category, archived ones included.
  Future<List<HouseholdCategory>> categories(String hid);

  /// People visible to [uid].
  Future<List<HouseholdPerson>> people(String hid, {required String uid});

  /// Loans visible to [uid].
  Future<List<HouseholdLoan>> loans(String hid, {required String uid});

  /// Budgets visible to [uid].
  Future<List<HouseholdBudget>> budgets(String hid, {required String uid});

  /// The most transactions one [transactions] read returns.
  static const maxRangeTransactions = 10000;

  /// Every transaction visible to [uid] with `occurredOn` in
  /// `[fromOn, toOn]` (inclusive, `YYYY-MM-DD`), newest first, read in pages.
  /// A range with more than [maxRangeTransactions] comes back with
  /// `complete: false`.
  Future<TxnRead> transactions(
    String hid, {
    required String uid,
    required String fromOn,
    required String toOn,
  });

  /// Whether the household has a non-archived account that [uid] cannot see
  /// (a partner's private account). Only this yes or no leaves the reader,
  /// never the account itself; it tells the member that totals are "your
  /// view" (DATA_MODEL 4).
  Future<bool> hasHiddenAccounts(String hid, {required String uid});

  /// The day's rate, or the most recent earlier one, or null.
  Future<FxDay?> fxRateOn(String hid, String date);
}

/// The household backend could not be reached. The tool reports it to the
/// model as an error instead of inventing data.
final class HouseholdUnavailable implements Exception {
  /// Creates the failure.
  const new(this.operation, [this.cause]);

  /// What was being read.
  final String operation;

  /// The underlying error, for logs.
  final Object? cause;

  @override
  String toString() => 'HouseholdUnavailable($operation): $cause';
}
