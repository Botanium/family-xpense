/// Checks drafts on a surface before they are saved (A2UI_CATALOG 9).
///
/// Drafts reach the phone as plain JSON in a surface's data model, written
/// by the agent or the local builder and edited on the phone. These
/// functions are synchronous and total: a draft whose shape is wrong is
/// reported, never thrown on, so `EntryList` can show it as "Needs review".
/// The same checks can guard agent output on the server.
library;

import 'package:xpense_shared/money/currency.dart';
import 'package:xpense_shared/money/money.dart';
import 'package:xpense_shared/money/result.dart';
import 'package:xpense_shared/schema/entry_draft.dart';
import 'package:xpense_shared/schema/wire_values.dart';
import 'package:xpense_shared/surface/surface_builder.dart';
import 'package:xpense_shared/taxonomy/categories.dart';
import 'package:xpense_shared/taxonomy/intents.dart';

/// Largest amount a draft may carry, in minor units (A2UI_CATALOG 9).
const int maxDraftAmountMinor = 1000000000000;

/// The ids the phone's household cache knows.
final class HouseholdRefs {
  /// Creates the reference sets.
  const new({
    this.accountCurrencies = const {},
    this.categoryIds = const {},
    this.categoryKinds = const {},
    this.personIds = const {},
    this.loanIds = const {},
    this.goalIds = const {},
  });

  /// Every account the member can see, with its currency code.
  final Map<String, String> accountCurrencies;

  /// Every category id.
  final Set<String> categoryIds;

  /// The kind (`expense` or `income`) of each category whose kind is
  /// known; a category not listed here is not checked for its kind.
  final Map<String, String> categoryKinds;

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

/// An expense filed under an income category, or the reverse. The server
/// treats such a category as no answer and asks again (`prepare_entries`),
/// and the write path refuses it (`EntryIssue.wrongCategoryKind`); the
/// slip asks for the category again too ([DraftCheck.missing]).
final class WrongCategoryKind extends DraftIssue {
  /// Creates the issue.
  const new({required this.categoryId, required this.expected})
    : super('categoryId');

  /// The category the draft names.
  final String categoryId;

  /// The kind the entry's intent takes: `expense` or `income`.
  final String expected;

  @override
  String toString() => 'WrongCategoryKind($categoryId, not $expected)';
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

  /// The fields still to answer, in asking order. A category of the wrong
  /// kind is asked again, as the server does.
  List<String> get missing => [
    for (final issue in issues)
      if (issue is MissingField ||
          (issue is WrongCategoryKind && !_listsMissing(issue.field)))
        issue.field,
  ];

  bool _listsMissing(String field) =>
      issues.any((i) => i is MissingField && i.field == field);

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
/// question), then required fields that are empty. A destination equal to
/// the source is unanswered too: a transfer never goes to its own account.
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
    if (draft.toAccountId != null && draft.toAccountId == draft.accountId)
      'toAccountId',
  }.toList();
}

/// [draft] (a draft's JSON) with the currency of the account just picked
/// for it, [accountCurrency].
///
/// An account holds only its own currency. When the draft's currency was
/// only guessed (it is in `guessed`: the member named no currency), it
/// follows the account, and the amount the member wrote keeps its major
/// units: "groceries 45" guessed as 45.00 USD is 45 IQD on a dinar account.
/// An amount the new currency cannot hold ("12.50" in dinars) is removed, so
/// the slip asks for it. The currency stays guessed, so picking another
/// account moves it again. The duplicate hint and FX quote, worked out for
/// the old figures, are dropped. A currency the member wrote is left alone; the
/// slip then reports [CurrencyMismatch] rather than change their words.
Map<String, Object?> followAccountCurrency(
  Map<String, Object?> draft,
  String? accountCurrency,
) {
  final from = draft['currency'];
  final guessed = draft['guessed'];
  final to = Currency.tryParse(accountCurrency ?? '');
  if (to == null ||
      from == to.code ||
      guessed is! List ||
      !guessed.contains('currency')) {
    return draft;
  }
  // The currency stays in `guessed`: it came from the account, not the
  // member's words, so a later pick moves it again.
  // The duplicate hint and the FX quote were worked out for the old
  // amount and currency; the server does not see a pick on the phone.
  final next = Map<String, Object?>.of(draft)
    ..['currency'] = to.code
    ..remove('duplicate')
    ..remove('fx');
  final amount = draft['amountMinor'];
  if (amount is int) {
    final old = Currency.tryParse(from is String ? from : '');
    final moved = old == null
        ? null
        : Money.parseMajor(Money(amount, old).toMajorString(), to);
    if (moved case Ok(:final value)) {
      next['amountMinor'] = value.minorUnits;
    } else {
      next.remove('amountMinor');
    }
  }
  return next;
}

List<DraftIssue> _referenceIssues(EntryDraft d, HouseholdRefs refs) {
  final issues = <DraftIssue>[];
  void ref(String field, String? id, bool Function(String) known) {
    if (id != null && !known(id)) issues.add(UnknownReference(field, id));
  }

  ref('accountId', d.accountId, refs.accountCurrencies.containsKey);
  ref('toAccountId', d.toAccountId, refs.accountCurrencies.containsKey);
  ref('categoryId', d.categoryId, refs.categoryIds.contains);
  final expected = switch (CaptureIntent.tryParse(d.intent)) {
    CaptureIntent.expense => CategoryKind.expense.wire,
    CaptureIntent.income => CategoryKind.income.wire,
    _ => null,
  };
  final kind = refs.categoryKinds[d.categoryId];
  if (expected != null && kind != null && kind != expected) {
    issues.add(
      WrongCategoryKind(categoryId: d.categoryId!, expected: expected),
    );
  }
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

/// Whether [value] is absent or passes [ok].
bool _optional(Object? value, bool Function(Object) ok) =>
    value == null || ok(value);

/// A probability or confidence: a number from 0 to 1.
bool _share(Object value) => value is num && value >= 0 && value <= 1;

/// A whole number (`5` or `5.0`) within [min] and [max] when given.
bool _wholeIn(Object value, int? min, int? max) {
  if (value is! num || !value.isFinite || value != value.truncate()) {
    return false;
  }
  return (min == null || value >= min) && (max == null || value <= max);
}

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
  // Nested objects too: their generated getters cast without checking, so
  // a wrong type here would throw while the slip renders.
  isNullOr(
    'confidence',
    (v) =>
        v is Map &&
        [
          'intent',
          'category',
          'account',
          'who',
        ].every((k) => _optional(v[k], _share)),
  );
  isNullOr(
    'recurring',
    (v) =>
        v is Map &&
        _optional(v['probability'], _share) &&
        _optional(v['unit'], (u) => inSet(u, cadenceUnitValues)) &&
        _optional(v['interval'], (n) => _wholeIn(n, 1, null)) &&
        _optional(v['dayOfMonth'], (n) => _wholeIn(n, 1, 31)) &&
        _optional(v['weekday'], (n) => _wholeIn(n, 1, 7)) &&
        _optional(v['recurringId'], (id) => id is String),
  );
  isNullOr(
    'fx',
    (v) =>
        v is Map &&
        v['pair'] is String &&
        v['pairRate'] is String &&
        _optional(v['source'], (src) => inSet(src, fxSourceValues)) &&
        _optional(v['asOf'], (d) => d is String && _date.hasMatch(d)) &&
        _optional(v['baseAmountMinor'], (n) => _wholeIn(n, null, null)),
  );
  isNullOr(
    'duplicate',
    (v) =>
        v is Map && v['txnId'] is String && _optional(v['probability'], _share),
  );
  return issues;
}
