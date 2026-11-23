/// Draft fields as the smart components show and edit them: labels,
/// picker options built from the household, and the write-back that also
/// clears the field from `missing` and `guessed`.
library;

import 'package:material_ui/material_ui.dart';
import 'package:xpense_app/a2ui/widgets/format.dart';
import 'package:xpense_app/a2ui/xpense_actions.dart';
import 'package:xpense_app/core/l10n/l10n.dart';
import 'package:xpense_shared/xpense_shared.dart';

/// One answer a picker offers for a field.
final class FieldOption {
  /// Creates an option.
  const new({required this.value, required this.label});

  /// The value written to the draft.
  final Object value;

  /// What the member sees.
  final String label;
}

/// The label of an intent wire value.
String intentLabel(BuildContext context, String? intent) {
  final l10n = context.l10n;
  return switch (CaptureIntent.tryParse(intent ?? '')) {
    CaptureIntent.expense => l10n.a2uiIntentExpense,
    CaptureIntent.income => l10n.a2uiIntentIncome,
    CaptureIntent.transfer => l10n.a2uiIntentTransfer,
    CaptureIntent.savingsMove => l10n.a2uiIntentSavingsMove,
    CaptureIntent.loanGiven => l10n.a2uiIntentLoanGiven,
    CaptureIntent.loanTaken => l10n.a2uiIntentLoanTaken,
    CaptureIntent.repaymentReceived => l10n.a2uiIntentRepaymentReceived,
    CaptureIntent.repaymentMade => l10n.a2uiIntentRepaymentMade,
    CaptureIntent.adjustment => l10n.a2uiIntentAdjustment,
    CaptureIntent.question ||
    CaptureIntent.command ||
    CaptureIntent.other ||
    null => l10n.a2uiIntentUnknown,
  };
}

/// The label of a `who` value.
String whoLabel(BuildContext context, XpenseHousehold household, String? who) {
  final l10n = context.l10n;
  return switch (who) {
    'me' => l10n.a2uiWhoMe,
    'partner' => household.partnerName ?? l10n.a2uiWhoPartner,
    'joint' => l10n.a2uiWhoJoint,
    _ => '',
  };
}

/// Whether money of [intent] comes into the account (labelled "Into").
bool _incoming(String? intent) =>
    const {'income', 'loan_taken', 'repayment_received'}.contains(intent);

/// The field rows a slip shows for [draft], in order: (field, label).
List<(String, String)> slipFields(BuildContext context, EntryDraft draft) {
  final l10n = context.l10n;
  final intent = draft.intent;
  final account = _incoming(intent) ? l10n.a2uiFieldInto : l10n.a2uiFieldFrom;
  return switch (intent) {
    'expense' || 'income' => [
      ('who', l10n.a2uiFieldWho),
      ('occurredOn', l10n.a2uiFieldWhen),
      ('accountId', account),
    ],
    'transfer' => [
      ('occurredOn', l10n.a2uiFieldWhen),
      ('accountId', l10n.a2uiFieldFrom),
      ('toAccountId', l10n.a2uiFieldTo),
    ],
    'savings_move' => [
      ('occurredOn', l10n.a2uiFieldWhen),
      ('accountId', l10n.a2uiFieldFrom),
      if (draft.goalId != null)
        ('goalId', l10n.a2uiFieldGoal)
      else
        ('toAccountId', l10n.a2uiFieldTo),
    ],
    'loan_given' ||
    'loan_taken' ||
    'repayment_received' ||
    'repayment_made' => [
      ('personName', l10n.a2uiFieldWith),
      ('occurredOn', l10n.a2uiFieldWhen),
      ('accountId', account),
    ],
    _ => [('occurredOn', l10n.a2uiFieldWhen), ('accountId', account)],
  };
}

/// What a field of [draft] shows, or null when it is empty.
String? fieldValue(
  BuildContext context,
  XpenseHousehold household,
  EntryDraft draft,
  String field,
) => switch (field) {
  'who' => draft.who == null ? null : whoLabel(context, household, draft.who),
  'occurredOn' =>
    draft.occurredOn == null
        ? null
        : dayLabel(context, draft.occurredOn, time: draft.occurredTime),
  'accountId' => _name(
    household.account(draft.accountId)?.name,
    draft.accountId,
  ),
  'toAccountId' => _name(
    household.account(draft.toAccountId)?.name,
    draft.toAccountId,
  ),
  'categoryId' => _name(
    household.category(draft.categoryId)?.name,
    draft.categoryId,
  ),
  'personName' => household.person(draft.personId)?.name ?? draft.personName,
  'goalId' => _name(household.goal(draft.goalId)?.name, draft.goalId),
  'intent' => intentLabel(context, draft.intent),
  _ => null,
};

