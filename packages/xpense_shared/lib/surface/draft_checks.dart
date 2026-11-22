/// Checks drafts on a surface before they are saved (A2UI_CATALOG 9).
///
/// Drafts reach the phone as plain JSON in a surface's data model, written
/// by the agent or the local builder and edited on the phone. These
/// functions are synchronous and total: a draft whose shape is wrong is
/// reported, never thrown on, so `EntryList` can show it as "Needs review".
/// The same checks can guard agent output on the server.
library;

import 'package:xpense_shared/money/currency.dart';
import 'package:xpense_shared/schema/entry_draft.dart';
import 'package:xpense_shared/schema/wire_values.dart';
import 'package:xpense_shared/surface/surface_builder.dart';
import 'package:xpense_shared/taxonomy/intents.dart';

/// Largest amount a draft may carry, in minor units (A2UI_CATALOG 9).
const int maxDraftAmountMinor = 1000000000000;

/// The ids the phone's household cache knows.
final class HouseholdRefs {
  /// Creates the reference sets.
  const new({
    this.accountCurrencies = const {},
    this.categoryIds = const {},
    this.personIds = const {},
    this.loanIds = const {},
    this.goalIds = const {},
  });

  /// Every account the member can see, with its currency code.
  final Map<String, String> accountCurrencies;

  /// Every category id.
  final Set<String> categoryIds;

  /// Every person (counterparty) id.
  final Set<String> personIds;

  /// Every loan id.
  final Set<String> loanIds;

  /// Every goal id.
  final Set<String> goalIds;
}

/// Something that stops a draft from being saved as it is.
sealed class DraftIssue {
  const new(this.field);

  /// The draft field the issue is about.
  final String field;
}

/// A field holds a value of the wrong type or outside its set. The draft
/// cannot be read; it needs the manual form.
final class MalformedField extends DraftIssue {
  /// Creates the issue.
  const new(super.field);

  @override
  String toString() => 'MalformedField($field)';
}

/// A required field is empty or still unanswered.
final class MissingField extends DraftIssue {
  /// Creates the issue.
  const new(super.field);

  @override
  String toString() => 'MissingField($field)';
}

/// A field names an id the household does not have.
final class UnknownReference extends DraftIssue {
  /// Creates the issue.
  const new(super.field, this.id);

  /// The unknown id.
  final String id;

  @override
  String toString() => 'UnknownReference($field: $id)';
}

/// The amount is outside `1 … 10^12` minor units.
final class DraftAmountOutOfRange extends DraftIssue {
  /// Creates the issue.
  const new(this.amountMinor) : super('amountMinor');

  /// The amount as given.
  final int amountMinor;

  @override
  String toString() => 'DraftAmountOutOfRange($amountMinor)';
}

/// The draft's currency differs from its account's currency.
final class CurrencyMismatch extends DraftIssue {
  /// Creates the issue.
  const new({required this.accountCurrency, required this.draftCurrency})
    : super('currency');

  /// The account's currency.
  final String accountCurrency;

  /// The draft's currency.
  final String draftCurrency;

  @override
  String toString() => 'CurrencyMismatch($draftCurrency ≠ $accountCurrency)';
}

/// The result of checking one draft.
final class DraftCheck {
  /// Creates a result.
  const new({required this.raw, required this.draft, required this.issues});

  /// The draft as found in the data model.
  final Object? raw;

  /// The typed draft, or null when its shape is wrong ([isMalformed]).
  final EntryDraft? draft;

  /// Everything that stops a save, missing fields first in asking order.
  final List<DraftIssue> issues;

  /// Whether the draft cannot be read and needs the manual form.
  bool get isMalformed => draft == null;

  /// The fields still to answer, in asking order.
  List<String> get missing => [
    for (final issue in issues)
      if (issue is MissingField) issue.field,
  ];

  /// Whether this draft can be saved as it is.
  bool get canSave => draft != null && issues.isEmpty;
}

/// The result of checking every draft of a surface.
final class DraftsCheck {
  /// Creates a result.
  const new({required this.drafts, required this.tooMany});

  /// One result per draft, in order.
  final List<DraftCheck> drafts;

  /// Whether there are more than [maxDraftsPerSurface] drafts.
  final bool tooMany;

  /// Whether every draft can be saved.
  bool get canSave =>
      !tooMany && drafts.isNotEmpty && drafts.every((d) => d.canSave);
}

/// Checks every draft in [raw] (the value at `/drafts`) against [refs].
DraftsCheck checkDrafts(Object? raw, HouseholdRefs refs) {
  final list = raw is List ? raw : const <Object?>[];
  return DraftsCheck(
    drafts: [for (final item in list) checkDraft(item, refs)],
    tooMany: list.length > maxDraftsPerSurface,
  );
}

