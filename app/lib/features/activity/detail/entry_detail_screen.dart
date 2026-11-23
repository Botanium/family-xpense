import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:xpense_app/core/l10n/l10n.dart';
import 'package:xpense_app/core/routing/routing.dart';
import 'package:xpense_app/core/theme/theme.dart';
import 'package:xpense_app/core/ui/ui.dart';
import 'package:xpense_app/data/accounts_repository.dart';
import 'package:xpense_app/data/household_repository.dart';
import 'package:xpense_app/data/read/entry_reader.dart';
import 'package:xpense_app/data/transactions_repository.dart';
import 'package:xpense_app/features/activity/detail/entry_history.dart';
import 'package:xpense_app/features/activity/detail/entry_labels.dart';
import 'package:xpense_app/services/clock.dart';
import 'package:xpense_shared/xpense_shared.dart';

/// The rows of entry detail, named as the edit sheet's fields
/// (`ManualField`), so a tap opens the sheet at that row.
abstract final class EntryRowField {
  /// The amount.
  static const amount = 'amount';

  /// The account.
  static const account = 'account';

  /// A transfer's destination.
  static const toAccount = 'toAccount';

  /// The category.
  static const category = 'category';

  /// Whose it is.
  static const who = 'who';

  /// The day.
  static const date = 'date';

  /// The counterparty.
  static const person = 'person';

  /// The note.
  static const note = 'note';
}

/// Entry detail and history (DESIGN_SYSTEM screen 17, BACKLOG S2.3): the
/// amount with the base-currency line, the fields as rows that open the
/// edit sheet at that field, the rate used and the source, and the
/// revisions with Restore. Every change goes through the write path.
class EntryDetailScreen extends ConsumerStatefulWidget {
  /// Creates the screen for entry [txnId].
  const new({required this.txnId, super.key});

  /// The entry's id, from the path.
  final String txnId;

  @override
  ConsumerState<EntryDetailScreen> createState() => _EntryDetailScreenState();
}

class _EntryDetailScreenState extends ConsumerState<EntryDetailScreen> {
  bool _busy = false;

  void _edit(String field) =>
      unawaited(context.push(AppRoutes.editEntry(widget.txnId, field: field)));

  Future<void> _run(
    Future<Result<WriteAck, TransactionsFailure>> Function(
      TransactionsRepository,
    )
    call, {
    String? doneMessage,
    VoidCallback? undo,
  }) async {
    if (_busy) return;
    setState(() => _busy = true);
    final result = await call(ref.read(transactionsRepositoryProvider));
    if (!mounted) return;
    setState(() => _busy = false);
    final l10n = context.l10n;
    switch (result) {
      case Ok():
        unawaited(XpHaptics.saved());
        if (doneMessage != null && undo != null) {
          showUndoToast(
            context: context,
            message: doneMessage,
            actionLabel: l10n.activityEntryUndo,
            onAction: undo,
          );
        }
      case Err(:final failure):
        unawaited(XpHaptics.warning());
        showUndoToast(
          context: context,
          message: _failureMessage(failure),
          actionLabel: l10n.activityEntryOk,
          onAction: () {},
        );
    }
  }

  String _failureMessage(TransactionsFailure failure) {
    final l10n = context.l10n;
    return switch (failure) {
      TransactionsNotAllowed() => l10n.activityEntryFailNotAllowed,
      TransactionConflict() => l10n.activityEntryFailConflict,
      TransactionDeleted() => l10n.activityEntryFailDeleted,
      EntryRateNeeded() => l10n.activityEntryFailRateNeeded,
      EntryInvalid() || TooManyEntries() => l10n.activityEntryFailInvalid,
      TransactionNotFound() ||
      TransactionNotDeleted() ||
      TransactionsUnknown() => l10n.activityEntryFailUnknown,
    };
  }

