// The storage port of the transaction write path. The repository
// (`ledger_transactions_repository.dart`) decides what to write; a store
// reads the household cache and commits a [LedgerPlan] as one atomic
// batch. `FirestoreLedgerStore` and `MemoryLedgerStore` implement it.
import 'package:flutter/foundation.dart';
import 'package:xpense_app/data/transactions_repository.dart';
import 'package:xpense_shared/xpense_shared.dart';

/// Stands for "the server's time" in a planned field (`createdAt`,
/// `updatedAt`, `deletedAt`, `changedAt`): Firestore writes
/// `FieldValue.serverTimestamp()`, the memory store its clock.
final class ServerTime {
  const new _();
}

/// The one [ServerTime] value.
const ServerTime serverTime = ServerTime._();

/// Who is writing, in which household.
@immutable
final class LedgerScope {
  /// Creates the scope.
  const new({required this.householdId, required this.uid});

  /// The household id.
  final String householdId;

  /// The signed-in member's uid.
  final String uid;

  @override
  bool operator ==(Object other) =>
      other is LedgerScope &&
      other.householdId == householdId &&
      other.uid == uid;

  @override
  int get hashCode => Object.hash(householdId, uid);
}

/// The household fields a save needs (DATA_MODEL 2.2).
@immutable
final class LedgerHousehold {
  /// Creates the record.
  const new({
    required this.baseCurrency,
    required this.memberIds,
    this.rateKind = 'market',
  });

  /// The base currency; every `baseAmountMinor` is in it.
  final Currency baseCurrency;

  /// The members' uids (at most two).
  final List<String> memberIds;

  /// `official` or `market`: the label of the daily rate (D-16).
  final String rateKind;
}

/// An account as a save needs it (DATA_MODEL 2.4).
@immutable
final class LedgerAccount {
  /// Creates the record.
  const new({
    required this.id,
    required this.currency,
    required this.visibleTo,
    this.joint = false,
    this.ownerUid,
  });

  /// The account id.
  final String id;

  /// Its currency; every entry on it is in it.
  final Currency currency;

  /// Who can read it.
  final List<String> visibleTo;

  /// Whether it is joint.
  final bool joint;

  /// The owner of a personal account.
  final String? ownerUid;
}

/// A category's kind, `expense` or `income` (DATA_MODEL 2.6).
@immutable
final class LedgerCategory {
  /// Creates the record.
  const new({required this.id, this.kind});

  /// The category id.
  final String id;

  /// `expense` or `income`; null when the stored value is unknown.
  final String? kind;
}

/// A loan as a save needs it (DATA_MODEL 2.8).
@immutable
final class LedgerLoan {
  /// Creates the record.
  const new({required this.id, required this.currency});

  /// The loan id.
  final String id;

  /// Its currency; `outstandingMinor` is in it.
  final Currency currency;
}

/// The household's rate for a day (DATA_MODEL 2.13).
@immutable
final class DayRate {
  /// Creates the record.
  const new({required this.day, required this.rate, this.kind});

  /// The day the rate was entered for, `YYYY-MM-DD`.
  final String day;

  /// The rate.
  final FxRate rate;

  /// `official` or `market`, as entered; null when not recorded.
  final String? kind;
}

/// One document write of a plan.
@immutable
sealed class DocWrite {
  const new();
}

/// Creates transaction [id] with [fields].
final class TxnCreate extends DocWrite {
  /// Creates the write.
  const new(this.id, this.fields);

  /// The transaction id.
  final String id;

  /// Every stored field, `rev: 0` and `deletedAt: null` included.
  final Map<String, Object?> fields;
}

/// Updates transaction [id] with [fields], which advance `rev` to [rev]
/// on top of the version [prevRevId].
final class TxnUpdate extends DocWrite {
  /// Creates the write.
  const new(this.id, this.fields, {required this.rev, this.prevRevId});

  /// The transaction id.
  final String id;

  /// The changed fields, `rev` and the update stamps included.
  final Map<String, Object?> fields;

  /// The new `rev`. The store may refuse the write unless the stored one
  /// is `rev - 1`, as the rules do.
  final int rev;