/// Checks one draft: its shape, the fields still to answer, and its ids,
/// amount and currency against [refs].
DraftCheck checkDraft(Object? raw, HouseholdRefs refs) {
  final shape = _shapeIssues(raw);
  if (shape.isNotEmpty) {
    return DraftCheck(raw: raw, draft: null, issues: shape);
  }
  final json = (raw! as Map).cast<String, dynamic>();
  final draft = EntryDraft.fromJson(json);
  return DraftCheck(
    raw: raw,
    draft: draft,
    issues: [
      for (final field in missingFields(draft)) MissingField(field),
      ..._referenceIssues(draft, refs),
    ],
  );
}

/// The fields of [draft] still to answer: those the producer listed in
/// `missing` (even if a provisional value is present, as for an intent
/// question), then required fields that are empty.
List<String> missingFields(EntryDraft draft) {
  final listed = draft.missing ?? const [];
  final required = <String>[
    'amountMinor',
    'currency',
    'accountId',
    'occurredOn',
    ...switch (CaptureIntent.tryParse(draft.intent)) {
      CaptureIntent.expense || CaptureIntent.income => ['categoryId'],
      CaptureIntent.transfer => ['toAccountId'],
      CaptureIntent.savingsMove when draft.goalId == null => ['toAccountId'],
      CaptureIntent.loanGiven ||
      CaptureIntent.loanTaken ||
      CaptureIntent.repaymentReceived ||
      CaptureIntent.repaymentMade when draft.personId == null => ['personName'],
      _ => const <String>[],
    },
  ];
  final json = draft.toJson();
  return {
    ...listed,
    for (final field in required)
      if (json[field] == null) field,
  }.toList();
}

List<DraftIssue> _referenceIssues(EntryDraft d, HouseholdRefs refs) {
  final issues = <DraftIssue>[];
  void ref(String field, String? id, bool Function(String) known) {
    if (id != null && !known(id)) issues.add(UnknownReference(field, id));
  }

  ref('accountId', d.accountId, refs.accountCurrencies.containsKey);
  ref('toAccountId', d.toAccountId, refs.accountCurrencies.containsKey);
  ref('categoryId', d.categoryId, refs.categoryIds.contains);
  ref('personId', d.personId, refs.personIds.contains);
  ref('loanId', d.loanId, refs.loanIds.contains);
  ref('goalId', d.goalId, refs.goalIds.contains);
  final amount = d.amountMinor;
  if (amount != null && (amount < 1 || amount > maxDraftAmountMinor)) {
    issues.add(DraftAmountOutOfRange(amount));
  }
  final accountCurrency = refs.accountCurrencies[d.accountId];
  final currency = d.currency;
  if (accountCurrency != null &&
      currency != null &&
      accountCurrency != currency) {
    issues.add(
      CurrencyMismatch(
        accountCurrency: accountCurrency,
        draftCurrency: currency,
      ),
    );
  }
  return issues;
}

final RegExp _date = RegExp(r'^\d{4}-\d{2}-\d{2}$');
final RegExp _time = RegExp(r'^\d{2}:\d{2}$');

const List<String> _plainStrings = [
  'accountId',
  'toAccountId',
  'categoryId',
  'personName',
  'personId',
  'loanId',
  'goalId',
];

/// Type and set checks on the raw JSON; explicit nulls are allowed, as a
/// model or reloaded state may write them.
List<DraftIssue> _shapeIssues(Object? raw) {
  if (raw is! Map || raw.keys.any((k) => k is! String)) {
    return const [MalformedField('draft')];
  }
  final issues = <DraftIssue>[];
  bool isNullOr(String field, bool Function(Object v) ok) {
    final Object? value = raw[field];
    final good = value == null || ok(value);
    if (!good) issues.add(MalformedField(field));
    return good;
  }

  bool inSet(Object v, List<String> values) =>
      v is String && values.contains(v);
  bool stringList(Object v) => v is List && v.every((e) => e is String);

  final Object? id = raw['id'];
  if (id is! String || id.isEmpty) issues.add(const MalformedField('id'));
  final intent = (raw['intent'] as Object?) ?? '';
  if (!inSet(intent, entryIntentWireValues)) {
    issues.add(const MalformedField('intent'));
  }
  isNullOr(
    'amountMinor',
    (v) => v is int || (v is double && v == v.truncate()),
  );
  isNullOr('currency', (v) => inSet(v, supportedCurrencyCodes));
  isNullOr('who', (v) => inSet(v, whoValues));
  isNullOr('origin', (v) => inSet(v, draftOriginValues));
  isNullOr('occurredOn', (v) => v is String && _date.hasMatch(v));
  isNullOr('occurredTime', (v) => v is String && _time.hasMatch(v));
  isNullOr('title', (v) => v is String && v.length <= 80);
  isNullOr('note', (v) => v is String && v.length <= 500);
  for (final field in _plainStrings) {
    isNullOr(field, (v) => v is String);
  }
  isNullOr('guessed', stringList);
  isNullOr('missing', stringList);
  isNullOr('confidence', (v) => v is Map);
  isNullOr('recurring', (v) => v is Map);
  isNullOr(
    'fx',
    (v) => v is Map && v['pair'] is String && v['pairRate'] is String,
  );
  isNullOr('duplicate', (v) => v is Map && v['txnId'] is String);
  return issues;
}
