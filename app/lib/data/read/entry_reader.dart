// Reads one transaction and its revisions (DATA_MODEL 2.5), for the entry
// detail screen (WP-21, DESIGN_SYSTEM screen 17).
//
// This file is the interface features import. The Firestore adapter is
// `firestore_entry_reader.dart` and the in-memory one
// `memory_entry_reader.dart`, next to it; only the composition root and
// tests name them. Writes never go through here: they go through
// `TransactionsRepository` (D-10).
//
// Each read package owns its own reader (WP-22 `activity_reader.dart`,
// WP-23 `home_reader.dart`). These are single-document reads, not
// queries: a member reads only an entry they can see (`visibleTo`, as
// the rules check), and a deleted one still reads, so its detail screen
// can show it as deleted with Restore.
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:xpense_app/data/transactions_repository.dart';

/// One stored transaction with what the detail screen shows about it
/// beyond its content.
@immutable
final class EntryRecord {
  /// Creates the record.
  const new({required this.txn, this.createdAt, this.syncing = false});

  /// The transaction.
  final LedgerTransaction txn;

  /// When it was first saved (server time); null while that is pending.
  final DateTime? createdAt;

  /// Whether a write to it is still on the phone only.
  final bool syncing;

  @override
  bool operator ==(Object other) =>
      other is EntryRecord &&
      other.txn == txn &&
      other.createdAt == createdAt &&
      other.syncing == syncing;

  @override
  int get hashCode => Object.hash(txn, createdAt, syncing);

  @override
  String toString() => 'EntryRecord(${txn.id})';
}

/// Why a revision was written (`revisions.reason`, DATA_MODEL 2.5).
enum RevisionReason {
  /// A member changed fields.
  edit,

  /// A member tapped Undo right after saving.
  undo,

  /// A member deleted the entry.
  delete,

  /// A member restored it.
  restore,

  /// A server job (reconcile, visibility backfill).
  system;

  /// Parses a stored value; unknown values read as [system].
  static RevisionReason fromWire(Object? wire) =>
      values.where((r) => r.name == wire).firstOrNull ?? system;
}

/// One revision of a transaction (`transactions/{id}/revisions/{revId}`).
@immutable
final class EntryRevision {
  /// Creates the revision.
  const new({
    required this.id,
    required this.rev,
    required this.before,
    required this.reason,
    this.changedBy,
    this.changedAt,
  });

  /// The revision id (UUID v7), equal to the version's `revId`.
  final String id;

  /// The `rev` this revision made.
  final int rev;

  /// The changed fields' values before the change, with timestamps as UTC
  /// `DateTime`s.
  final Map<String, Object?> before;

  /// Why it was written.
  final RevisionReason reason;

  /// Who wrote it (a uid, or `system`).
  final String? changedBy;

  /// When (server time); null while that is pending.
  final DateTime? changedAt;

  @override
  bool operator ==(Object other) =>
      other is EntryRevision &&
      other.id == id &&
      other.rev == rev &&
      mapEquals(other.before, before) &&
      other.reason == reason &&
      other.changedBy == changedBy &&
      other.changedAt == changedAt;

  @override
  int get hashCode =>
      Object.hash(id, rev, Object.hashAll(before.keys), reason, changedAt);

  // No values: this lands in logs.
  @override
  String toString() => 'EntryRevision($id, rev $rev, ${reason.name})';
}

/// Reads transactions the member can see. Reads come from the phone's
/// cache first, so they work offline.
abstract interface class EntryReader {
  /// Transaction [id], live; null while it does not exist or the member
  /// cannot see it.
  Stream<EntryRecord?> watchEntry(String id);

  /// The revisions of transaction [id], live, newest first.
  Stream<List<EntryRevision>> watchRevisions(String id);
}

/// The [EntryReader] for this run. Throws until the composition
/// root sets it.
final entryReaderProvider = Provider<EntryReader>(
  (ref) =>
      throw UnimplementedError('entryReaderProvider is set in bootstrap()'),
  name: 'entryReaderProvider',
);

/// One transaction, live.
final StreamProviderFamily<EntryRecord?, String> entryProvider = StreamProvider
    .autoDispose
    .family<EntryRecord?, String>(
      (ref, id) => ref.watch(entryReaderProvider).watchEntry(id),
      name: 'entryProvider',
    );

/// One transaction's revisions, live, newest first.
final StreamProviderFamily<List<EntryRevision>, String> entryRevisionsProvider =
    StreamProvider.autoDispose.family<List<EntryRevision>, String>(
      (ref, id) => ref.watch(entryReaderProvider).watchRevisions(id),
      name: 'entryRevisionsProvider',
    );

/// Parses a stored revision; null when it is malformed. Timestamps must
/// already be `DateTime`.
EntryRevision? revisionFromFields(String id, Map<String, Object?> data) {
  final rev = data['rev'];
  if (rev is! int) return null;
  return EntryRevision(
    id: id,
    rev: rev,
    before: switch (data['before']) {
      final Map<Object?, Object?> m => m.cast<String, Object?>(),
      _ => const {},
    },
    reason: RevisionReason.fromWire(data['reason']),
    changedBy: switch (data['changedBy']) {
      final String s => s,
      _ => null,
    },
    changedAt: switch (data['changedAt']) {
      final DateTime t => t,
      _ => null,
    },
  );
}

/// Sorts [revisions] newest first.
List<EntryRevision> newestFirst(Iterable<EntryRevision> revisions) =>
    revisions.toList()..sort((a, b) => b.rev.compareTo(a.rev));
