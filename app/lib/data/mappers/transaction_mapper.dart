// Maps between the typed `LedgerTransaction` and the stored fields of
// `transactions/{id}` (DATA_MODEL 2.5), and back to an `EntryDraft` for the
// edit form. Pure: timestamps are `DateTime` here; the Firestore store
// converts them to and from `Timestamp`.
import 'package:xpense_app/data/transactions_repository.dart';
import 'package:xpense_shared/xpense_shared.dart';

/// The content fields of a transaction, the ones an edit may change, in
/// stored order. Every one is written on every save (null when empty), so
/// an edit can clear a field and a revision can name its old value.
const List<String> transactionContentFields = [
  'type',
  'amountMinor',
  'currency',
  'accountId',
  'toAccountId',
  'toAmountMinor',
  'toAmountSource',
  'baseAmountMinor',
  'fx',
  'adjustmentSign',
  'categoryId',
  'whoUid',
  'whoScope',
  'occurredAt',
  'occurredOn',
  'title',
  'note',
  'personId',
  'personName',
  'loanId',
  'goalId',
  'recurringId',
  'groupId',
  'source',
  'ai',
  'visibleTo',
];

/// The stored form of [fx].
Map<String, Object?> fxFields(StoredFx fx) => {
  'pair': fx.pair,
  'pairRate': fx.pairRate,
  'source': fx.source,
  'asOf': fx.asOf,
};

/// The content fields of [t] ([transactionContentFields]); `rev`,
/// `deletedAt` and the audit stamps are the plan's to add.
Map<String, Object?> transactionContent(LedgerTransaction t) => {
  'type': t.type.wire,
  'amountMinor': t.amountMinor,
  'currency': t.currency.code,
  'accountId': t.accountId,
  'toAccountId': t.toAccountId,
  'toAmountMinor': t.toAmountMinor,
  'toAmountSource': t.toAmountSource?.wire,
  'baseAmountMinor': t.baseAmountMinor,
  'fx': t.fx == null ? null : fxFields(t.fx!),
  'adjustmentSign': t.type == LedgerType.adjustment
      ? (t.adjustmentSign ?? 1)
      : null,
  'categoryId': t.categoryId,
  'whoUid': t.whoUid,
  'whoScope': t.whoScope.wire,
  'occurredAt': t.occurredAt.toUtc(),
  'occurredOn': t.occurredOn,
  'title': t.title,
  'note': t.note,
  'personId': t.personId,
  'personName': t.personName,
  'loanId': t.loanId,
  'goalId': t.goalId,
  'recurringId': t.recurringId,
  'groupId': t.groupId,
  'source': t.source.wire,
  'ai': t.ai,
  'visibleTo': [...t.visibleTo],
};

/// Reads stored transaction [id], or null when it is malformed. Timestamps
/// must already be `DateTime`. A `deletedAt` that is set but not a
/// `DateTime` (a server timestamp still pending) reads as
/// [LedgerTransaction.deletePending].
LedgerTransaction? transactionFromFields(String id, Map<String, Object?> data) {
  final type = LedgerType.tryParse('${data['type']}');
  final amount = data['amountMinor'];
  final currency = Currency.tryParse('${data['currency']}');
  final accountId = data['accountId'];
  final occurredAt = data['occurredAt'];
  if (type == null ||
      amount is! int ||
      currency == null ||
      accountId is! String ||
      occurredAt is! DateTime) {
    return null;
  }
  String? str(String key) => switch (data[key]) {
    final String v => v,
    _ => null,
  };
  int? integer(String key) => switch (data[key]) {
    final int v => v,
    _ => null,
  };
  final deletedAt = data['deletedAt'];
  return LedgerTransaction(
    id: id,
    type: type,
    amountMinor: amount,
    currency: currency,
    accountId: accountId,
    toAccountId: str('toAccountId'),
    toAmountMinor: integer('toAmountMinor'),
    toAmountSource: ToAmountSource.tryParse(data['toAmountSource']),
    baseAmountMinor: integer('baseAmountMinor') ?? 0,
    fx: _fxFrom(data['fx']),
    adjustmentSign: type == LedgerType.adjustment
        ? (data['adjustmentSign'] == -1 ? -1 : 1)
        : null,
    categoryId: str('categoryId'),
    whoUid: str('whoUid'),
    whoScope: WhoScope.fromWire(data['whoScope']),
    occurredAt: occurredAt,
    occurredOn: str('occurredOn') ?? '',
    title: str('title') ?? '',
    note: str('note'),
    personId: str('personId'),
    personName: str('personName'),
    loanId: str('loanId'),
    goalId: str('goalId'),
    recurringId: str('recurringId'),
    groupId: str('groupId'),
    source: EntrySource.fromWire(data['source']),
    ai: switch (data['ai']) {
      final Map<Object?, Object?> ai => ai.cast<String, Object?>(),
      _ => null,
    },
    visibleTo: switch (data['visibleTo']) {
      final List<Object?> list => list.whereType<String>().toList(),
      _ => const [],
    },
    deletedAt: deletedAt is DateTime ? deletedAt : null,
    deletePending: deletedAt != null && deletedAt is! DateTime,
    rev: integer('rev') ?? 0,
    revId: str('revId'),
    createdBy: str('createdBy'),
  );
}

StoredFx? _fxFrom(Object? value) {
  if (value is! Map) return null;
  final pair = value['pair'];
  final rate = value['pairRate'];
  if (pair is! String || rate is! String) return null;
  return StoredFx(
    pair: pair,
    pairRate: rate,
    source: switch (value['source']) {
      final String s => s,
      _ => 'manual',
    },
    asOf: switch (value['asOf']) {
      final String s => s,
      _ => '',
    },
  );
}

/// [t] as a draft, to prefill the edit form (WP-21). `who` is said from
/// [viewerUid]'s side: their own entries are `me`.
EntryDraft draftFromTransaction(
  LedgerTransaction t, {
  required String viewerUid,
}) {
  String two(int v) => v.toString().padLeft(2, '0');
  final local = t.occurredAt.toLocal();
  final fx = t.fx;
  return EntryDraft(
    id: t.id,
    intent: t.type == LedgerType.transfer && t.goalId != null
        ? CaptureIntent.savingsMove.wire
        : t.type.wire,
    amountMinor: t.amountMinor,
    currency: t.currency.code,
    accountId: t.accountId,
    toAccountId: t.toAccountId,
    categoryId: t.categoryId,
    who: switch (t.whoScope) {
      WhoScope.joint => 'joint',
      WhoScope.member when t.whoUid == null || t.whoUid == viewerUid => 'me',
      WhoScope.member => 'partner',
    },
    occurredOn: t.occurredOn,
    occurredTime: '${two(local.hour)}:${two(local.minute)}',
    title: t.title.isEmpty ? null : t.title,
    note: t.note,
    personId: t.personId,
    // A loan event saved with only a name keeps it, so the draft passes the
    // same checks again (Codex review, PR #35).
    personName: t.personName,
    loanId: t.loanId,
    goalId: t.goalId,
    fx: fx == null
        ? null
        : FxQuote(
            pair: fx.pair,
            pairRate: fx.pairRate,
            source: fx.source,
            asOf: fx.asOf,
            baseAmountMinor: t.baseAmountMinor,
          ),
  );
}
