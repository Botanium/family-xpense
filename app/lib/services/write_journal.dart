// A small phone-local journal of queued transaction changes (WP-20, Codex
// review of PR #35). Firestore keeps a queued batch across an app restart,
// but not the callback that re-applies it when the server refuses it, so
// the write path records each edit, delete and restore here until the
// server has it. The SharedPreferences adapter is
// `write_journal_prefs.dart`; only the composition root names it.
import 'package:flutter/foundation.dart';

/// One queued change to a stored transaction.
@immutable
final class PendingRevision {
  /// Creates the record.
  const new({
    required this.householdId,
    required this.uid,
    required this.txnId,
    required this.revId,
    required this.baseVersion,
    required this.op,
    this.payload = const {},
  });

  /// Reads a stored record, or null when it is malformed.
  static PendingRevision? fromJson(Object? json) {
    if (json is! Map) return null;
    String? str(String key) => switch (json[key]) {
      final String v => v,
      _ => null,
    };
    final householdId = str('householdId');
    final uid = str('uid');
    final txnId = str('txnId');
    final revId = str('revId');
    final baseVersion = str('baseVersion');
    final op = str('op');
    if (householdId == null ||
        uid == null ||
        txnId == null ||
        revId == null ||
        baseVersion == null ||
        op == null) {
      return null;
    }
    return PendingRevision(
      householdId: householdId,
      uid: uid,
      txnId: txnId,
      revId: revId,
      baseVersion: baseVersion,
      op: op,
      payload: switch (json['payload']) {
        final Map<Object?, Object?> m => m.cast<String, Object?>(),
        _ => const {},
      },
    );
  }

  /// The household.
  final String householdId;

  /// The member who made the change.
  final String uid;

  /// The transaction.
  final String txnId;

  /// The `revId` the change writes; once the server has a revision with
  /// this id, the change landed.
  final String revId;

  /// The version it was built on (`revId`, or `rev:N` before `revId`).
  final String baseVersion;

  /// `edit`, `delete` or `restore`.
  final String op;

  /// What the op needs to be built again (an edit's draft and extras, a
  /// delete's reason), as JSON.
  final Map<String, Object?> payload;

  /// The stored form.
  Map<String, Object?> toJson() => {
    'householdId': householdId,
    'uid': uid,
    'txnId': txnId,
    'revId': revId,
    'baseVersion': baseVersion,
    'op': op,
    'payload': payload,
  };

  @override
  String toString() => 'PendingRevision($txnId, $op)';
}

/// Keeps [PendingRevision]s across app restarts.
abstract interface class WriteJournal {
  /// Every record, oldest first.
  List<PendingRevision> get entries;

  /// Adds [entry].
  Future<void> put(PendingRevision entry);

  /// Removes the record of [revId], if any.
  Future<void> remove(String revId);
}

/// A [WriteJournal] in memory: for the fakes build and tests. A test keeps
/// the instance to stand for what survives a restart.
final class MemoryWriteJournal implements WriteJournal {
  final List<PendingRevision> _entries = [];

  @override
  List<PendingRevision> get entries => List.unmodifiable(_entries);

  @override
  Future<void> put(PendingRevision entry) async => _entries.add(entry);

  @override
  Future<void> remove(String revId) async =>
      _entries.removeWhere((e) => e.revId == revId);
}
