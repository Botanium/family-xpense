// The revision history of an entry as rows (DESIGN_SYSTEM screen 17,
// BACKLOG S2.3), and how Restore turns an old version back into an edit.
// Pure: tested without widgets.
import 'package:flutter/foundation.dart';
import 'package:xpense_app/data/mappers/transaction_mapper.dart';
import 'package:xpense_app/data/transactions_reader.dart';
import 'package:xpense_app/data/transactions_repository.dart';
import 'package:xpense_shared/xpense_shared.dart';

/// The part of an entry a change touched, for the row's title.
enum ChangedPart {
  /// The amount (or what arrives).
  amount,

  /// The account or the transfer's destination.
  account,

  /// The category.
  category,

  /// Whose it is.
  who,

  /// The day and time.
  date,

  /// The note.
  note,

  /// The counterparty or the title.
  person,

  /// The type.
  type,

  /// The stored rate only.
  rate,
}

/// What a history row stands for.
enum HistoryKind {
  /// The first save.
  created,

  /// Fields changed.
  edit,

  /// Deleted.
  delete,

  /// Undone right after saving.
  undo,

  /// Restored after a delete.
  restore,

  /// A server job corrected it.
  system,
}

/// One row of the history, newest first.
@immutable
final class HistoryItem {
  /// Creates the row.
  const new({
    required this.kind,
    required this.actor,
    required this.at,
    this.parts = const {},
    this.before = const {},
    this.after = const {},
    this.revision,
    this.restorable = false,
  });

  /// What happened.
  final HistoryKind kind;

  /// Who did it (a uid or `system`), when known.
  final String? actor;

  /// When, when known.
  final DateTime? at;

  /// What an edit touched.
  final Set<ChangedPart> parts;

  /// The changed fields' values before.
  final Map<String, Object?> before;

  /// The same fields' values after.
  final Map<String, Object?> after;

  /// The revision, for every row but [HistoryKind.created].
  final EntryRevision? revision;

  /// Whether the row offers Restore.
  final bool restorable;

  /// The one part an edit touched, or null for none or several.
  ChangedPart? get onlyPart => parts.length == 1 ? parts.single : null;
}

/// The parts of the entry each stored field belongs to. Fields derived
/// from others (`baseAmountMinor`, `visibleTo`, `toAmountSource`) and
/// links the form does not show are not listed.
const Map<String, ChangedPart> _partOf = {
  'amountMinor': ChangedPart.amount,
  'toAmountMinor': ChangedPart.amount,
  'adjustmentSign': ChangedPart.amount,
  'accountId': ChangedPart.account,
  'toAccountId': ChangedPart.account,
  'currency': ChangedPart.account,
  'categoryId': ChangedPart.category,
  'whoUid': ChangedPart.who,
  'whoScope': ChangedPart.who,
  'occurredAt': ChangedPart.date,
  'occurredOn': ChangedPart.date,
  'note': ChangedPart.note,
  'personName': ChangedPart.person,
  'personId': ChangedPart.person,
  'title': ChangedPart.person,
  'type': ChangedPart.type,
  'fx': ChangedPart.rate,
};

/// The history of [record] from its [revisions] (any order), newest
/// first, ending with the first save.
///
/// Each revision stores only the old values of what it changed; the new
/// values are what the next newer revision says they were before it, or
/// the entry as it is now.
List<HistoryItem> buildHistory(
  EntryRecord record,
  List<EntryRevision> revisions,
) {
  final txn = record.txn;
  final state = <String, Object?>{
    ...transactionContent(txn),
    'deleted': txn.deleted,
  };
  final ordered = newestFirst(revisions);
  final latestDelete = ordered
      .where(
        (r) =>
            r.reason == RevisionReason.delete ||
            r.reason == RevisionReason.undo,
      )
      .firstOrNull;
  final items = <HistoryItem>[];
  for (final r in ordered) {
    final before = {
      for (final e in r.before.entries)
        if (e.key != 'deletedAt') e.key: e.value,
    };
    final after = {for (final k in before.keys) k: state[k]};
    var parts = {for (final k in before.keys) ?_partOf[k]};
    // The rate follows a change of amount, day or account; it is named
    // only when nothing else changed.
    if (parts.length > 1) parts = parts.difference({ChangedPart.rate});
    final kind = switch (r.reason) {
      RevisionReason.edit => HistoryKind.edit,
      RevisionReason.delete => HistoryKind.delete,
      RevisionReason.undo => HistoryKind.undo,
      RevisionReason.restore => HistoryKind.restore,
      RevisionReason.system => HistoryKind.system,
    };
    final restorable = switch (kind) {
      HistoryKind.edit || HistoryKind.system =>
        !txn.deleted && before.keys.any(_partOf.containsKey),
      HistoryKind.delete ||
      HistoryKind.undo => txn.deleted && identical(r, latestDelete),
      HistoryKind.restore || HistoryKind.created => false,
    };
    items.add(
      HistoryItem(
        kind: kind,
        actor: r.changedBy,
        at: r.changedAt,
        parts: kind == HistoryKind.edit || kind == HistoryKind.system
            ? parts
            : const {},
        before: before,
        after: after,
        revision: r,
        restorable: restorable,
      ),
    );
    state.addAll(before);
  }
  items.add(
    HistoryItem(
      kind: HistoryKind.created,
      actor: txn.createdBy,
      at: record.createdAt,
      after: {
        'amountMinor': state['amountMinor'],
        'currency': state['currency'],
      },
    ),
  );
  return items;
}

/// What Restore on an edit row saves: the entry as it is now with the
/// fields that revision changed set back. Null when the old version no
/// longer reads.
({EntryDraft draft, EntryExtras extras})? restoreDraft(
  LedgerTransaction current,
  EntryRevision revision, {
  required String viewerUid,
}) {
  final fields = {
    ...transactionContent(current),
    for (final e in revision.before.entries)
      if (transactionContentFields.contains(e.key)) e.key: e.value,
    'rev': current.rev,
    'createdBy': current.createdBy,
  };
  final old = transactionFromFields(current.id, fields);
  if (old == null) return null;
  return (
    draft: draftFromTransaction(old, viewerUid: viewerUid),
    extras: EntryExtras(
      toAmountMinor: old.toAmountSource == ToAmountSource.entered
          ? old.toAmountMinor
          : null,
      adjustmentSign: old.adjustmentSign,
    ),
  );
}
