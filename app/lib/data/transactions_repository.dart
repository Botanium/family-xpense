// The transaction write path (DATA_MODEL 2.5, 3, 7; BACKLOG S2.1; D-10,
// D-12, D-13): the one place the phone writes money data.
//
// This file is the interface features import. The implementation is
// `write/ledger_transactions_repository.dart` over a `LedgerStore`: the
// Firestore store (`write/firestore_ledger_store.dart`) in real builds and
// the in-memory one (`write/memory_ledger_store.dart`) in fakes and tests.
// Only the composition root and tests name them.
//
// API contract (stable for WP-21, WP-22, WP-34 and later packages):
// - Every call returns a `Result`; nothing throws into the UI.
// - A write is one Firestore batch with `FieldValue.increment` on balances
//   and loan totals. It works offline: the call returns `queued` once the
//   batch is on the phone, and the entry shows from the cache at once.
// - Ids are client-generated UUID v7, so a retried offline save is the
//   same document.
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:xpense_shared/xpense_shared.dart';

/// Where an entry came from (`transactions.source`, DATA_MODEL 2.5).
enum EntrySource {
  /// Typed in Ask.
  chat('chat'),

  /// Spoken.
  voice('voice'),

  /// From a receipt photo.
  receipt('receipt'),

  /// The Add manually form, or an opening balance.
  manual('manual'),

  /// Posted from a recurring template.
  recurring('recurring'),

  /// Imported from a file.
  imported('import'),

  /// The iOS quick-capture shortcut.
  shortcut('shortcut');

  new(this.wire);

  /// The stored value.
  final String wire;

  /// The source for a stored [wire] value; unknown values read as [manual].
  static EntrySource fromWire(Object? wire) =>
      values.where((s) => s.wire == wire).firstOrNull ?? manual;
}

/// Whether an entry belongs to one member or to both (`whoScope`).
enum WhoScope {
  /// One member's; `whoUid` says whose.
  member,

  /// The household's.
  joint;

  /// The stored value.
  String get wire => name;

  /// Parses a stored value; unknown values read as [member].
  static WhoScope fromWire(Object? wire) => wire == 'joint' ? joint : member;
}

/// Why an entry was soft-deleted, as its revision records it.
enum DeleteReason {
  /// The member deleted it.
  delete,

  /// The member tapped Undo right after saving it.
  undo,
}

/// The exchange rate an entry was saved with (`transactions.fx`,
/// DATA_MODEL 1). It is never recomputed.
@immutable
final class StoredFx {
  /// Creates the record.
  const new({
    required this.pair,
    required this.pairRate,
    required this.source,
    required this.asOf,
  });

  /// Market-convention pair, `USD/IQD`.
  final String pair;

  /// The rate as a decimal string, for example `"1705"`.
  final String pairRate;

  /// `official` or `market` (the household's daily rate, D-16), or
  /// `manual` (typed for this entry).
  final String source;

  /// The household-local day the rate is for, `YYYY-MM-DD`.
  final String asOf;

  /// The parsed rate, or null when the stored values are malformed.
  FxRate? get rate => FxRate.parse(pair, pairRate).valueOrNull;

  @override
  bool operator ==(Object other) =>
      other is StoredFx &&
      other.pair == pair &&
      other.pairRate == pairRate &&
      other.source == source &&
      other.asOf == asOf;

  @override
  int get hashCode => Object.hash(pair, pairRate, source, asOf);

  @override
  String toString() => 'StoredFx($pair $pairRate $source $asOf)';
}

