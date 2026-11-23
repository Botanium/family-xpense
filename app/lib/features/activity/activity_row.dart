import 'package:flutter/semantics.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import 'package:xpense_app/core/l10n/l10n.dart';
import 'package:xpense_app/core/theme/theme.dart';
import 'package:xpense_app/core/ui/ui.dart';
import 'package:xpense_app/data/transactions_repository.dart';
import 'package:xpense_app/features/activity/activity_controller.dart';
import 'package:xpense_app/features/activity/activity_model.dart';
import 'package:xpense_app/features/activity/swipe_actions.dart';
import 'package:xpense_shared/xpense_shared.dart';

/// What every row of one build needs to label itself, looked up once per
/// list build instead of once per row.
@immutable
final class ActivityRowLabels {
  /// Creates the lookups.
  const new({
    required this.accountNames,
    required this.baseCurrency,
    required this.people,
  });

  /// Account names by id.
  final Map<String, String> accountNames;

  /// The household base currency: amounts in it show no code.
  final Currency baseCurrency;

  /// The viewer and the partner.
  final ActivityPeople people;

  /// The row title: the merchant or label, else the counterparty, else the
  /// type.
  String title(AppLocalizations l10n, LedgerTransaction txn) {
    if (txn.title.trim().isNotEmpty) return txn.title;
    final person = txn.personName;
    if (person != null && person.isNotEmpty) return person;
    return typeName(l10n, txn.type);
  }

  /// The meta line: category or type, whose, account.
  String meta(AppLocalizations l10n, LedgerTransaction txn) {
    final kind =
        activityCategoryName(txn.categoryId) ?? typeName(l10n, txn.type);
    final who = switch (txn.whoScope) {
      WhoScope.joint => l10n.activityWhoJoint,
      WhoScope.member when txn.whoUid == people.viewerUid =>
        l10n.activityWhoYou,
      WhoScope.member => people.partnerName ?? l10n.activityWhoPartner,
    };
    String name(String? id) => accountNames[id] ?? l10n.activityUnknownAccount;
    final to = txn.toAccountId;
    final account = to == null
        ? name(txn.accountId)
        : l10n.activityTransferAccounts(name(txn.accountId), name(to));
    return l10n.activityRowMeta(kind, who, account);
  }

  /// A ledger type's name.
  static String typeName(AppLocalizations l10n, LedgerType type) =>
      switch (type) {
        LedgerType.expense => l10n.activityTypeExpense,
        LedgerType.income => l10n.activityTypeIncome,
        LedgerType.transfer => l10n.activityTypeTransfer,
        LedgerType.loanGiven => l10n.activityTypeLoanGiven,
        LedgerType.loanTaken => l10n.activityTypeLoanTaken,
        LedgerType.repaymentReceived => l10n.activityTypeRepaymentReceived,
        LedgerType.repaymentMade => l10n.activityTypeRepaymentMade,
        LedgerType.adjustment => l10n.activityTypeAdjustment,
      };
}

/// A day header: "Today", "Yesterday" or the date, and the day's net in
/// mono (income minus spending, base currency).
class ActivityDayHeaderView extends StatelessWidget {
  /// Creates the header of [day]; [today] is the household-local day.
  const new({
    required this.day,
    required this.today,
    required this.baseCurrency,
    super.key,
  });

  /// The group.
  final ActivityDay day;

  /// Today, `YYYY-MM-DD`.
  final DateTime today;

  /// The base currency.
  final Currency baseCurrency;

  /// The label for [day] seen on [today].
  static String label(BuildContext context, String day, DateTime today) {
    final l10n = context.l10n;
    final date = DateTime.tryParse(day);
    if (date == null) return day;
    final t = DateTime(today.year, today.month, today.day);
    final d = DateTime(date.year, date.month, date.day);
    final diff = t.difference(d).inDays;
    if (diff == 0) return l10n.activityToday;
    if (diff == 1) return l10n.activityYesterday;
    final locale = Localizations.localeOf(context).toLanguageTag();
    return d.year == t.year
        ? DateFormat.MMMd(locale).format(d)
        : DateFormat.yMMMd(locale).format(d);
  }