String? _name(String? known, String? id) => known ?? id;

/// The question asked for a missing [field].
String fieldQuestion(BuildContext context, String field) {
  final l10n = context.l10n;
  return switch (field) {
    'accountId' => l10n.a2uiAskAccount,
    'toAccountId' => l10n.a2uiAskToAccount,
    'categoryId' => l10n.a2uiAskCategory,
    'who' => l10n.a2uiAskWho,
    'occurredOn' => l10n.a2uiAskDay,
    'personName' => l10n.a2uiAskPerson,
    'goalId' => l10n.a2uiAskGoal,
    'intent' => l10n.a2uiAskIntent,
    _ => l10n.a2uiAskInForm,
  };
}

/// The answers a picker offers for [field] of [draft], the current value
/// first, then in the household's order. Drafts carry no per-option
/// probabilities yet, so that is the ranking. Empty for fields only the
/// manual form can set (amount, currency).
List<FieldOption> fieldOptions(
  BuildContext context,
  XpenseHousehold household,
  EntryDraft draft,
  String field,
) {
  final l10n = context.l10n;
  final options = switch (field) {
    // A guessed currency follows the account picked (withField), so every
    // account is offered; a written one rules out other currencies.
    'accountId' || 'toAccountId' => [
      for (final a in household.accounts)
        if (draft.currency == null ||
            a.currency == draft.currency ||
            (field == 'accountId' &&
                (draft.guessed ?? const []).contains('currency')))
          if (field == 'accountId' || a.id != draft.accountId)
            FieldOption(value: a.id, label: a.name),
    ],
    'categoryId' => [
      for (final c in household.categories)
        FieldOption(value: c.id, label: c.name),
    ],
    'who' => [
      for (final who in whoValues)
        if (who != 'partner' || household.partnerName != null)
          FieldOption(value: who, label: whoLabel(context, household, who)),
    ],
    'occurredOn' => [
      FieldOption(value: dayString(today()), label: l10n.a2uiDayToday),
      FieldOption(value: dayString(yesterday()), label: l10n.a2uiDayYesterday),
    ],
    'personName' => [
      for (final p in household.people) FieldOption(value: p.id, label: p.name),
    ],
    'goalId' => [
      for (final g in household.goals) FieldOption(value: g.id, label: g.name),
    ],
    'intent' => [
      for (final intent in entryIntentWireValues)
        if (intent != 'adjustment')
          FieldOption(value: intent, label: intentLabel(context, intent)),
    ],
    _ => const <FieldOption>[],
  };
  final current = switch (field) {
    'personName' => draft.personId,
    _ => draft.toJson()[field],
  };
  return [
    ...options.where((o) => o.value == current),
    ...options.where((o) => o.value != current),
  ];
}

/// [draft] with [field] set to [value], and the field cleared from
/// `missing` and `guessed`: the member answered it. Picking a person sets
/// both its id and its name. Picking an account settles a guessed currency
/// ([followAccountCurrency]), given the [household].
Map<String, Object?> withField(
  Map<String, Object?> draft,
  String field,
  Object? value, {
  XpenseHousehold? household,
}) {
  final next = Map<String, Object?>.of(draft);
  if (field == 'personName' && value is String) {
    next['personId'] = value;
    next['personName'] = household?.person(value)?.name ?? value;
  } else {
    next[field] = value;
  }
  for (final list in ['missing', 'guessed']) {
    final values = next[list];
    if (values is List) {
      final rest = [
        for (final v in values)
          if (v != field) v,
      ];
      if (rest.isEmpty) {
        next.remove(list);
      } else {
        next[list] = rest;
      }
    }
  }
  if (field == 'accountId' && value is String && household != null) {
    return followAccountCurrency(next, household.account(value)?.currency);
  }
  return next;
}

/// The lowest confidence a draft carries, for its header ("94%").
double? lowestConfidence(EntryDraft draft) {
  final c = draft.confidence;
  if (c == null) return null;
  final values = [c.intent, c.category, c.account, c.who].nonNulls;
  return values.isEmpty ? null : values.reduce((a, b) => a < b ? a : b);
}
