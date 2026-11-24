// The transaction write path over a `LedgerStore` (DATA_MODEL 1, 2.5, 3,
// 7). The store only reads and commits; every decision is made here, so
// the in-memory store tests all of it and the Firestore store stays thin.
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:xpense_app/data/mappers/transaction_mapper.dart';
import 'package:xpense_app/data/transactions_repository.dart';
import 'package:xpense_app/data/write/ledger_store.dart';
import 'package:xpense_app/services/write_journal.dart';
import 'package:xpense_shared/xpense_shared.dart';

/// Entries a delete or undo writes per batch. Each revision costs the
/// rules a `getAfter`, and a batch may make at most 20 document reads.
const int maxRevisionsPerBatch = 8;

/// [TransactionsRepository] over [LedgerStore].
final class LedgerTransactionsRepository implements TransactionsRepository {
  /// Creates the repository. [journal] keeps queued edits, deletes and
  /// restores across app restarts (see [resumePending]); without one they
  /// are kept in memory only.
  new(this._store, {WriteJournal? journal})
    : _journal = journal ?? MemoryWriteJournal();

  final LedgerStore _store;
  final WriteJournal _journal;
  final StreamController<LateWriteFailure> _late =
      StreamController<LateWriteFailure>.broadcast();

  @override
  Stream<LateWriteFailure> get lateFailures => _late.stream;

  /// Stops reporting late failures.
  Future<void> dispose() => _late.close();

  // ---------------------------------------------------------------- save

  @override
  Future<Result<SavedEntries, TransactionsFailure>> saveEntries(
    List<EntryDraft> drafts, {
    EntrySource? source,
    Map<String, EntryExtras> extras = const {},
  }) async {
    if (drafts.isEmpty || drafts.length > maxEntriesPerSave) {
      return const Err(TooManyEntries());
    }
    final scope = _store.scope;
    final household = await _store.household();
    if (scope == null || household == null) {
      return const Err(TransactionsNotAllowed());
    }
    final groupId = _store.newId();
    final txns = <LedgerTransaction>[];
    for (final draft in drafts) {
      final resolved = await _resolve(
        draft,
        scope: scope,
        household: household,
        extras: extras[_draftId(draft)] ?? const EntryExtras(),
        source:
            source ??
            (draft.toJson()['origin'] == null
                ? EntrySource.manual
                : EntrySource.chat),
        groupId: groupId,
      );
      switch (resolved) {
        case Ok(:final value):
          txns.add(value);
        case Err(:final failure):
          return Err(failure);
      }
    }
    final plan = LedgerPlan(
      writes: [
        for (final t in txns)
          TxnCreate(t.id, {
            ...transactionContent(t),
            'deletedAt': null,
            'rev': 0,
            'revId': _store.newId(),
            'prevRevId': null,
            ..._createStamps(scope.uid),
          }),
      ],
      effects: txns.fold(
        BalanceEffects.none,
        (sum, t) => sum + effectDelta(null, t.line),
      ),
    );
    final touched = {
      for (final t in txns) ...[t.accountId, ?t.toAccountId, ?t.loanId],
    };
    if (touched.length > maxAccountsPerSave) {
      return const Err(TooManyEntries());
    }
    final ids = [for (final t in txns) t.id];
    final committed = await _store.commit(
      plan,
      onLateFailure: (f) => _reportLate(ids, _fromStore(f)),
    );
    return switch (committed) {
      Ok(:final value) => Ok(
        SavedEntries(groupId: groupId, txnIds: ids, ack: value),
      ),
      Err(:final failure) => Err(_fromStore(failure)),
    };
  }

  // ------------------------------------------------- edit, delete, restore

  @override
  Future<Result<WriteAck, TransactionsFailure>> editEntry(
    String txnId,
    EntryDraft draft, {
    EntryExtras extras = const EntryExtras(),
  }) => _revise(txnId, _EditOp(draft.toJson(), extras));

  @override
  Future<Result<WriteAck, TransactionsFailure>> deleteEntry(
    String txnId, {
    DeleteReason reason = DeleteReason.delete,
  }) => _revise(txnId, _DeleteOp(reason));

  @override
  Future<Result<WriteAck, TransactionsFailure>> restoreEntry(String txnId) =>
      _revise(txnId, const _RestoreOp());

  /// Re-applies the edits, deletes and restores an earlier run queued that
  /// the server refused (the partner changed the entry first), once the
  /// queue has reached the server; reports through [lateFailures] what
  /// cannot be re-applied. The composition root calls it once a household
  /// is known. Firestore keeps a queued batch across a restart, but not the
  /// callback that would re-apply it (Codex review, PR #35). Only the
  /// signed-in member's records in the current household are resumed.
  Future<void> resumePending() async {
    final previous = _resuming;
    final done = Completer<void>();
    _resuming = done.future;
    try {
      await previous;
      await _resume();
    } finally {
      done.complete();
    }
  }