  @override
  Widget build(BuildContext context) {
    final type = XpType.of(context);
    final colors = XpColors.of(context);
    final l10n = context.l10n;
    final net = MoneyFormat.figure(
      day.netMinor,
      exponent: baseCurrency.exponent,
      signed: true,
    );
    return Padding(
      padding: const EdgeInsetsDirectional.only(
        top: XpSpace.s20,
        bottom: XpSpace.s4,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Expanded(
            child: Semantics(
              header: true,
              child: Text(
                label(context, day.day, today),
                style: type.subhead.copyWith(color: colors.inkSecondary),
              ),
            ),
          ),
          if (day.hasNet)
            Semantics(
              label: l10n.activityDayNet(net.amount),
              child: ExcludeSemantics(
                child: Text(
                  net.amount,
                  style: type.figureSmall.copyWith(color: colors.inkSecondary),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// One entry: title, meta line and signed amount, with swipe actions (Edit,
/// Delete) and the long-press context menu.
class ActivityEntryRow extends StatelessWidget {
  /// Creates the row.
  const new({
    required this.txn,
    required this.labels,
    required this.group,
    required this.onOpen,
    required this.onEdit,
    required this.onDelete,
    this.syncing = false,
    this.last = false,
    super.key,
  });

  /// The entry.
  final LedgerTransaction txn;

  /// Lookups for the labels.
  final ActivityRowLabels labels;

  /// The list's swipe group.
  final SwipeGroup group;

  /// Opens the entry's detail.
  final VoidCallback onOpen;

  /// Opens the edit form.
  final VoidCallback onEdit;

  /// Deletes it (with the undo toast).
  final VoidCallback onDelete;

  /// Whether a write to it is still on the phone only.
  final bool syncing;

  /// Whether it is the last row of its day (no hairline under it).
  final bool last;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = XpColors.of(context);
    final sign = amountSignOf(txn);
    final amount = MoneyText(
      sign == AmountSign.minus ? -txn.amountMinor : txn.amountMinor,
      exponent: txn.currency.exponent,
      currency: txn.currency == labels.baseCurrency ? '' : txn.currency.code,
      tone: sign == AmountSign.plus ? MoneyTone.income : MoneyTone.neutral,
      textAlign: TextAlign.end,
    );
    final row = XpListRow(
      title: labels.title(l10n, txn),
      subtitle: labels.meta(l10n, txn),
      showDivider: !last,
      onTap: onOpen,
      // Inside the row's merged node, so VoiceOver offers Edit and Delete
      // on the row itself (swiping is invisible to it).
      trailing: Semantics(
        customSemanticsActions: {
          CustomSemanticsAction(label: l10n.activityEdit): onEdit,
          CustomSemanticsAction(label: l10n.activityDelete): onDelete,
        },
        child: syncing
            ? Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Dot(
                    color: colors.inkTertiary,
                    size: XpSpace.dotUnread,
                    semanticLabel: l10n.activitySyncing,
                  ),
                  const SizedBox(width: XpSpace.s6),
                  amount,
                ],
              )
            : amount,
      ),
    );
    return SwipeActions(
      id: txn.id,
      group: group,
      onFullSwipe: onDelete,
      actions: [
        SwipeAction(label: l10n.activityEdit, onPressed: onEdit),
        SwipeAction(
          label: l10n.activityDelete,
          destructive: true,
          onPressed: onDelete,
        ),
      ],
      child: Padding(
        padding: const EdgeInsetsDirectional.symmetric(
          horizontal: XpSpace.screenMargin,
        ),
        child: XpContextMenu(
          actions: [
            XpAction(label: l10n.activityEdit, onPressed: onEdit),
            XpAction(
              label: l10n.activityDelete,
              destructive: true,
              onPressed: onDelete,
            ),
          ],
          // The lifted copy may get a height a fraction of a point short of
          // the row's while it animates; clip instead of overflowing.
          child: UnconstrainedBox(
            constrainedAxis: Axis.horizontal,
            alignment: AlignmentDirectional.topStart,
            clipBehavior: Clip.hardEdge,
            child: row,
          ),
        ),
      ),
    );
  }
}
