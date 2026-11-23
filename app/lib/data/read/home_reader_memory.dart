import 'dart:async';

import 'package:xpense_app/data/mappers/transaction_mapper.dart';
import 'package:xpense_app/data/read/home_reader.dart';
import 'package:xpense_app/data/transactions_repository.dart';
import 'package:xpense_app/data/write/memory_ledger_store.dart';

/// [HomeReader] over a [MemoryLedgerStore], for the fakes build and
/// tests. It sees what the store's phone sees, queued writes included, and
/// applies the same `visibleTo` and `deletedAt` filters as the Firestore
/// queries.
final class MemoryHomeReader implements HomeReader {
  /// Reads [store].
  const new(MemoryLedgerStore this.store);

  /// A reader with nothing in it.
  const new empty() : store = null;

  /// The store read; null reads as empty.
  final MemoryLedgerStore? store;

  @override
  Stream<List<LedgerTransaction>> watchRange({
    required String fromDay,
    required String toDay,
  }) => _watch(
    () =>
        _visible()
            .where(
              (t) =>
                  t.occurredOn.compareTo(fromDay) >= 0 &&
                  t.occurredOn.compareTo(toDay) <= 0,
            )
            .toList()
          ..sort((a, b) => a.occurredOn.compareTo(b.occurredOn)),
  );

  @override
  Stream<List<LedgerTransaction>> watchRecent({required int limit}) => _watch(
    () =>
        (_visible().toList()
              ..sort((a, b) => b.occurredAt.compareTo(a.occurredAt)))
            .take(limit)
            .toList(),
  );

  Iterable<LedgerTransaction> _visible() sync* {
    final store = this.store;
    final uid = store?.scope?.uid;
    if (store == null || uid == null) return;
    for (final e in store.transactions.entries) {
      final t = transactionFromFields(e.key, e.value);
      if (t != null && t.visibleTo.contains(uid) && !t.deleted) yield t;
    }
  }

  Stream<List<LedgerTransaction>> _watch(
    List<LedgerTransaction> Function() read,
  ) {
    late final StreamController<List<LedgerTransaction>> controller;
    StreamSubscription<void>? changes;
    controller = StreamController<List<LedgerTransaction>>(
      onListen: () {
        controller.add(read());
        changes = store?.changes.listen((_) => controller.add(read()));
      },
      onCancel: () => changes?.cancel(),
    );
    return controller.stream;
  }
}