  /// The running [resumePending], so two never overlap.
  Future<void>? _resuming;

  Future<void> _resume() async {
    final scope = _store.scope;
    if (scope == null) return;
    // Another member's or household's records stay until their owner signs
    // in on this phone again (Codex review, PR #35).
    final pending = [
      for (final e in _journal.entries)
        if (e.householdId == scope.householdId && e.uid == scope.uid) e,
    ];
    if (pending.isEmpty) return;
    await _store.settle();
    for (final entry in pending) {
      // Handled in this run already.
      if (!_journal.entries.any((e) => e.revId == entry.revId)) continue;
      // The record is removed only once the change is on the server or its
      // re-apply has taken it over, so a stop in between loses nothing.
      final op = _Op.fromJournal(entry.op, entry.payload);
      if (op == null || await _store.hasRevision(entry.txnId, entry.revId)) {
        await _journal.remove(entry.revId);
        continue;
      }
      await _lateRetry(
        entry.txnId,
        op,
        staleVersion: entry.baseVersion,
        replaces: entry.revId,
      );
    }
  }

  /// What [op] changes on [prev], or null when it changes nothing.
  Future<Result<_Revision?, TransactionsFailure>> _build(
    _Op op,
    LedgerTransaction prev,
    LedgerScope scope,
    LedgerHousehold household,
  ) async {
    switch (op) {
      case _EditOp(:final draft, :final extras):
        if (prev.deleted) return const Err(TransactionDeleted());
        final resolved = await _resolve(
          EntryDraft.fromJson(draft),
          scope: scope,
          household: household,
          extras: extras,
          source: prev.source,
          groupId: prev.groupId,
          previous: prev,
        );
        return switch (resolved) {
          Err(:final failure) => Err(failure),
          Ok(value: final next) => Ok(_editOf(prev, next)),
        };
      case _DeleteOp(:final reason):
        if (prev.deleted) return const Err(TransactionDeleted());
        return Ok(_deletionOf(prev, reason));
      case _RestoreOp():
        if (!prev.deleted) return const Err(TransactionNotDeleted());
        return Ok(
          _Revision(
            fields: const {'deletedAt': null},
            before: {'deletedAt': prev.deletedAt},
            reason: RevisionReason.restore,
            after: prev.line.withDeleted(deleted: false),
          ),
        );
    }
  }

  PendingRevision _pending(
    LedgerScope scope,
    LedgerTransaction prev,
    String revId,
    _Op op,
  ) => PendingRevision(
    householdId: scope.householdId,
    uid: scope.uid,
    txnId: prev.id,
    revId: revId,
    baseVersion: _version(prev),
    op: op.name,
    payload: op.payload,
  );

  @override
  Future<Result<WriteAck, TransactionsFailure>> undoSave(
    SavedEntries saved,
  ) async {
    final scope = _store.scope;
    if (scope == null) return const Err(TransactionsNotAllowed());
    var ack = WriteAck.synced;
    final ids = saved.txnIds;
    for (var start = 0; start < ids.length; start += maxRevisionsPerBatch) {
      final chunk = ids.skip(start).take(maxRevisionsPerBatch).toList();
      final result = await _undoChunk(chunk, scope);
      switch (result) {
        case Ok(:final value):
          if (value == WriteAck.queued) ack = WriteAck.queued;
        case Err(:final failure):
          return Err(failure);
      }
    }
    return Ok(ack);
  }

  /// Deletes [ids] in one batch; on a refusal, one by one, so a conflict on
  /// one entry is re-applied without holding up the rest.
  Future<Result<WriteAck, TransactionsFailure>> _undoChunk(
    List<String> ids,
    LedgerScope scope,
  ) async {
    const op = _DeleteOp(DeleteReason.undo);
    final writes = <DocWrite>[];
    var effects = BalanceEffects.none;
    final touched = <PendingRevision>[];
    for (final id in ids) {
      final prev = await _store.transaction(id);
      if (prev == null) return const Err(TransactionNotFound());
      if (prev.deleted) continue;
      final revision = _deletionOf(prev, DeleteReason.undo);
      final revId = _store.newId();
      writes.addAll(_revisionWrites(prev, revision, scope.uid, revId));
      effects = effects + effectDelta(prev.line, revision.after);
      touched.add(_pending(scope, prev, revId, op));
    }
    if (writes.isEmpty) return const Ok(WriteAck.synced);
    for (final p in touched) {
      await _journal.put(p);
    }
    Future<void> forget() async {
      for (final p in touched) {
        await _journal.remove(p.revId);
      }
    }

    final committed = await _store.commit(
      LedgerPlan(writes: writes, effects: effects),
      onLateFailure: (f) {
        // Each re-apply takes its record over.
        for (final p in touched) {
          unawaited(
            _lateRetry(
              p.txnId,
              op,
              staleVersion: p.baseVersion,
              replaces: p.revId,
            ),
          );
        }
      },
    );
    switch (committed) {
      case Ok(value: WriteAck.queued):
        return const Ok(WriteAck.queued);
      case Ok(:final value):
        await forget();
        return Ok(value);
      case Err(:final failure) when failure.kind == StoreFailureKind.denied:
        var ack = WriteAck.synced;
        for (final p in touched) {
          final one = await _revise(p.txnId, op, replaces: p.revId);
          switch (one) {
            case Ok(:final value):
              if (value == WriteAck.queued) ack = WriteAck.queued;
            case Err(failure: TransactionDeleted()):
              break;
            case Err(:final failure):
              return Err(failure);
          }
        }
        return Ok(ack);
      case Err(:final failure):
        await forget();
        return Err(_fromStore(failure));
    }
  }