/// A stored transaction (DATA_MODEL 2.5), typed.
@immutable
final class LedgerTransaction {
  /// Creates a transaction.
  const new({
    required this.id,
    required this.type,
    required this.amountMinor,
    required this.currency,
    required this.accountId,
    required this.baseAmountMinor,
    required this.whoScope,
    required this.occurredAt,
    required this.occurredOn,
    required this.visibleTo,
    this.toAccountId,
    this.toAmountMinor,
    this.fx,
    this.adjustmentSign,
    this.categoryId,
    this.whoUid,
    this.title = '',
    this.note,
    this.personId,
    this.loanId,
    this.goalId,
    this.recurringId,
    this.groupId,
    this.source = EntrySource.manual,
    this.ai,
    this.deletedAt,
    this.deletePending = false,
    this.rev = 0,
    this.revId,
    this.createdBy,
  });

  /// The document id (UUID v7).
  final String id;

  /// The ledger type.
  final LedgerType type;

  /// The amount in minor units of [currency]; positive.
  final int amountMinor;

  /// The currency, always the [accountId] account's.
  final Currency currency;

  /// The account money leaves (or enters, for income-like types).
  final String accountId;

  /// The destination of a transfer.
  final String? toAccountId;

  /// What arrives in [toAccountId] when its currency differs; null means
  /// [amountMinor].
  final int? toAmountMinor;

  /// The amount in the household base currency, fixed at save time.
  final int baseAmountMinor;

  /// The rate used, when one was needed.
  final StoredFx? fx;

  /// `1` or `-1` for an `adjustment`; null for every other type.
  final int? adjustmentSign;

  /// The category (expense and income).
  final String? categoryId;

  /// The member it belongs to, when [whoScope] is `member`.
  final String? whoUid;

  /// Member or joint.
  final WhoScope whoScope;

  /// When it happened.
  final DateTime occurredAt;

  /// The household-local day, `YYYY-MM-DD`.
  final String occurredOn;

  /// Merchant or short label; empty when there is none.
  final String title;

  /// Free-text note.
  final String? note;

  /// The counterparty of a loan event.
  final String? personId;

  /// The loan it belongs to.
  final String? loanId;

  /// The goal of a savings move.
  final String? goalId;

  /// The recurring template that posted it.
  final String? recurringId;

  /// Entries saved together share this id.
  final String? groupId;

  /// Where it came from.
  final EntrySource source;

  /// How AI produced it (`ai` map), as stored.
  final Map<String, Object?>? ai;

  /// Who can read it: the union of its accounts' `visibleTo`.
  final List<String> visibleTo;

  /// When it was soft-deleted, once the server has stamped it.
  final DateTime? deletedAt;

  /// Whether it is soft-deleted on the phone and the server timestamp is
  /// still pending.
  final bool deletePending;

  /// Increments on every edit, delete and restore.
  final int rev;

  /// The id of this version (also its revision's id); every write names the
  /// version it was built on as `prevRevId` (DATA_MODEL 7). Null for an
  /// entry written before `revId` existed.
  final String? revId;

  /// Who first saved it.
  final String? createdBy;

  /// Whether it is soft-deleted.
  bool get deleted => deletedAt != null || deletePending;

  /// The fields that move balances, for the shared effect table.
  LedgerLine get line => LedgerLine(
    type: type,
    amountMinor: amountMinor,
    accountId: accountId,
    toAccountId: toAccountId,
    toAmountMinor: toAmountMinor,
    adjustmentSign: adjustmentSign ?? 1,
    loanId: loanId,
    deleted: deleted,
  );

  @override
  bool operator ==(Object other) =>
      other is LedgerTransaction &&
      other.id == id &&
      other.type == type &&
      other.amountMinor == amountMinor &&
      other.currency == currency &&
      other.accountId == accountId &&
      other.toAccountId == toAccountId &&
      other.toAmountMinor == toAmountMinor &&
      other.baseAmountMinor == baseAmountMinor &&
      other.fx == fx &&
      other.adjustmentSign == adjustmentSign &&
      other.categoryId == categoryId &&
      other.whoUid == whoUid &&
      other.whoScope == whoScope &&
      other.occurredAt == occurredAt &&
      other.occurredOn == occurredOn &&
      other.title == title &&
      other.note == note &&
      other.personId == personId &&
      other.loanId == loanId &&
      other.goalId == goalId &&
      other.recurringId == recurringId &&
      other.groupId == groupId &&
      other.source == source &&
      mapEquals(other.ai, ai) &&
      listEquals(other.visibleTo, visibleTo) &&
      other.deletedAt == deletedAt &&
      other.deletePending == deletePending &&
      other.rev == rev &&
      other.revId == revId &&
      other.createdBy == createdBy;

