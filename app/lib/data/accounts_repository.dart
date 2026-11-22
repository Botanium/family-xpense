// The household's accounts as the signed-in member can see them, and how
// they are added, edited, archived and shared (DATA_MODEL 2.4, 3, 4;
// BACKLOG S1.6, S1.7, S1.8).
//
// This file is the interface features import. The Firestore adapter is
// `accounts_repository_firebase.dart` and the fake is
// `accounts_repository_fake.dart`; only the composition root and tests
// name them.
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:xpense_shared/xpense_shared.dart';

/// What kind of account (DATA_MODEL 2.4). Credit balances are negative.
enum AccountKind {
  /// Cash in a wallet or at home.
  cash,

  /// A current or checking account.
  bank,

  /// A credit card.
  credit,

  /// A savings account; goals live on these.
  savings,

  /// Anything else.
  other;

  /// The stored value.
  String get wire => name;

  /// Parses a stored value; unknown values read as [other].
  static AccountKind fromWire(Object? value) =>
      values.asNameMap()[value] ?? other;
}

/// Who an account belongs to.
enum AccountScope {
  /// One member's; private unless they share it.
  personal,

  /// Both members'; always visible to both.
  joint;

  /// The stored value.
  String get wire => name;

  /// Parses a stored value; unknown values read as [personal], the more
  /// private reading.
  static AccountScope fromWire(Object? value) =>
      value == 'joint' ? joint : personal;
}

/// An account (DATA_MODEL 2.4), as the signed-in member sees it.
@immutable
final class Account {
  /// Creates an account.
  const new({
    required this.id,
    required this.name,
    required this.kind,
    required this.currency,
    required this.scope,
    required this.visibleTo,
    this.ownerUid,
    this.sharedWithPartner = false,
    this.balanceMinor = 0,
    this.archived = false,
    this.order = 0,
    this.appliedVisibleTo,
    this.sharingDone,
    this.sharingTotal,
  });

  /// The document id.
  final String id;

  /// The name, such as "Cash wallet" or "Joint Visa ••4021".
  final String name;

  /// The kind.
  final AccountKind kind;

  /// The currency; every entry on the account is in it.
  final Currency currency;

  /// Personal or joint.
  final AccountScope scope;

  /// The owner of a personal account.
  final String? ownerUid;

  /// Whether the owner shares a personal account with their partner.
  final bool sharedWithPartner;

  /// Who can read it (DATA_MODEL 4).
  final List<String> visibleTo;

  /// The balance in minor units of [currency], maintained by increments.
  final int balanceMinor;

  /// Whether it is archived (hidden from lists and totals).
  final bool archived;

  /// List order.
  final int order;

  /// The [visibleTo] the account's history was last rewritten for, written
  /// by the server only (`visibilityAppliedTo`); null when not recorded.
  final List<String>? appliedVisibleTo;

  /// Entries rewritten so far by the running history rewrite, if any.
  final int? sharingDone;

  /// Entries the running history rewrite will look at, once counted.
  final int? sharingTotal;

  /// The balance as [Money].
  Money get balance => Money(balanceMinor, currency);

  /// Whether the history is still being shared or unshared ("Sharing…").
  bool get sharingInProgress {
    final applied = appliedVisibleTo;
    return applied != null && !setEquals(applied.toSet(), visibleTo.toSet());
  }

  /// Whether [uid] owns it.
  bool isOwnedBy(String uid) =>
      scope == AccountScope.personal && ownerUid == uid;

  /// Whether it is a personal account its owner keeps to themself.
  bool get isPrivate => scope == AccountScope.personal && !sharedWithPartner;

  @override
  bool operator ==(Object other) =>
      other is Account &&
      other.id == id &&
      other.name == name &&
      other.kind == kind &&
      other.currency == currency &&
      other.scope == scope &&
      other.ownerUid == ownerUid &&
      other.sharedWithPartner == sharedWithPartner &&
      listEquals(other.visibleTo, visibleTo) &&
      other.balanceMinor == balanceMinor &&
      other.archived == archived &&
      other.order == order &&
      listEquals(other.appliedVisibleTo, appliedVisibleTo) &&
      other.sharingDone == sharingDone &&
      other.sharingTotal == sharingTotal;

  @override
  int get hashCode => Object.hash(
    id,
    name,
    kind,
    currency,
    scope,
    ownerUid,
    sharedWithPartner,
    Object.hashAll(visibleTo),
    balanceMinor,
    archived,
    order,
    appliedVisibleTo == null ? null : Object.hashAll(appliedVisibleTo!),
    sharingDone,
    sharingTotal,
  );

  // No name or balance: this lands in logs.
  @override
  String toString() => 'Account($id, ${kind.wire}, ${currency.code})';
}

/// A member of the household, for owner tags and the Partner filter.
@immutable
final class HouseholdMember {
  /// Creates a member.
  const new({
    required this.uid,
    required this.displayName,
    this.hasPrivateAccounts = false,
  });

  /// The uid.
  final String uid;