  _Revision _deletionOf(LedgerTransaction prev, DeleteReason reason) =>
      _Revision(
        fields: const {'deletedAt': serverTime},
        before: const {'deletedAt': null},
        reason: switch (reason) {
          DeleteReason.delete => RevisionReason.delete,
          DeleteReason.undo => RevisionReason.undo,
        },
        after: prev.line.withDeleted(deleted: true),
      );

  /// The revision that turns [prev] into [next], or null when nothing
  /// changed.
  _Revision? _editOf(LedgerTransaction prev, LedgerTransaction next) {
    final old = transactionContent(prev);
    final now = transactionContent(next);
    final changed = [
      for (final key in transactionContentFields)
        if (!_deepEquals(old[key], now[key])) key,
    ];
    if (changed.isEmpty) return null;
    return _Revision(
      fields: {for (final k in changed) k: now[k]},
      before: {for (final k in changed) k: old[k]},
      reason: RevisionReason.edit,
      after: next.line,
    );
  }

  /// Reads [txnId], lets [op] decide the change, and commits it with a
  /// revision and the balance difference.
  ///
  /// When the rules refuse it because the entry moved on (the partner saved
  /// first, DATA_MODEL 7), the change is built again once on top of the
  /// server's version. A queued write the server refuses later is
  /// re-applied the same way, in the background.
  ///
  /// [replaces] is the journal record of the change this call re-applies.
  /// It is removed only once this call has journaled its own record or
  /// reached a final outcome, never before: a stop in between leaves it for
  /// the next [resumePending] (Codex review, PR #35).
  Future<Result<WriteAck, TransactionsFailure>> _revise(
    String txnId,
    _Op op, {
    bool fresh = false,
    String? staleVersion,
    String? replaces,
  }) async {
    Future<Result<WriteAck, TransactionsFailure>> settled(
      Result<WriteAck, TransactionsFailure> outcome,
    ) async {
      if (replaces != null) await _journal.remove(replaces);
      return outcome;
    }

    final scope = _store.scope;
    if (scope == null) return const Err(TransactionsNotAllowed());
    final prev = await _store.transaction(txnId, fresh: fresh);
    if (prev == null) return await settled(const Err(TransactionNotFound()));
    final household = await _store.household();
    if (household == null) return const Err(TransactionsNotAllowed());
    if (staleVersion != null && _version(prev) == staleVersion) {
      // The server has the version this write was built on, so the refusal
      // was not a conflict.
      return await settled(const Err(TransactionsNotAllowed()));
    }
    final built = await _build(op, prev, scope, household);
    final _Revision revision;
    switch (built) {
      case Err(:final failure):
        return await settled(Err(failure));
      case Ok(value: null):
        return await settled(const Ok(WriteAck.synced));
      case Ok(:final _Revision value):
        revision = value;
    }
    final revId = _store.newId();
    final plan = LedgerPlan(
      writes: _revisionWrites(prev, revision, scope.uid, revId),
      effects: effectDelta(prev.line, revision.after),
    );
    final retried = staleVersion != null;
    // Kept until the server has it, so a restart cannot lose the change;
    // only then is the record it takes over removed.
    await _journal.put(_pending(scope, prev, revId, op));
    if (replaces != null) await _journal.remove(replaces);
    final committed = await _store.commit(
      plan,
      onLateFailure: (f) async {
        if (!retried && f.kind == StoreFailureKind.denied) {
          // The re-apply takes the record over.
          unawaited(
            _lateRetry(
              txnId,
              op,
              staleVersion: _version(prev),
              replaces: revId,
            ),
          );
        } else {
          await _journal.remove(revId);
          _reportLate([txnId], _fromStore(f));
        }
      },
    );
    switch (committed) {
      case Ok(value: WriteAck.queued):
        return const Ok(WriteAck.queued);
      case Ok(:final value):
        await _journal.remove(revId);
        return Ok(value);
      case Err(:final failure)
          when !retried && failure.kind == StoreFailureKind.denied:
        return await _revise(
          txnId,
          op,
          fresh: true,
          staleVersion: _version(prev),
          replaces: revId,
        );
      case Err(:final failure) when retried:
        await _journal.remove(revId);
        return Err(
          failure.kind == StoreFailureKind.denied
              ? const TransactionConflict()
              : _fromStore(failure),
        );
      case Err(:final failure):
        await _journal.remove(revId);
        return Err(_fromStore(failure));
    }
  }

