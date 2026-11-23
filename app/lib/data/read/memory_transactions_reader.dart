// [TransactionsReader] over the in-memory ledger, for the fakes build and
// tests. [ObservedLedgerStore] wraps the `MemoryLedgerStore` the write path
// commits to and says when it changed, so the reader's streams update
// after every save, edit, delete and restore, as Firestore's listeners do.
import 'dart:async';

import 'package:xpense_app/data/mappers/transaction_mapper.dart';
import 'package:xpense_app/data/transactions_reader.dart';
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

/// [TransactionsReader] over an [ObservedLedgerStore].
final class MemoryTransactionsReader implements TransactionsReader {
  /// Creates the reader.
  new(this._store);

  final ObservedLedgerStore _store;

  Stream<T> _watch<T>(T Function() read) async* {
    yield read();
    yield* _store.changes.map((_) => read());
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
  Stream<List<EntryRevision>> watchRevisions(String id) => _watch(() {
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
  });
}