  void _delete() {
    final l10n = context.l10n;
    final id = widget.txnId;
    unawaited(
      showXpActionSheet(
        context: context,
        title: l10n.activityEntryDeleteQuestion,
        cancelLabel: l10n.activityEntryCancel,
        actions: [
          XpAction(
            label: l10n.activityEntryDelete,
            destructive: true,
            onPressed: () {
              unawaited(XpHaptics.destructive());
              final repository = ref.read(transactionsRepositoryProvider);
              unawaited(
                _run(
                  (r) => r.deleteEntry(id),
                  doneMessage: l10n.activityEntryDeleted,
                  undo: () => unawaited(repository.restoreEntry(id)),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  void _restore(HistoryItem item, LedgerTransaction txn) {
    final revision = item.revision;
    if (revision == null) return;
    switch (item.kind) {
      case HistoryKind.delete || HistoryKind.undo:
        unawaited(_run((r) => r.restoreEntry(txn.id)));
      case HistoryKind.edit || HistoryKind.system:
        final viewer = ref.read(accountsRepositoryProvider).viewerUid;
        if (viewer == null) return;
        final restored = restoreDraft(txn, revision, viewerUid: viewer);
        if (restored == null) {
          showUndoToast(
            context: context,
            message: context.l10n.activityEntryFailInvalid,
            actionLabel: context.l10n.activityEntryOk,
            onAction: () {},
          );
          return;
        }
        unawaited(
          _run(
            (r) => r.editEntry(txn.id, restored.draft, extras: restored.extras),
          ),
        );
      case HistoryKind.created || HistoryKind.restore:
        break;
    }
  }

  void _more(LedgerTransaction txn) {
    final l10n = context.l10n;
    unawaited(
      showXpActionSheet(
        context: context,
        cancelLabel: l10n.activityEntryCancel,
        actions: [
          if (txn.deleted)
            XpAction(
              label: l10n.activityEntryRestoreEntry,
              onPressed: () => unawaited(_run((r) => r.restoreEntry(txn.id))),
            )
          else ...[
            XpAction(
              label: l10n.activityEntryEdit,
              onPressed: () => _edit(EntryRowField.amount),
            ),
            XpAction(
              label: l10n.activityEntryDelete,
              destructive: true,
              onPressed: _delete,
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = XpColors.of(context);
    final entry = ref.watch(entryProvider(widget.txnId));
    final record = entry.value;
    return Scaffold(
      backgroundColor: colors.canvas,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            XpTopBar(
              title: l10n.activityEntryTitle,
              leading: const XpBackButton(),
              trailing: record == null
                  ? null
                  : GlassIconButton(
                      glyph: XpGlyph.more,
                      semanticLabel: l10n.activityEntryMore,
                      onPressed: _busy ? null : () => _more(record.txn),
                    ),
            ),
            Expanded(
              child: switch (entry) {
                AsyncData(value: final record?) => _EntryBody(
                  record: record,
                  busy: _busy,
                  onEdit: record.txn.deleted ? null : _edit,
                  onRestore: (item) => _restore(item, record.txn),
                  onDelete: _delete,
                  onRestoreEntry: () =>
                      unawaited(_run((r) => r.restoreEntry(record.txn.id))),
                ),
                AsyncLoading() => const Padding(
                  padding: EdgeInsetsDirectional.all(XpSpace.screenMargin),
                  child: Skeleton(rows: 6),
                ),
                _ => Center(
                  child: EmptyState(message: l10n.activityEntryNotFound),
                ),
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _EntryBody extends ConsumerWidget {
  const new({
    required this.record,
    required this.busy,
    required this.onEdit,
    required this.onRestore,
    required this.onDelete,
    required this.onRestoreEntry,
  });

  final EntryRecord record;
  final bool busy;
  final ValueChanged<String>? onEdit;
  final ValueChanged<HistoryItem> onRestore;
  final VoidCallback onDelete;
  final VoidCallback onRestoreEntry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final type = XpType.of(context);
    final colors = XpColors.of(context);
    final txn = record.txn;
    final locale = Localizations.localeOf(context).toLanguageTag();
    final now = ref.watch(clockProvider).now();
    final accounts = ref.watch(accountsProvider).value ?? const <Account>[];
    final members = ref.watch(householdMembersProvider).value ?? const [];
    final viewer = ref.watch(accountsRepositoryProvider).viewerUid;
    final base = switch (ref.watch(membershipProvider).value) {
      InHousehold(:final household) => household.baseCurrency,
      _ => txn.currency,
    };
    final revisions =
        ref.watch(entryRevisionsProvider(txn.id)).value ?? const [];
    final history = buildHistory(record, revisions);

    String accountName(Object? id) =>
        accounts.where((a) => a.id == id).firstOrNull?.name ??
        l10n.activityEntryNone;
    String categoryLabel(Object? id) =>
        defaultCategories
            .where((c) => c.slug == id)
            .firstOrNull
            ?.nameIn(fallbackLanguage) ??
        l10n.activityEntryNone;
    String person(Object? uid) {
      if (uid == null) return '';
      if (uid == viewer) return l10n.activityEntryWhoYou;
      final member = members.where((m) => m.uid == uid).firstOrNull;
      return member == null || member.displayName.isEmpty
          ? l10n.activityEntryWhoPartner
          : member.displayName;
    }

    String who(Object? scope, Object? uid) =>
        scope == WhoScope.joint.wire ? l10n.activityEntryWhoJoint : person(uid);
    String money(Object? minor, Object? code) {
      final currency = Currency.tryParse('$code');
      if (minor is! int || currency == null) return l10n.activityEntryNone;
      final figure = MoneyFormat.figure(
        minor,
        exponent: currency.exponent,
        currency: currency.code,
      );
      return '${figure.currency} ${figure.whole}${figure.fraction}';
    }

    // Each side reads the entry as it was then: an old USD amount stays
    // USD after the entry moved to an IQD account.
    String? change(HistoryItem item) {
      String pair(String before, String after) =>
          l10n.activityEntryHistoryChange(before, after);
      final changed = item.before;
      final b = item.beforeState;
      final a = item.afterState;
      return switch (item.onlyPart) {
        ChangedPart.amount when changed.containsKey('amountMinor') => pair(
          money(b['amountMinor'], b['currency']),
          money(a['amountMinor'], a['currency']),
        ),
        ChangedPart.account when changed.containsKey('accountId') => pair(
          accountName(b['accountId']),
          accountName(a['accountId']),
        ),
        ChangedPart.account => pair(
          accountName(b['toAccountId']),
          accountName(a['toAccountId']),
        ),
        ChangedPart.category => pair(
          categoryLabel(b['categoryId']),
          categoryLabel(a['categoryId']),
        ),
        ChangedPart.who => pair(
          who(b['whoScope'], b['whoUid']),
          who(a['whoScope'], a['whoUid']),
        ),
        ChangedPart.date => switch ((b['occurredAt'], a['occurredAt'])) {
          (final DateTime before, final DateTime after) => pair(
            l10n.entryWhen(before, now, locale),
            l10n.entryWhen(after, now, locale),
          ),
          _ => null,
        },
        ChangedPart.note => pair(
          '${b['note'] ?? l10n.activityEntryNone}',
          '${a['note'] ?? l10n.activityEntryNone}',
        ),
        _ => null,
      };
    }

    final fx = txn.fx;
    final category = txn.categoryId == null
        ? null
        : categoryLabel(txn.categoryId);
    final headerTail =
        category ??
        switch (txn.personName ?? (txn.title.isEmpty ? null : txn.title)) {
          final String name => name,
          null => null,
        };
    final converted = fx == null || txn.currency == base
        ? null
        : l10n.activityEntryConverted(
            money(txn.baseAmountMinor, base.code),
            _rateText(fx),
            l10n.entryRateLabel(fx.source),
          );
    final mode = l10n.entryModeLabel(txn.ai);
    final source = l10n.entrySourceLabel(txn.source);
    final edit = busy ? null : onEdit;
    final loanEvent = switch (txn.type) {
      LedgerType.loanGiven ||
      LedgerType.loanTaken ||
      LedgerType.repaymentReceived ||
      LedgerType.repaymentMade => true,
      _ => false,
    };
    final rows = <Widget>[
      if (txn.categoryId != null ||
          txn.type == LedgerType.expense ||
          txn.type == LedgerType.income)
        _row(
          l10n.activityEntryRowCategory,
          category ?? l10n.activityEntryNone,
          EntryRowField.category,
          edit,
        ),
      if (txn.type == LedgerType.transfer) ...[
        _row(
          l10n.activityEntryRowFrom,
          accountName(txn.accountId),
          EntryRowField.account,
          edit,
        ),
        _row(
          l10n.activityEntryRowTo,
          accountName(txn.toAccountId),
          EntryRowField.toAccount,
          edit,
        ),
        if (txn.toAmountMinor case final arrives?)
          _row(
            l10n.activityEntryRowArrives,
            money(
              arrives,
              accounts
                  .where((a) => a.id == txn.toAccountId)
                  .firstOrNull
                  ?.currency
                  .code,
            ),
            EntryRowField.toAccount,
            edit,
          ),
      ] else
        _row(
          l10n.activityEntryRowAccount,
          accountName(txn.accountId),
          EntryRowField.account,
          edit,
        ),
      if (loanEvent)
        _row(
          l10n.activityEntryRowPerson,
          txn.personName ??
              (txn.title.isEmpty ? l10n.activityEntryNone : txn.title),
          EntryRowField.person,
          edit,
        ),
      if (txn.type == LedgerType.expense || txn.type == LedgerType.income)
        _row(
          l10n.activityEntryRowWho,
          who(txn.whoScope.wire, txn.whoUid),
          EntryRowField.who,
          edit,
        ),
      _row(
        l10n.activityEntryRowWhen,
        l10n.entryWhen(txn.occurredAt, now, locale),
        EntryRowField.date,
        edit,
      ),
      _row(
        l10n.activityEntryRowNote,
        txn.note ?? l10n.activityEntryNoNote,
        EntryRowField.note,
        edit,
      ),
    ];

    return ListView(
      padding: EdgeInsetsDirectional.only(
        start: XpSpace.screenMargin,
        end: XpSpace.screenMargin,
        top: XpSpace.s8,
        bottom: XpSpace.bottomControlOffset(context) + XpSpace.s24,
      ),
      children: [
        Text(
          [
            l10n.entryTypeLabel(txn.type),
            ?headerTail,
          ].join(' · ').toUpperCase(),
          style: type.monoLabel.copyWith(color: colors.inkSecondary),
        ),
        const SizedBox(height: XpSpace.s4),
        XpPressable(
          onPressed: edit == null ? null : () => edit(EntryRowField.amount),
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: MoneyText(
              txn.amountMinor,
              exponent: txn.currency.exponent,
              currency: txn.currency.code,
              style: MoneyStyle.large,
              converted: converted?.toUpperCase(),
            ),
          ),
        ),
        if (txn.deleted || record.syncing) ...[
          const SizedBox(height: XpSpace.s8),
          Text(
            txn.deleted
                ? l10n.activityEntryDeletedNote
                : l10n.activityEntrySyncing,
            style: type.meta.copyWith(
              color: txn.deleted ? colors.danger : colors.inkSecondary,
            ),
          ),
        ],
        const SizedBox(height: XpSpace.s16),
        ...rows,
        const SizedBox(height: XpSpace.s16),
        if (fx != null)
          LedgerRow(
            label: l10n.activityEntryRateUsed,
            value: l10n
                .activityEntryRateValue(
                  _rateText(fx),
                  l10n.entryRateLabel(fx.source),
                )
                .toUpperCase(),
          ),
        LedgerRow(
          label: l10n.activityEntrySource,
          value:
              (mode == null
                      ? source
                      : l10n.activityEntrySourceValue(source, mode))
                  .toUpperCase(),
        ),
        const SizedBox(height: XpSpace.s24),
        SectionLabel(l10n.activityEntryRevisions),
        const SizedBox(height: XpSpace.s4),
        for (final item in history)
          HistoryRow(
            title: l10n.entryHistoryTitle(item, txn.source),
            detail: item.kind == HistoryKind.created
                ? money(
                    item.afterState['amountMinor'],
                    item.afterState['currency'],
                  )
                : change(item),
            when: [
              if (item.at case final at?) l10n.entryWhen(at, now, locale),
              if (person(item.actor) case final name when name.isNotEmpty) name,
            ].join(' · '),
            restoreLabel: item.restorable ? l10n.activityEntryRestore : null,
            onRestore: busy ? null : () => onRestore(item),
          ),
        const SizedBox(height: XpSpace.s24),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: txn.deleted
              ? XpButton.text(
                  label: l10n.activityEntryRestoreEntry,
                  onPressed: busy ? null : onRestoreEntry,
                )
              : XpButton.destructive(
                  label: l10n.activityEntryDelete,
                  onPressed: busy ? null : onDelete,
                ),
        ),
      ],
    );
  }

  static String _rateText(StoredFx fx) {
    final parts = fx.pairRate.split('.');
    final whole = int.tryParse(parts.first);
    if (whole == null) return fx.pairRate;
    final grouped = MoneyFormat.group(whole);
    return parts.length > 1 ? '$grouped.${parts[1]}' : grouped;
  }

  static Widget _row(
    String title,
    String value,
    String field,
    ValueChanged<String>? onEdit,
  ) => XpDisclosure(
    title: title,
    value: value,
    onTap: onEdit == null ? null : () => onEdit(field),
  );
}