  /// Re-applies a queued change the server refused, on top of the server's
  /// version, and reports it when that fails too.
  ///
  /// Re-applies of one entry run one after another, in the order the queue
  /// was refused: an edit then a delete queued offline are both refused
  /// when the partner wrote first (each names its predecessor), and the
  /// delete must be rebuilt on top of the re-applied edit.
  Future<void> _lateRetry(
    String txnId,
    _Op op, {
    String? staleVersion,
    String? replaces,
  }) async {
    final before = _lateRetries[txnId]?.future;
    final done = Completer<void>();
    _lateRetries[txnId] = done;
    try {
      await before;
      await _reapply(
        txnId,
        op,
        staleVersion: staleVersion ?? '',
        replaces: replaces,
      );
    } finally {
      done.complete();
      if (identical(_lateRetries[txnId], done)) _lateRetries.remove(txnId);
    }
  }

  final Map<String, Completer<void>> _lateRetries = {};

  Future<void> _reapply(
    String txnId,
    _Op op, {
    required String staleVersion,
    String? replaces,
  }) async {
    final again = await _revise(
      txnId,
      op,
      fresh: true,
      staleVersion: staleVersion,
      replaces: replaces,
    );
    switch (again) {
      case Ok():
      case Err(failure: TransactionDeleted() || TransactionNotDeleted()):
        break;
      case Err(:final failure):
        _reportLate([txnId], failure);
    }
  }

  /// The update and revision that write [revision] as version [revId];
  /// the rules accept it only on top of the version it names as
  /// `prevRevId` (DATA_MODEL 7).
  List<DocWrite> _revisionWrites(
    LedgerTransaction prev,
    _Revision revision,
    String uid,
    String revId,
  ) {
    final rev = prev.rev + 1;
    return [
      TxnUpdate(
        prev.id,
        {
          ...revision.fields,
          'rev': rev,
          'revId': revId,
          'prevRevId': prev.revId,
          ..._updateStamps(uid),
        },
        rev: rev,
        prevRevId: prev.revId,
      ),
      RevisionCreate(prev.id, revId, {
        'rev': rev,
        'before': revision.before,
        'changedBy': uid,
        'changedAt': serverTime,
        'reason': revision.reason.name,
      }),
    ];
  }

  // ------------------------------------------------------- draft → entry