  /// The name they chose, such as "Sam".
  final String displayName;

  /// Whether they keep any account private. Their partner then sees
  /// "Your view" instead of "Household balance" (DATA_MODEL 4). Only the
  /// flag is shared, never the accounts.
  final bool hasPrivateAccounts;

  @override
  bool operator ==(Object other) =>
      other is HouseholdMember &&
      other.uid == uid &&
      other.displayName == displayName &&
      other.hasPrivateAccounts == hasPrivateAccounts;

  @override
  int get hashCode => Object.hash(uid, displayName, hasPrivateAccounts);

  @override
  String toString() => 'HouseholdMember($uid)';
}

/// One entry on an account's detail screen.
@immutable
final class AccountEntry {
  /// Creates an entry.
  const new({
    required this.id,
    required this.title,
    required this.type,
    required this.amountMinor,
    required this.currency,
    required this.occurredAt,
  });

  /// The transaction id.
  final String id;

  /// Its title, such as "Rent" or "Opening balance".
  final String title;

  /// The ledger type (`expense`, `income`, `transfer`, `adjustment`, …).
  final String type;

  /// Its effect on this account's balance, signed (DATA_MODEL 3).
  final int amountMinor;

  /// The account's currency.
  final Currency currency;

  /// When it happened.
  final DateTime occurredAt;

  @override
  bool operator ==(Object other) =>
      other is AccountEntry &&
      other.id == id &&
      other.title == title &&
      other.type == type &&
      other.amountMinor == amountMinor &&
      other.currency == currency &&
      other.occurredAt == occurredAt;

  @override
  int get hashCode =>
      Object.hash(id, title, type, amountMinor, currency, occurredAt);

  @override
  String toString() => 'AccountEntry($id, $type)';
}

/// A new account, as the add form fills it in.
@immutable
final class AccountDraft {
  /// Creates a draft.
  const new({
    required this.name,
    required this.kind,
    required this.currency,
    required this.scope,
    this.sharedWithPartner = false,
    this.openingBalanceMinor = 0,
    this.openingRate,
  });

  /// The name.
  final String name;

  /// The kind.
  final AccountKind kind;

  /// The currency.
  final Currency currency;

  /// Personal or joint.
  final AccountScope scope;

  /// Whether a personal account is shared from the start.
  final bool sharedWithPartner;

  /// Today's balance, signed (a card owes money: negative). Not zero
  /// becomes an `adjustment` entry (DESIGN_SYSTEM 9, screen 4).
  final int openingBalanceMinor;

  /// The USD/IQD rate typed with the opening balance, when the account is
  /// not in the base currency and the household has no rate yet. It is
  /// saved as today's rate (DATA_MODEL 2.13).
  final FxRate? openingRate;

  @override
  bool operator ==(Object other) =>
      other is AccountDraft &&
      other.name == name &&
      other.kind == kind &&
      other.currency == currency &&
      other.scope == scope &&
      other.sharedWithPartner == sharedWithPartner &&
      other.openingBalanceMinor == openingBalanceMinor &&
      other.openingRate == openingRate;

  @override
  int get hashCode => Object.hash(
    name,
    kind,
    currency,
    scope,
    sharedWithPartner,
    openingBalanceMinor,
    openingRate,
  );

  @override
  String toString() => 'AccountDraft(${kind.wire}, ${currency.code})';
}

/// Why an account write did not work. Carries a stable [code], never a
/// user-facing string.
@immutable
sealed class AccountsFailure implements Failure {
  const new();

  @override
  bool operator ==(Object other) => other.runtimeType == runtimeType;

  @override
  int get hashCode => runtimeType.hashCode;

  @override
  String toString() => code;
}

/// Not in a household, or Firestore's rules refused the write.
final class AccountsNotAllowed extends AccountsFailure {
  /// Creates the failure.
  const new();

  @override
  String get code => 'accounts.not_allowed';
}

/// The opening balance is in a currency other than the base and the
/// household has no exchange rate yet: the form asks for one.
final class AccountsRateNeeded extends AccountsFailure {
  /// Creates the failure.
  const new();

  @override
  String get code => 'accounts.rate_needed';
}

/// No such account, or not one the member may change.
final class AccountNotFound extends AccountsFailure {
  /// Creates the failure.
  const new();

  @override
  String get code => 'accounts.not_found';
}

/// Anything else. The original error is reported where it was caught.
final class AccountsUnknown extends AccountsFailure {
  /// Creates the failure with a machine-readable [detail].
  const new(this.detail);

  /// The error code or type. Never shown.
  final String detail;

  @override
  String get code => 'accounts.unknown';

  @override
  bool operator ==(Object other) =>
      other is AccountsUnknown && other.detail == detail;

  @override
  int get hashCode => Object.hash(AccountsUnknown, detail);

  @override
  String toString() => '$code($detail)';
}

/// Longest account name the app accepts, in characters.
const int maxAccountNameLength = 40;

