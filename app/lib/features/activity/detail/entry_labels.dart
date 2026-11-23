import 'package:intl/intl.dart';
import 'package:xpense_app/core/l10n/generated/app_localizations.dart';
import 'package:xpense_app/data/transactions_repository.dart';
import 'package:xpense_app/features/activity/detail/entry_history.dart';
import 'package:xpense_shared/xpense_shared.dart';

/// The words entry detail uses for types, sources, rates and history.
extension EntryLabels on AppLocalizations {
  /// The type's name, such as "Expense".
  String entryTypeLabel(LedgerType type) => switch (type) {
    LedgerType.expense => activityEntryTypeExpense,
    LedgerType.income => activityEntryTypeIncome,
    LedgerType.transfer => activityEntryTypeTransfer,
    LedgerType.loanGiven => activityEntryTypeLoanGiven,
    LedgerType.loanTaken => activityEntryTypeLoanTaken,
    LedgerType.repaymentReceived => activityEntryTypeRepaymentReceived,
    LedgerType.repaymentMade => activityEntryTypeRepaymentMade,
    LedgerType.adjustment => activityEntryTypeAdjustment,
  };

  /// The source's name, such as "Voice".
  String entrySourceLabel(EntrySource source) => switch (source) {
    EntrySource.manual => activityEntrySourceManual,
    EntrySource.chat => activityEntrySourceChat,
    EntrySource.voice => activityEntrySourceVoice,
    EntrySource.receipt => activityEntrySourceReceipt,
    EntrySource.recurring => activityEntrySourceRecurring,
    EntrySource.imported => activityEntrySourceImport,
    EntrySource.shortcut => activityEntrySourceShortcut,
  };

  /// The first history row's title, such as "Created by voice".
  String entryCreatedLabel(EntrySource source) => switch (source) {
    EntrySource.manual => activityEntryCreatedManual,
    EntrySource.chat => activityEntryCreatedChat,
    EntrySource.voice => activityEntryCreatedVoice,
    EntrySource.receipt => activityEntryCreatedReceipt,
    EntrySource.recurring => activityEntryCreatedRecurring,
    EntrySource.imported => activityEntryCreatedImport,
    EntrySource.shortcut => activityEntryCreatedShortcut,
  };

  /// The rate's label, such as "Market".
  String entryRateLabel(String source) => switch (source) {
    'official' => activityEntryRateOfficial,
    'manual' => activityEntryRateManual,
    _ => activityEntryRateMarket,
  };

  /// Where an AI path understood the entry; null for an entry no model
  /// read (`ai.path` is the draft's origin).
  String? entryModeLabel(Map<String, Object?>? ai) => switch (ai?['path']) {
    'parser' || 'rule' || 'on_device' => activityEntryModeOnDevice,
    'decisions' || 'agent' => activityEntryModeCloud,
    _ => null,
  };

  /// A history row's title.
  String entryHistoryTitle(HistoryItem item, EntrySource source) =>
      switch (item.kind) {
        HistoryKind.created => entryCreatedLabel(source),
        HistoryKind.delete => activityEntryHistoryDeleted,
        HistoryKind.undo => activityEntryHistoryUndone,
        HistoryKind.restore => activityEntryHistoryRestored,
        HistoryKind.system => activityEntryHistorySystem,
        HistoryKind.edit => switch (item.onlyPart) {
          null => activityEntryChangedMany,
          ChangedPart.amount => activityEntryChangedAmount,
          ChangedPart.account => activityEntryChangedAccount,
          ChangedPart.category => activityEntryChangedCategory,
          ChangedPart.who => activityEntryChangedWho,
          ChangedPart.date => activityEntryChangedDate,
          ChangedPart.note => activityEntryChangedNote,
          ChangedPart.person => activityEntryChangedPerson,
          ChangedPart.type => activityEntryChangedType,
          ChangedPart.rate => activityEntryChangedRate,
        },
      };

  /// "Today 13:20", "Yesterday 09:10" or "Nov 20 13:20", in local time.
  String entryWhen(DateTime at, DateTime now, String locale) {
    final local = at.toLocal();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(local.year, local.month, local.day);
    final time = DateFormat.Hm(locale).format(local);
    final days = today.difference(day).inDays;
    if (days == 0) return activityEntryToday(time);
    if (days == 1) return activityEntryYesterday(time);
    final date = local.year == now.year
        ? DateFormat.MMMd(locale).format(local)
        : DateFormat.yMMMd(locale).format(local);
    return activityEntryOnDay(date, time);
  }
}