  /// Checks [draft] against the household cache and turns it into the
  /// transaction to store (DATA_MODEL 1, 2.5). [previous] is the stored
  /// version when editing.
  Future<Result<LedgerTransaction, TransactionsFailure>> _resolve(
    EntryDraft draft, {
    required LedgerScope scope,
    required LedgerHousehold household,
    required EntryExtras extras,
    required EntrySource source,
    required String? groupId,
    LedgerTransaction? previous,
  }) async {
    final draftId = _draftId(draft);
    Err<LedgerTransaction, TransactionsFailure> invalid(
      String field,
      EntryIssue issue,
    ) => Err(EntryInvalid(draftId: draftId, field: field, issue: issue));

    final json = draft.toJson();
    final intent = CaptureIntent.tryParse('${json['intent']}');
    if (intent != null && !intent.recordsMoney) {
      return invalid('intent', EntryIssue.notMoney);
    }
    // Shape next: an EntryDraft's getters throw on a wrongly typed field.
    final check = checkDraft(json, const HouseholdRefs());
    final malformed = check.issues.whereType<MalformedField>().firstOrNull;
    if (malformed != null) {
      final field = malformed.field;
      final tooLong =
          (field == 'title' || field == 'note') && json[field] is String;
      return invalid(
        field,
        tooLong ? EntryIssue.tooLong : EntryIssue.malformed,
      );
    }
    final type = intent?.ledgerType;
    if (type == null) return invalid('intent', EntryIssue.malformed);
    // The shared checker lists a transfer to its own account as an
    // unanswered destination; the write path says exactly what is wrong.
    if (type == LedgerType.transfer &&
        draft.toAccountId != null &&
        draft.toAccountId == draft.accountId) {
      return invalid('toAccountId', EntryIssue.sameAccount);
    }
    // The currency and the day can be derived; everything else missing
    // (or still unanswered) stops the save.
    final missing = check.missing
        .where((f) => f != 'currency' && f != 'occurredOn')
        .firstOrNull;
    if (missing != null) return invalid(missing, EntryIssue.missing);

    final amount = draft.amountMinor!;
    if (amount < 1 || amount > maxDraftAmountMinor) {
      return invalid('amountMinor', EntryIssue.amountOutOfRange);
    }
    final account = await _store.account(draft.accountId!);
    if (account == null) {
      return invalid('accountId', EntryIssue.unknownReference);
    }
    // An account holds only its own currency (DATA_MODEL 1), but it can
    // pay in the other: "10000 iqd dinner" from a dollar account. The
    // entry is then stored in the account's currency, the amount converted
    // at the rate for its date (below), and `fx` records that rate.
    final spoken = draft.currency == null
        ? account.currency
        : Currency.tryParse(draft.currency!);
    if (spoken == null) {
      return invalid('currency', EntryIssue.currencyMismatch);
    }
    final currency = account.currency;
    final converts = spoken != currency;

    // A goal's account is the destination of a savings move.
    String? goalAccount;
    if (draft.goalId case final goalId?) {
      goalAccount = await _store.goalAccount(goalId);
      if (goalAccount == null) {
        return invalid('goalId', EntryIssue.unknownReference);
      }
    }
    LedgerAccount? to;
    if (type == LedgerType.transfer) {
      final toId = draft.toAccountId ?? goalAccount;
      if (toId == null) return invalid('toAccountId', EntryIssue.missing);
      if (toId == account.id) {
        return invalid('toAccountId', EntryIssue.sameAccount);
      }
      to = await _store.account(toId);
      if (to == null) {
        return invalid('toAccountId', EntryIssue.unknownReference);
      }
    }

    if (draft.categoryId case final categoryId?) {
      final category = await _store.category(categoryId);
      if (category == null) {
        return invalid('categoryId', EntryIssue.unknownReference);
      }
      final kind = category.kind;
      if ((type == LedgerType.expense || type == LedgerType.income) &&
          kind != null &&
          kind != type.wire) {
        return invalid('categoryId', EntryIssue.wrongCategoryKind);
      }
    }
    if (draft.personId case final personId?) {
      if (!await _store.hasPerson(personId)) {
        return invalid('personId', EntryIssue.unknownReference);
      }
    }
    if (draft.loanId case final loanId?) {
      final loan = await _store.loan(loanId);
      if (loan == null) return invalid('loanId', EntryIssue.unknownReference);
      if (loan.currency != currency) {
        return invalid('loanId', EntryIssue.currencyMismatch);
      }
    }

    // Who: `me` is the writer; with no answer, a joint account's entry is
    // joint and a personal one belongs to its owner.
    final String? whoUid;
    final WhoScope whoScope;
    switch (draft.who) {
      case 'joint':
        (whoUid, whoScope) = (null, WhoScope.joint);
      case 'partner':
        final partner = household.memberIds
            .where((m) => m != scope.uid)
            .firstOrNull;
        if (partner == null) return invalid('who', EntryIssue.noPartner);
        (whoUid, whoScope) = (partner, WhoScope.member);
      case 'me':
        (whoUid, whoScope) = (scope.uid, WhoScope.member);
      default:
        (whoUid, whoScope) = account.joint
            ? (null, WhoScope.joint)
            : (account.ownerUid ?? scope.uid, WhoScope.member);
    }

    final now = _store.now();
    final occurredOn = draft.occurredOn ?? householdDay(now);
    final day = DateTime.tryParse(occurredOn);
    if (day == null || householdDay(day) != occurredOn) {
      return invalid('occurredOn', EntryIssue.malformed);
    }
    final time = switch (draft.occurredTime) {
      null => null,
      final hm => _parseTime(hm),
    };
    if (draft.occurredTime != null && time == null) {
      return invalid('occurredTime', EntryIssue.malformed);
    }
    final DateTime occurredAt;
    final kept = previous?.occurredAt.toLocal();
    if (time != null &&
        kept != null &&
        previous!.occurredOn == occurredOn &&
        kept.hour == time.$1 &&
        kept.minute == time.$2) {
      // A prefilled HH:mm that was not changed keeps the stored instant,
      // seconds included (Codex review, PR #35).
      occurredAt = previous.occurredAt;
    } else if (time != null) {
      occurredAt = DateTime(day.year, day.month, day.day, time.$1, time.$2);
    } else if (previous != null && previous.occurredOn == occurredOn) {
      occurredAt = previous.occurredAt;
    } else if (occurredOn == householdDay(now)) {
      occurredAt = now;
    } else {
      occurredAt = DateTime(day.year, day.month, day.day, 12);
    }

    final title = (draft.title ?? draft.personName ?? '').trim();
    if (title.length > maxTitleLength) {
      return invalid('title', EntryIssue.tooLong);
    }
    final note = switch (draft.note?.trim()) {
      null || '' => null,
      final n => n,
    };
    if (note != null && note.length > maxNoteLength) {
      return invalid('note', EntryIssue.tooLong);
    }

    // FX (DATA_MODEL 1): a rate is needed when the entry is not in the base
    // currency, or when a transfer between currencies has no typed arriving
    // amount. The base amount is rounded half-even, once, and stored.
    final base = household.baseCurrency;
    final toCurrency = to?.currency;
    final crossTransfer = toCurrency != null && toCurrency != currency;
    // An arriving amount the caller types overrides; otherwise an edit that
    // keeps the amount, the accounts and the rate keeps the stored arriving
    // amount and the quote it was converted with (Codex review, PR #35).
    var toAmount = crossTransfer ? extras.toAmountMinor : null;
    var toSource = toAmount == null ? null : ToAmountSource.entered;
    StoredFx? retainedFx;
    // A stored arriving amount converted with the day's rate is converted
    // again when the day changes; a typed one is kept. The stored
    // `toAmountSource` says which (Codex review, PR #35); an entry saved
    // before it was recorded is judged by comparing with the conversion.
    if (crossTransfer &&
        !converts &&
        toAmount == null &&
        !extras.toAmountReset &&
        previous != null &&
        previous.amountMinor == amount &&
        previous.accountId == account.id &&
        previous.toAccountId == to!.id &&
        !_namesNewRate(draft.fx, previous.fx) &&
        (previous.occurredOn == occurredOn ||
            switch (previous.toAmountSource) {
              ToAmountSource.entered => true,
              ToAmountSource.rate => false,
              null => !_rateDerived(previous, toCurrency),
            })) {
      toAmount = previous.toAmountMinor;
      toSource = previous.toAmountSource;
      retainedFx = previous.fx;
    }
    final needsRate =
        converts || currency != base || (crossTransfer && toAmount == null);
    FxRate? rate;
    StoredFx? fx;
    if (needsRate) {
      final priced = await _price(
        draft,
        occurredOn: occurredOn,
        household: household,
        previous: previous,
      );
      switch (priced) {
        case null:
          return Err(
            EntryRateNeeded(
              draftId: draftId,
              from: converts ? spoken.code : currency.code,
              to: converts
                  ? currency.code
                  : currency != base
                  ? base.code
                  : toCurrency!.code,
            ),
          );
        case Err():
          return invalid('fx', EntryIssue.malformed);
        case Ok(:final value):
          (rate, fx) = value;
      }
    } else if (retainedFx != null) {
      fx = retainedFx;
    } else if (draft.fx case final named?
        when named.baseAmountMinor == amount &&
            FxRate.parse(named.pair, named.pairRate).isOk) {
      // The same for the rate an edit or a restored version names, when
      // it is the one this amount was converted with: in the base
      // currency, the base amount is the amount itself.
      fx = StoredFx(
        pair: named.pair,
        pairRate: named.pairRate,
        source: fxSourceValues.contains(named.source)
            ? named.source!
            : 'manual',
        asOf: named.asOf != null && DateTime.tryParse(named.asOf!) != null
            ? named.asOf!
            : occurredOn,
      );
    } else if (previous != null &&
        previous.fx != null &&
        previous.currency == currency &&
        previous.amountMinor == amount &&
        !_namesNewRate(draft.fx, previous.fx)) {
      // An entry in the base currency whose amount was converted from the
      // other one keeps the rate it was converted with while the amount
      // stays: a note or a category edit does not erase it (Codex review,
      // PR #46). A new amount was not converted, so it has no rate.
      fx = previous.fx;
    }
    // The amount in the account's currency: as written, or converted.
    var stored = amount;
    if (converts) {
      final converted = rate!
          .convert(Money(amount, spoken), currency)
          .valueOrNull
          ?.minorUnits;
      if (converted == null) return invalid('fx', EntryIssue.malformed);
      if (converted < 1 || converted > maxDraftAmountMinor) {
        return invalid('amountMinor', EntryIssue.amountOutOfRange);
      }
      stored = converted;
    }
    final baseAmount = toBaseAmount(Money(stored, currency), base, rate: rate);
    final baseMinor = baseAmount.valueOrNull?.minorUnits;
    if (baseMinor == null) {
      return invalid(
        'fx',
        baseAmount.failureOrNull is AmountOutOfRange
            ? EntryIssue.amountOutOfRange
            : EntryIssue.malformed,
      );
    }
    if (crossTransfer && toAmount == null) {
      if (spoken == toCurrency) {
        // The member's figure is what arrives: "move 10,000 dinars from
        // the dollar account to the wallet" credits exactly 10,000; only
        // the debit is converted (Codex review, PR #46).
        toAmount = amount;
        toSource = ToAmountSource.entered;
      } else {
        // From the amount as written, so rounding the debit does not
        // change the credit too.
        toAmount = rate!
            .convert(Money(amount, spoken), toCurrency)
            .valueOrNull
            ?.minorUnits;
        if (toAmount == null) return invalid('fx', EntryIssue.malformed);
        toSource = ToAmountSource.rate;
      }
    }
    if (toAmount != null && (toAmount < 1 || toAmount > maxDraftAmountMinor)) {
      return invalid('toAmountMinor', EntryIssue.amountOutOfRange);
    }

    final visibleTo = {...account.visibleTo, ...?to?.visibleTo}.toList()
      ..sort();
    if (!visibleTo.contains(scope.uid)) {
      return const Err(TransactionsNotAllowed());
    }

    return Ok(
      LedgerTransaction(
        id: previous?.id ?? _store.newId(),
        type: type,
        amountMinor: stored,
        currency: currency,
        accountId: account.id,
        toAccountId: to?.id,
        toAmountMinor: toAmount,
        toAmountSource: toAmount == null ? null : toSource,
        baseAmountMinor: baseMinor,
        fx: fx,
        adjustmentSign: type == LedgerType.adjustment
            ? switch (extras.adjustmentSign ?? previous?.adjustmentSign) {
                final int sign when sign < 0 => -1,
                _ => 1,
              }
            : null,
        categoryId: draft.categoryId,
        whoUid: whoUid,
        whoScope: whoScope,
        occurredAt: occurredAt,
        occurredOn: occurredOn,
        title: title,
        note: note,
        personId: draft.personId,
        personName: switch (draft.personName?.trim()) {
          null || '' => null,
          final name => name,
        },
        loanId: draft.loanId,
        goalId: draft.goalId,
        recurringId: previous?.recurringId,
        groupId: groupId,
        source: source,
        ai: previous == null ? _aiOf(draft) : previous.ai,
        visibleTo: visibleTo,
        deletedAt: previous?.deletedAt,
        rev: previous?.rev ?? 0,
        createdBy: previous?.createdBy ?? scope.uid,
      ),
    );
  }