  @override
  int get hashCode => Object.hashAll([
    id,
    type,
    amountMinor,
    currency,
    accountId,
    toAccountId,
    toAmountMinor,
    baseAmountMinor,
    fx,
    adjustmentSign,
    categoryId,
    whoUid,
    whoScope,
    occurredAt,
    occurredOn,
    title,
    note,
    personId,
    loanId,
    goalId,
    recurringId,
    groupId,
    source,
    Object.hashAll(visibleTo),
    deletedAt,
    deletePending,
    rev,
    revId,
    createdBy,
  ]);

  // No title, note or amount: this lands in logs.
  @override
  String toString() => 'LedgerTransaction($id, ${type.wire}, rev $rev)';
}

/// What a draft cannot carry yet, keyed by draft id in
/// [TransactionsRepository.saveEntries].
@immutable
final class EntryExtras {
  /// Creates the extras.
  const new({this.toAmountMinor, this.adjustmentSign});

  /// What arrives in a transfer's destination when its currency differs,
  /// in that account's minor units. Null converts the amount with the rate
  /// (an edit keeps the stored one while the amount and accounts stay).
  final int? toAmountMinor;

  /// `-1` for an adjustment that lowers the balance, `1` for one that
  /// raises it; ignored for other types. Null is `1` on a save and keeps
  /// the stored sign on an edit.
  final int? adjustmentSign;

  @override
  bool operator ==(Object other) =>
      other is EntryExtras &&
      other.toAmountMinor == toAmountMinor &&
      other.adjustmentSign == adjustmentSign;

  @override
  int get hashCode => Object.hash(toAmountMinor, adjustmentSign);
}

/// Whether a write has reached the server.
enum WriteAck {
  /// Firestore acknowledged it.
  synced,

  /// It is on the phone and will sync when the connection is back. If the
  /// server then refuses it, Firestore rolls it back on the phone and
  /// [TransactionsRepository.lateFailures] reports it.
  queued,
}

/// The result of [TransactionsRepository.saveEntries].
@immutable
final class SavedEntries {
  /// Creates the result.
  const new({required this.groupId, required this.txnIds, required this.ack});

  /// The id stored as `groupId` on every entry of the save.
  final String groupId;

  /// The new transaction ids, in draft order.
  final List<String> txnIds;

  /// Whether the batch reached the server.
  final WriteAck ack;

  @override
  bool operator ==(Object other) =>
      other is SavedEntries &&
      other.groupId == groupId &&
      listEquals(other.txnIds, txnIds) &&
      other.ack == ack;

  @override
  int get hashCode => Object.hash(groupId, Object.hashAll(txnIds), ack);

  @override
  String toString() => 'SavedEntries($groupId, ${txnIds.length}, ${ack.name})';
}

/// What is wrong with one draft, for [EntryInvalid].
enum EntryIssue {
  /// The intent records no money (`question`, `command`, `other`).
  notMoney,

  /// A required field is empty or still unanswered.
  missing,

  /// A field names something the household cache does not have.
  unknownReference,

  /// A field holds a value it cannot hold (a rate, a sign, a date).
  malformed,

  /// The amount is outside `1 … 10^12` minor units, or converts to zero.
  amountOutOfRange,

  /// The currency differs from the account's, or from the loan's.
  currencyMismatch,

  /// A transfer to the account it leaves.
  sameAccount,

  /// An expense category on income, or the reverse.
  wrongCategoryKind,

  /// `who: partner` before the partner has joined.
  noPartner,

  /// The title is over 80 characters or the note over 500.
  tooLong,
}