/// Who may read an account (DATA_MODEL 2.4): its owner alone, or every
/// member when it is joint or shared. Sorted, so equal sets compare equal.
List<String> accountVisibleTo({
  required AccountScope scope,
  required String? ownerUid,
  required bool sharedWithPartner,
  required List<String> memberIds,
}) {
  final everyone = scope == AccountScope.joint || sharedWithPartner;
  final result = everyone || ownerUid == null
      ? {...memberIds, ?ownerUid}.toList()
      : [ownerUid];
  return result..sort();
}

/// The base-currency amount of an opening balance of [amountMinor] (signed)
/// in [currency], unsigned as `baseAmountMinor` is stored; null when it
/// needs a [rate] and has none. A zero balance writes no entry and needs no
/// rate, so an empty account in the other currency can always be added.
int? openingBaseAmount({
  required int amountMinor,
  required Currency currency,
  required Currency base,
  FxRate? rate,
}) {
  if (amountMinor == 0) return 0;
  return toBaseAmount(
    Money(amountMinor.abs(), currency),
    base,
    rate: rate,
  ).valueOrNull?.minorUnits;
}

/// The effect of a stored transaction on account [accountId], signed, in
/// the account's minor units (DATA_MODEL 3). Zero when it does not touch
/// the account.
int balanceEffect(Map<String, Object?> txn, String accountId) {
  final amount = txn['amountMinor'];
  if (amount is! int) return 0;
  final type = txn['type'];
  if (txn['toAccountId'] == accountId) {
    final to = txn['toAmountMinor'];
    return to is int ? to : amount;
  }
  if (txn['accountId'] != accountId) return 0;
  return switch (type) {
    'expense' || 'loan_given' || 'repayment_made' || 'transfer' => -amount,
    'income' || 'loan_taken' || 'repayment_received' => amount,
    'adjustment' => txn['adjustmentSign'] == -1 ? -amount : amount,
    _ => 0,
  };
}

/// Adds, edits, archives and shares accounts, and streams them.
///
/// Every list query includes `where('visibleTo', arrayContains: uid)`
/// (DATA_MODEL 4): a partner's private accounts are never read, so they
/// appear in no list and no total.
///
/// Writes are batches that work offline and return once Firestore has them
/// or once they are queued on the phone. Every call returns a [Result].
abstract interface class AccountsRepository {
  /// The signed-in member's uid, or null when not in a household.
  String? get viewerUid;

  /// Every account the member can see, archived ones too, in list order.
  /// Empty while not in a household.
  Stream<List<Account>> watchAccounts();

  /// The household's members.
  Stream<List<HouseholdMember>> watchMembers();

  /// The most recent USD/IQD rate the household entered (DATA_MODEL 2.13),
  /// or null when it has none.
  Stream<FxRate?> watchLatestRate();

  /// The newest entries on account [accountId] the member can see, newest
  /// first.
  Stream<List<AccountEntry>> watchEntries(String accountId);

  /// Adds an account from [draft], then its opening balance as an
  /// `adjustment` entry. Returns the new account's id.
  Future<Result<String, AccountsFailure>> create(AccountDraft draft);

  /// Renames account [id] and changes its kind.
  Future<Result<void, AccountsFailure>> edit(
    String id, {
    required String name,
    required AccountKind kind,
  });

  /// Archives or restores account [id].
  Future<Result<void, AccountsFailure>> setArchived(
    String id, {
    required bool archived,
  });

  /// Shares the member's personal account [id] with their partner, or
  /// makes it private again. Its history follows on the server
  /// (`/events/account-visibility`); until then the account shows
  /// "Sharing…".
  Future<Result<void, AccountsFailure>> setShared(
    String id, {
    required bool shared,
  });
}

/// The [AccountsRepository] for this run. Throws until the composition
/// root sets it.
final accountsRepositoryProvider = Provider<AccountsRepository>(
  (ref) => throw UnimplementedError(
    'accountsRepositoryProvider is set in bootstrap()',
  ),
  name: 'accountsRepositoryProvider',
);

/// Every account the member can see, as a stream.
final accountsProvider = StreamProvider<List<Account>>(
  (ref) => ref.watch(accountsRepositoryProvider).watchAccounts(),
  name: 'accountsProvider',
);

/// The household's members, as a stream.
final householdMembersProvider = StreamProvider<List<HouseholdMember>>(
  (ref) => ref.watch(accountsRepositoryProvider).watchMembers(),
  name: 'householdMembersProvider',
);

/// The household's latest USD/IQD rate, as a stream.
final latestRateProvider = StreamProvider<FxRate?>(
  (ref) => ref.watch(accountsRepositoryProvider).watchLatestRate(),
  name: 'latestRateProvider',
);

/// The entries of one account, as a stream.
final StreamProviderFamily<List<AccountEntry>, String> accountEntriesProvider =
    StreamProvider.autoDispose.family<List<AccountEntry>, String>(
      (ref, id) => ref.watch(accountsRepositoryProvider).watchEntries(id),
      name: 'accountEntriesProvider',
    );