  /// The rate for a draft: the one it names, else (on an edit that keeps
  /// the day) the stored one, else the household's for the day. Null when
  /// there is none; an [Err] when the named one is malformed.
  Future<Result<(FxRate, StoredFx), MoneyFailure>?> _price(
    EntryDraft draft, {
    required String occurredOn,
    required LedgerHousehold household,
    LedgerTransaction? previous,
  }) async {
    final named = draft.fx;
    final stored = previous?.fx;
    if (named != null && _namesNewRate(named, stored)) {
      final parsed = FxRate.parse(named.pair, named.pairRate);
      if (parsed case Err(:final failure)) return Err(failure);
      final rate = parsed.valueOrNull!;
      final asOf = named.asOf;
      return Ok((
        rate,
        StoredFx(
          pair: rate.pair.code,
          pairRate: rate.rateString,
          source: fxSourceValues.contains(named.source)
              ? named.source!
              : 'manual',
          asOf: asOf != null && DateTime.tryParse(asOf) != null
              ? asOf
              : occurredOn,
        ),
      ));
    }
    final storedRate = stored?.rate;
    if (stored != null &&
        storedRate != null &&
        previous!.occurredOn == occurredOn) {
      return Ok((storedRate, stored));
    }
    final dayRate = await _store.rateOn(occurredOn);
    if (dayRate == null) return null;
    return Ok((
      dayRate.rate,
      StoredFx(
        pair: dayRate.rate.pair.code,
        pairRate: dayRate.rate.rateString,
        source: household.rateKind,
        asOf: dayRate.day,
      ),
    ));
  }

