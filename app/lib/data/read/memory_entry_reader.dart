// [EntryReader] over the in-memory ledger, for the fakes build and
// tests. [ObservedLedgerStore] wraps the `MemoryLedgerStore` the write path
// commits to and says when it changed, so the reader's streams update
// after every save, edit, delete and restore, as Firestore's listeners do.
import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:xpense_app/data/mappers/transaction_mapper.dart';
import 'package:xpense_app/data/read/entry_reader.dart';
import 'package:xpense_app/data/transactions_repository.dart';
import 'package:xpense_app/data/write/ledger_store.dart';
import 'package:xpense_app/data/write/memory_ledger_store.dart';
import 'package:xpense_shared/xpense_shared.dart';

/// A [LedgerStore] that forwards to [memory] and reports each commit on
/// [changes].
final class ObservedLedgerStore implements LedgerStore {
  /// Wraps [memory].
  new(this.memory);

  /// The store written to.
  final MemoryLedgerStore memory;

  final StreamController<void> _changes = StreamController<void>.broadcast(
    sync: true,
  );

  /// Fires after every commit that wrote something.
  Stream<void> get changes => _changes.stream;

  /// Reports a change made directly on [memory] (tests seeding data).
  void notify() => _changes.add(null);

  @override
  LedgerScope? get scope => memory.scope;

  @override
  DateTime now() => memory.now();

  @override
  String newId() => memory.newId();

  @override
  Future<LedgerHousehold?> household() => memory.household();

  @override
  Future<LedgerAccount?> account(String id) => memory.account(id);

  @override
  Future<LedgerCategory?> category(String id) => memory.category(id);

  @override
  Future<LedgerLoan?> loan(String id) => memory.loan(id);

  @override
  Future<bool> hasPerson(String id) => memory.hasPerson(id);

  @override
  Future<String?> goalAccount(String id) => memory.goalAccount(id);

  @override
  Future<DayRate?> rateOn(String day) => memory.rateOn(day);

  @override
  Future<LedgerTransaction?> transaction(String id, {bool fresh = false}) =>
      memory.transaction(id, fresh: fresh);

  @override
  Future<void> settle() => memory.settle();

  @override
  Future<bool> hasRevision(String txnId, String revId) =>
      memory.hasRevision(txnId, revId);

  @override
  Future<Result<WriteAck, StoreFailure>> commit(
    LedgerPlan plan, {
    void Function(StoreFailure failure)? onLateFailure,
  }) async {
    final result = await memory.commit(plan, onLateFailure: onLateFailure);
    if (result.isOk) _changes.add(null);
    return result;
  }
}

/// [EntryReader] over an [ObservedLedgerStore].
final class MemoryEntryReader implements EntryReader {
  /// Creates the reader.
  new(this._store);

  final ObservedLedgerStore _store;

  /// [read] now and after every commit through [_store] or any other
  /// change to its memory (a partner's edit, a queued write reaching the
  /// server, an account's opening balance), as a Firestore listener hears
  /// them all. It subscribes when listened to, so a change right after the
  /// first value is not missed.
  Stream<T> _watch<T>(T Function() read) {
    late final StreamController<T> out;
    final subs = <StreamSubscription<void>>[];
    out = StreamController<T>(
      onListen: () {
        out.add(read());
        void emit(void _) => out.add(read());
        subs
          ..add(_store.changes.listen(emit))
          ..add(_store.memory.changes.listen(emit));
      },
      // Cancelled without waiting: a `Future.wait` returned here never
      // completes under a widget test's fake clock, so `.first` would hang.
      onCancel: () {
        for (final s in subs) {
          unawaited(s.cancel());
        }
      },
    );
    return out.stream;
  }

  @override
  Stream<EntryRecord?> watchEntry(String id) => _watch(() {
    final uid = _store.scope?.uid;
    final data = _store.memory.transactions[id];
    if (uid == null || data == null) return null;
    final txn = transactionFromFields(id, data);
    if (txn == null || !txn.visibleTo.contains(uid)) return null;
    return EntryRecord(
      txn: txn,
      createdAt: switch (data['createdAt']) {
        final DateTime t => t,
        _ => null,
      },
      syncing: !_store.memory.online,
    );
  }).distinct();

  @override
  Stream<List<EntryRevision>> watchRevisions(String id) =>
      _watch<List<EntryRevision>>(() {
        final uid = _store.scope?.uid;
        final data = _store.memory.transactions[id];
        final visible = switch (data?['visibleTo']) {
          final List<Object?> list => list.contains(uid),
          _ => false,
        };
        if (!visible) return const <EntryRevision>[];
        return newestFirst([
          for (final r
              in _store.memory.revisions[id] ?? const <Map<String, Object?>>[])
            ?revisionFromFields('${r['id']}', r),
        ]);
      }).distinct(listEquals);
}
