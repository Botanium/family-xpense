// The in-memory `ActivityReader`, for the fakes build and tests. It reads the
// same stored fields the memory write path keeps
// (`write/memory_ledger_store.dart`), so a delete and its undo show at once.
import 'dart:async';

import 'package:xpense_app/data/mappers/transaction_mapper.dart';
import 'package:xpense_app/data/read/activity_reader.dart';
import 'package:xpense_app/data/transactions_repository.dart';
import 'package:xpense_shared/xpense_shared.dart';

/// [ActivityReader] over stored transaction fields held in memory.
///
/// `read` returns every stored transaction by id, as the phone sees it.
/// Call [changed] after a write (or wrap the write path in
/// [NotifyingTransactionsRepository]) to emit again.
final class MemoryActivityReader implements ActivityReader {
  /// Creates the reader for viewer [viewerUid]; null reads as "not in a
  /// household".
  new({required this._read, required this.viewerUid});

  /// A reader with nothing in it.
  factory empty({String? viewerUid}) =>
      MemoryActivityReader(read: () => const {}, viewerUid: viewerUid);

  final Map<String, Map<String, Object?>> Function() _read;

  /// Who is reading.
  String? viewerUid;

  /// When set, every [watch] fails with it (for error-state tests).
  ActivityReadFailure? failure;

  /// When set, windows report they came from the cache (offline).
  bool fromCache = false;

  /// Ids reported as still syncing.
  Set<String> syncing = const {};

  final StreamController<void> _changes = StreamController<void>.broadcast();

  /// How many windows were opened, for paging tests.
  final List<ActivityQuery> opened = [];

  /// Emits a new window to every listener.
  void changed() {
    if (!_changes.isClosed) _changes.add(null);
  }

  @override
  Stream<ActivityWindow> watch(ActivityQuery query) {
    opened.add(query);
    StreamSubscription<void>? changes;
    late final StreamController<ActivityWindow> out;
    void emit() {
      final failed = failure;
      if (failed != null) {
        out.addError(failed);
      } else {
        out.add(_window(query));
      }
    }

    out = StreamController<ActivityWindow>(
      onListen: () {
        emit();
        changes = _changes.stream.listen((_) => emit());
      },
      onCancel: () => changes?.cancel(),
    );
    return out.stream;
  }

  ActivityWindow _window(ActivityQuery query) {
    final uid = viewerUid;
    if (uid == null) return const ActivityWindow(entries: [], hasMore: false);
    final live =
        <LedgerTransaction>[
          for (final MapEntry(:key, :value) in _read().entries)
            if (value['deletedAt'] == null)
              if (transactionFromFields(key, value) case final txn?)
                if (txn.visibleTo.contains(uid) && query.matches(txn)) txn,
        ]..sort((a, b) {
          final byTime = b.occurredAt.compareTo(a.occurredAt);
          return byTime != 0 ? byTime : b.id.compareTo(a.id);
        });
    return ActivityWindow(
      entries: live.take(query.limit).toList(),
      hasMore: live.length > query.limit,
      fromCache: fromCache,
      syncing: {
        for (final t in live.take(query.limit))
          if (syncing.contains(t.id)) t.id,
      },
    );
  }

  /// Stops emitting.
  Future<void> dispose() => _changes.close();
}

/// A [TransactionsRepository] that tells a [MemoryActivityReader] after every
/// write, so the window follows the memory write path.
final class NotifyingTransactionsRepository implements TransactionsRepository {
  /// Wraps [_inner]; [reader] hears of every write.
  new(this._inner, this.reader);

  final TransactionsRepository _inner;

  /// The reader that follows this write path.
  final MemoryActivityReader reader;

  Future<T> _then<T>(Future<T> write) async {
    final result = await write;
    reader.changed();
    return result;
  }

  @override
  Future<Result<SavedEntries, TransactionsFailure>> saveEntries(
    List<EntryDraft> drafts, {
    EntrySource? source,
    Map<String, EntryExtras> extras = const {},
  }) => _then(_inner.saveEntries(drafts, source: source, extras: extras));

  @override
  Future<Result<WriteAck, TransactionsFailure>> editEntry(
    String txnId,
    EntryDraft draft, {
    EntryExtras extras = const EntryExtras(),
  }) => _then(_inner.editEntry(txnId, draft, extras: extras));

  @override
  Future<Result<WriteAck, TransactionsFailure>> deleteEntry(
    String txnId, {
    DeleteReason reason = DeleteReason.delete,
  }) => _then(_inner.deleteEntry(txnId, reason: reason));

  @override
  Future<Result<WriteAck, TransactionsFailure>> undoSave(SavedEntries saved) =>
      _then(_inner.undoSave(saved));

  @override
  Future<Result<WriteAck, TransactionsFailure>> restoreEntry(String txnId) =>
      _then(_inner.restoreEntry(txnId));

  @override
  Stream<LateWriteFailure> get lateFailures => _inner.lateFailures;
}