/// Why a write did not happen. Carries a stable [code], never a
/// user-facing string; the screen localises from it.
@immutable
sealed class TransactionsFailure implements Failure {
  const new();

  @override
  bool operator ==(Object other) => other.runtimeType == runtimeType;

  @override
  int get hashCode => runtimeType.hashCode;

  @override
  String toString() => code;
}

/// Not in a household, or the rules refused the write (the member cannot
/// see an account it touches).
final class TransactionsNotAllowed extends TransactionsFailure {
  /// Creates the failure.
  const new();

  @override
  String get code => 'transactions.not_allowed';
}

/// A draft cannot be saved as it is. Nothing was written.
final class EntryInvalid extends TransactionsFailure {
  /// Creates the failure for [field] of draft [draftId].
  const new({required this.draftId, required this.field, required this.issue});

  /// The draft's id.
  final String draftId;

  /// The draft field, such as `categoryId`.
  final String field;

  /// What is wrong.
  final EntryIssue issue;

  @override
  String get code => 'transactions.invalid';

  @override
  bool operator ==(Object other) =>
      other is EntryInvalid &&
      other.draftId == draftId &&
      other.field == field &&
      other.issue == issue;

  @override
  int get hashCode => Object.hash(EntryInvalid, draftId, field, issue);

  @override
  String toString() => '$code($draftId.$field: ${issue.name})';
}

/// A draft needs the USD/IQD rate and the household has none for its day
/// or earlier (D-16): the screen asks for it. Nothing was written.
final class EntryRateNeeded extends TransactionsFailure {
  /// Creates the failure for draft [draftId], converting [from] to [to].
  const new({required this.draftId, required this.from, required this.to});

  /// The draft's id.
  final String draftId;

  /// The source currency code.
  final String from;

  /// The target currency code.
  final String to;

  @override
  String get code => 'transactions.rate_needed';

  @override
  bool operator ==(Object other) =>
      other is EntryRateNeeded &&
      other.draftId == draftId &&
      other.from == from &&
      other.to == to;

  @override
  int get hashCode => Object.hash(EntryRateNeeded, draftId, from, to);
}

/// More drafts than one save takes ([maxEntriesPerSave]), drafts touching
/// more accounts and loans than one batch can check
/// ([maxAccountsPerSave]), or none.
final class TooManyEntries extends TransactionsFailure {
  /// Creates the failure.
  const new();

  @override
  String get code => 'transactions.too_many';
}

/// No such transaction, or not one the member can see.
final class TransactionNotFound extends TransactionsFailure {
  /// Creates the failure.
  const new();

  @override
  String get code => 'transactions.not_found';
}

/// The transaction is deleted: restore it before editing, or it was
/// already deleted.
final class TransactionDeleted extends TransactionsFailure {
  /// Creates the failure.
  const new();

  @override
  String get code => 'transactions.deleted';
}

/// A restore of an entry that is not deleted.
final class TransactionNotDeleted extends TransactionsFailure {
  /// Creates the failure.
  const new();

  @override
  String get code => 'transactions.not_deleted';
}

/// The partner changed the entry at the same moment and re-applying on
/// top of their change failed too. Nothing was written.
final class TransactionConflict extends TransactionsFailure {
  /// Creates the failure.
  const new();

  @override
  String get code => 'transactions.conflict';
}

/// Anything else. The original error is reported where it was caught.
final class TransactionsUnknown extends TransactionsFailure {
  /// Creates the failure with a machine-readable [detail].
  const new(this.detail);

  /// The error code or type. Never shown.
  final String detail;

  @override
  String get code => 'transactions.unknown';

  @override
  bool operator ==(Object other) =>
      other is TransactionsUnknown && other.detail == detail;

  @override
  int get hashCode => Object.hash(TransactionsUnknown, detail);

  @override
  String toString() => '$code($detail)';
}