  /// The stored `revId` this write was built on (null for an entry written
  /// before `revId` existed). The rules refuse the write unless the stored
  /// `revId` still equals it, so a queued write whose predecessor was
  /// refused is refused too.
  final String? prevRevId;
}

/// Appends revision [id] under transaction [txnId] (DATA_MODEL 2.5).
final class RevisionCreate extends DocWrite {
  /// Creates the write.
  const new(this.txnId, this.id, this.fields);

  /// The transaction id.
  final String txnId;

  /// The revision id (UUID v7).
  final String id;

  /// `{rev, before, changedBy, changedAt, reason}`.
  final Map<String, Object?> fields;
}

/// Everything one atomic batch writes: documents, then the balance and loan
/// increments the store turns into `FieldValue.increment` updates.
@immutable
final class LedgerPlan {
  /// Creates the plan.
  const new({required this.writes, required this.effects});

  /// The document writes, in order.
  final List<DocWrite> writes;

  /// The increments to `accounts/{id}.balanceMinor` and
  /// `loans/{id}.outstandingMinor`.
  final BalanceEffects effects;

  /// The transactions the plan creates or changes.
  List<String> get txnIds => [
    for (final w in writes)
      if (w case TxnCreate(:final id) || TxnUpdate(:final id)) id,
  ];
}

/// Why a store could not commit. The original error is reported by the
/// store.
enum StoreFailureKind {
  /// The rules refused it: no access, or `rev` moved on.
  denied,

  /// Anything else.
  unknown,
}

/// A failed commit.
@immutable
final class StoreFailure implements Failure {
  /// Creates the failure.
  const new(this.kind, [this.detail = '']);

  /// What kind.
  final StoreFailureKind kind;

  /// A machine-readable detail, such as the Firestore error code.
  final String detail;

  @override
  String get code => 'store.${kind.name}';

  @override
  bool operator ==(Object other) =>
      other is StoreFailure && other.kind == kind && other.detail == detail;

  @override
  int get hashCode => Object.hash(kind, detail);

  @override
  String toString() => 'StoreFailure(${kind.name} $detail)';
}

/// Reads the household cache and commits plans.
///
/// Reads come from the phone's cache first, so they work offline; a read
/// that finds nothing (or is refused) returns null. Only [commit] reports
/// failures.
abstract interface class LedgerStore {
  /// The current writer and household, or null when not in one.
  LedgerScope? get scope;

  /// Now, for `occurredAt` and ids.
  DateTime now();

  /// A new UUID v7.
  String newId();

  /// The household.
  Future<LedgerHousehold?> household();

  /// Account [id], if the member can see it.
  Future<LedgerAccount?> account(String id);

  /// Category [id].
  Future<LedgerCategory?> category(String id);

  /// Loan [id], if the member can see it.
  Future<LedgerLoan?> loan(String id);

  /// Whether person [id] exists and the member can see it.
  Future<bool> hasPerson(String id);

  /// The savings account of goal [id], or null when there is no such goal.
  Future<String?> goalAccount(String id);

  /// The rate for household-local [day]: that day's, or the most recent
  /// earlier one (DATA_MODEL 2.13).
  Future<DayRate?> rateOn(String day);

  /// Transaction [id] as stored, or null. [fresh] asks the server first
  /// (falling back to the cache offline), to re-apply after a conflict.
  Future<LedgerTransaction?> transaction(String id, {bool fresh = false});

  /// Completes once every batch queued on the phone has been answered by
  /// the server (Firestore's `waitForPendingWrites`); it waits while
  /// offline.
  Future<void> settle();

  /// Whether the server has revision [revId] of transaction [txnId], that
  /// is, whether the write that made it landed.
  Future<bool> hasRevision(String txnId, String revId);

  /// Writes [plan] as one atomic batch.
  ///
  /// Returns [WriteAck.queued] when the batch is on the phone but the
  /// server has not answered in time; if the server refuses it later,
  /// [onLateFailure] is called (after Firestore rolled it back locally).
  Future<Result<WriteAck, StoreFailure>> commit(
    LedgerPlan plan, {
    void Function(StoreFailure failure)? onLateFailure,
  });
}