  // ------------------------------------------------------------- helpers

  void _reportLate(List<String> ids, TransactionsFailure failure) {
    if (!_late.isClosed) {
      _late.add(LateWriteFailure(txnIds: ids, failure: failure));
    }
  }

  static TransactionsFailure _fromStore(StoreFailure failure) =>
      switch (failure.kind) {
        StoreFailureKind.denied => const TransactionsNotAllowed(),
        StoreFailureKind.unknown => TransactionsUnknown(failure.detail),
      };

  static Map<String, Object?> _createStamps(String uid) => {
    'createdAt': serverTime,
    'createdBy': uid,
    'updatedAt': serverTime,
    'updatedBy': uid,
    'schemaVersion': 1,
  };

  static Map<String, Object?> _updateStamps(String uid) => {
    'updatedAt': serverTime,
    'updatedBy': uid,
  };

  /// Whether [t]'s arriving amount is its amount converted with its stored
  /// rate into [to] (rather than an amount the member typed).
  static bool _rateDerived(LedgerTransaction t, Currency to) {
    final rate = t.fx?.rate;
    if (rate == null) return false;
    final converted = rate.convert(Money(t.amountMinor, t.currency), to);
    return converted.valueOrNull?.minorUnits == t.toAmountMinor;
  }

  /// Whether [named] (a draft's `fx`) asks for a rate other than [stored].
  /// A prefilled draft repeats the stored rate; that names nothing new.
  static bool _namesNewRate(FxQuote? named, StoredFx? stored) =>
      named != null &&
      !(stored != null &&
          named.pair == stored.pair &&
          named.pairRate == stored.pairRate &&
          (named.asOf ?? stored.asOf) == stored.asOf);