/// A queued write the server refused after the call had returned
/// [WriteAck.queued]. Firestore has already rolled it back on the phone.
@immutable
final class LateWriteFailure {
  /// Creates the report.
  const new({required this.txnIds, required this.failure});

  /// The transactions the write touched.
  final List<String> txnIds;

  /// Why it was refused.
  final TransactionsFailure failure;

  @override
  String toString() => 'LateWriteFailure(${txnIds.length}, $failure)';
}

/// The most drafts one save takes: a surface's limit (A2UI_CATALOG 9).
const int maxEntriesPerSave = maxDraftsPerSurface;

/// The most distinct accounts and loans one save may touch.
///
/// The rules read every account a new entry names (the household once
/// more), and a batch may read at most 20 documents; loans cost no read but
/// are counted too, for headroom. Above this a save is refused with
/// [TooManyEntries] rather than split, so it stays all or nothing
/// (Codex review, PR #35).
const int maxAccountsPerSave = 15;

/// The single write path for money entries (D-10).
///
/// - [saveEntries] checks every draft against the household cache, fixes
///   its base amount with the stored rate (DATA_MODEL 1), and writes all of
///   them plus their balance and loan increments in one batch: either all
///   are saved or none.
/// - [editEntry] writes a revision and applies only the difference.
/// - [deleteEntry] soft-deletes (`deletedAt`) with reversing increments;
///   [restoreEntry] undoes it.
///
/// `runTransaction` is never used: it fails offline (D-13). Two partners
/// editing the same entry is settled by `rev` (DATA_MODEL 7): the losing
/// write is re-applied once on top of the winner's.
abstract interface class TransactionsRepository {
  /// Validates [drafts] and saves them as one group.
  ///
  /// [source] defaults to `chat` for drafts with an `origin` and `manual`
  /// otherwise. [extras] carries, by draft id, what an [EntryDraft] cannot
  /// hold yet (a typed arriving amount, an adjustment's sign).
  ///
  /// A draft's `fx` (pair and rate) is used as given, as a `manual` rate
  /// unless it names its source; its `baseAmountMinor` is ignored and
  /// recomputed. Without one, the household's rate for the entry's day (or
  /// the latest earlier day) is used and labelled with the household's
  /// `rateKind` (`market` by default, D-16).
  Future<Result<SavedEntries, TransactionsFailure>> saveEntries(
    List<EntryDraft> drafts, {
    EntrySource? source,
    Map<String, EntryExtras> extras = const {},
  });

  /// Replaces the content of transaction [txnId] with [draft] (its `id` is
  /// ignored), writes a revision with the fields' old values, and applies
  /// the difference to balances and loan totals.
  ///
  /// The entry keeps its source, group, AI record and creator. It keeps
  /// the rate it was saved with unless its day changes or [draft] names a
  /// rate. Nothing changed writes nothing.
  Future<Result<WriteAck, TransactionsFailure>> editEntry(
    String txnId,
    EntryDraft draft, {
    EntryExtras extras = const EntryExtras(),
  });

  /// Soft-deletes transaction [txnId] and reverses its effect.
  Future<Result<WriteAck, TransactionsFailure>> deleteEntry(
    String txnId, {
    DeleteReason reason = DeleteReason.delete,
  });

  /// Soft-deletes every entry of a save, for the Undo toast. Already
  /// deleted entries are skipped.
  Future<Result<WriteAck, TransactionsFailure>> undoSave(SavedEntries saved);

  /// Restores a soft-deleted transaction and re-applies its effect.
  Future<Result<WriteAck, TransactionsFailure>> restoreEntry(String txnId);

  /// Queued writes the server refused later.
  Stream<LateWriteFailure> get lateFailures;
}

/// The [TransactionsRepository] for this run. Throws until the composition
/// root sets it.
final transactionsRepositoryProvider = Provider<TransactionsRepository>(
  (ref) => throw UnimplementedError(
    'transactionsRepositoryProvider is set in bootstrap()',
  ),
  name: 'transactionsRepositoryProvider',
);