  /// Which stored version [t] is: its `revId`, or its `rev` for an entry
  /// written before `revId` existed.
  static String _version(LedgerTransaction t) => t.revId ?? 'rev:${t.rev}';

  static String _draftId(EntryDraft draft) => '${draft.toJson()['id']}';

  static Map<String, Object?>? _aiOf(EntryDraft draft) {
    final json = draft.toJson();
    final origin = json['origin'];
    if (origin is! String) return null;
    return {
      'path': origin,
      'confidence': json['confidence'],
      'guessedFields': json['guessed'] ?? const <String>[],
    };
  }

  static (int, int)? _parseTime(String hm) {
    final match = RegExp(r'^(\d{2}):(\d{2})$').firstMatch(hm);
    if (match == null) return null;
    final h = int.parse(match.group(1)!);
    final m = int.parse(match.group(2)!);
    return h < 24 && m < 60 ? (h, m) : null;
  }
}

/// Longest `title`, in characters (DATA_MODEL 2.5).
const int maxTitleLength = 80;

/// Longest `note`, in characters (DATA_MODEL 2.5).
const int maxNoteLength = 500;

/// The household-local calendar day of [time], `YYYY-MM-DD` (DATA_MODEL 1).
/// The phone's zone stands in for the household's: both partners live in
/// the household's zone (`Asia/Baghdad` by default).
String householdDay(DateTime time) {
  final t = time.isUtc ? time.toLocal() : time;
  String two(int v) => v.toString().padLeft(2, '0');
  return '${t.year.toString().padLeft(4, '0')}-${two(t.month)}-${two(t.day)}';
}

/// `revisions/{id}.reason` (DATA_MODEL 2.5); `system` is the server's.
enum RevisionReason {
  /// An edit.
  edit,

  /// Undo right after a save.
  undo,

  /// A delete.
  delete,

  /// A restore of a deleted entry.
  restore,
}

/// A change to a stored transaction, kept in the [WriteJournal] so it can
/// be built again on top of another version.
sealed class _Op {
  const new();

  /// Reads a journal record's op, or null when it is malformed.
  static _Op? fromJournal(String name, Map<String, Object?> payload) {
    switch (name) {
      case 'edit':
        final draft = payload['draft'];
        if (draft is! Map) return null;
        final to = payload['toAmountMinor'];
        final sign = payload['adjustmentSign'];
        final reset = payload['toAmountReset'];
        return _EditOp(
          draft.cast<String, dynamic>(),
          EntryExtras(
            toAmountMinor: to is int ? to : null,
            adjustmentSign: sign is int ? sign : null,
            toAmountReset: reset == true,
          ),
        );
      case 'delete':
        return _DeleteOp(
          payload['reason'] == DeleteReason.undo.name
              ? DeleteReason.undo
              : DeleteReason.delete,
        );
      case 'restore':
        return const _RestoreOp();
    }
    return null;
  }

  /// The journal's name for it.
  String get name;

  /// What the journal keeps to build it again.
  Map<String, Object?> get payload;
}

final class _EditOp extends _Op {
  const new(this.draft, this.extras);

  final Map<String, dynamic> draft;
  final EntryExtras extras;

  @override
  String get name => 'edit';

  @override
  Map<String, Object?> get payload => {
    'draft': draft,
    'toAmountMinor': extras.toAmountMinor,
    'adjustmentSign': extras.adjustmentSign,
    'toAmountReset': extras.toAmountReset,
  };
}

final class _DeleteOp extends _Op {
  const new(this.reason);

  final DeleteReason reason;

  @override
  String get name => 'delete';

  @override
  Map<String, Object?> get payload => {'reason': reason.name};
}

final class _RestoreOp extends _Op {
  const new();

  @override
  String get name => 'restore';

  @override
  Map<String, Object?> get payload => const {};
}

/// One change to a stored transaction.
@immutable
final class _Revision {
  const new({
    required this.fields,
    required this.before,
    required this.reason,
    required this.after,
  });

  /// The fields written.
  final Map<String, Object?> fields;

  /// Their values before.
  final Map<String, Object?> before;

  /// Why.
  final RevisionReason reason;

  /// The transaction's balance fields afterwards.
  final LedgerLine after;
}

bool _deepEquals(Object? a, Object? b) {
  if (a is Map && b is Map) {
    return a.length == b.length &&
        a.keys.every((k) => b.containsKey(k) && _deepEquals(a[k], b[k]));
  }
  if (a is List && b is List) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!_deepEquals(a[i], b[i])) return false;
    }
    return true;
  }
  return a == b;
}
