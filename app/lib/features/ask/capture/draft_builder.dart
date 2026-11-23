/// Drafts for paths L and D (ARCHITECTURE 5.1 and 5.2): the fast parse,
/// learned rules, an optional on-device extraction and optional Decisions
/// answers become one `EntryDraft` for the local surface builder.
///
/// Pure. The field policy mirrors the agent's `prepareEntries`
/// (`server/lib/tools/prepare_entries.dart`), so the same message gives
/// the same slip on every path.
library;

import 'package:clock/clock.dart';
import 'package:flutter/foundation.dart';
import 'package:xpense_app/a2ui/xpense_surface_host.dart';
import 'package:xpense_app/features/ask/capture/confidence_policy.dart';
import 'package:xpense_app/services/decisions_client.dart';
import 'package:xpense_shared/xpense_shared.dart';

/// The parser's view of [household] with the learned [rules].
///
/// A category's kind comes from the default taxonomy by id (category ids
/// are the default slugs, DATA_MODEL 2.6); unknown ids count as expense.
ParseContext parseContextFor(
  XpenseHousehold household, {
  required Clock clock,
  List<ParserRule> rules = const [],
  String? defaultAccountId,
}) => ParseContext(
  clock: clock,
  accounts: [
    for (final a in household.accounts)
      if (Currency.tryParse(a.currency) case final currency?)
        ParserAccount(id: a.id, name: a.name, currency: currency),
  ],
  people: [
    for (final p in household.people) ParserPerson(id: p.id, name: p.name),
  ],
  categories: [
    for (final c in household.categories)
      ParserCategory(
        id: c.id,
        names: {'en': c.name},
        kind: categoryKindOf(c.id),
      ),
  ],
  rules: rules,
  defaultAccountId: defaultAccountId,
);

/// `income` or `expense` for category [id], from the default taxonomy.
String categoryKindOf(String id) {
  for (final c in defaultCategories) {
    if (c.slug == id) return c.kind.wire;
  }
  return CategoryKind.expense.wire;
}

/// A draft's title and the kind of rule a correction to it would teach.
@immutable
final class DraftTitle {
  /// Creates a title.
  const new(this.text, this.kind);

  /// The title as the member wrote it, such as "Costco".
  final String text;

  /// `merchant` after "at" or "from", otherwise `keyword`.
  final RuleKind kind;

  @override
  bool operator ==(Object other) =>
      other is DraftTitle && other.text == text && other.kind == kind;

  @override
  int get hashCode => Object.hash(text, kind);

  @override
  String toString() => 'DraftTitle($text, ${kind.wire})';
}

const _merchantMarkers = {'at', 'from'};
const _stopWords = {
  'a',
  'an',
  'the',
  'and',
  'or',
  'on',
  'in',
  'for',
  'to',
  'of',
  'with',
  'my',
  'our',
  'me',
  'i',
  'we',
  'it',
  'was',
  'is',
  'were',
  'just',
  'some',
  'spent',
  'spend',
  'paid',
  'pay',
  'bought',
  'buy',
  'got',
  'cost',
  'costs',
  'today',
  'yesterday',
  'tonight',
  'this',
  'that',
  'by',
  'using',
  'via',
  'dollars',
  'dollar',
  'usd',
  'dinars',
  'dinar',
  'iqd',
  'bucks',
  'k',
  'from',
  'at',
};

/// The words of [raw] that name what the entry was for: the words after
/// "at" or "from" (a merchant), else the remaining content words, at most
/// four, in the member's casing. Null when nothing is left.
DraftTitle? titleOf(String raw, FastParse parse) {
  final normalized = normalize(raw);
  final text = normalized.text;
  final cased = normalized.cased;
  final taken = <(int, int)>[
    for (final a in parse.amounts) (a.mention.start, a.mention.end),
    if (parse.dateMention case final d?) (d.start, d.end),
    for (final h in parse.hints) (h.start, h.end),
  ];
  bool isTaken(Token t) => taken.any((s) => t.start < s.$2 && t.end > s.$1);
  final tokens = tokenize(text);
  final words = <Token>[];
  for (final t in tokens) {
    if (t.kind != TokenKind.word) continue;
    words.add(t);
  }
  String casedOf(Token t) => cased.substring(t.start, t.end);
  bool content(Token t) => !isTaken(t) && !_stopWords.contains(t.text);

  // A merchant: the run of content words right after "at" or "from".
  for (var i = 0; i < words.length; i++) {
    if (!_merchantMarkers.contains(words[i].text) || isTaken(words[i])) {
      continue;
    }
    final run = <Token>[];
    for (var j = i + 1; j < words.length && run.length < 4; j++) {
      if (!content(words[j])) break;
      run.add(words[j]);
    }
    if (run.isNotEmpty) {
      return DraftTitle(run.map(casedOf).join(' '), RuleKind.merchant);
    }
  }
  final rest = [
    for (final t in words)
      if (content(t) &&
          !parse.ruleHits.any((r) => t.start >= r.start && t.end <= r.end))
        t,
  ];
  // A rule's own pattern is the best title: it is what taught the rule.
  if (parse.ruleHits.isNotEmpty) {
    final r = parse.ruleHits.first;
    return DraftTitle(cased.substring(r.start, r.end), RuleKind.merchant);
  }
  if (rest.isEmpty) return null;
  return DraftTitle(rest.take(4).map(casedOf).join(' '), RuleKind.keyword);
}

/// The question keys to send to `/decide` for [parse] (AI_PIPELINE 7):
/// only what the parser and rules left open. `person` is asked only when
/// a person is named, `to_account` only on a transfer cue, `is_recurring`
/// for spending and income (WP-33 hand-over), `duplicate` when the amount
/// and its currency are known, which is what the server's candidate search
/// needs.
List<String> decideQuestionsFor(FastParse parse) {
  final unresolved = parse.signals.unresolved;
  final intent = _settledIntent(parse);
  final transfer =
      intent == CaptureIntent.transfer || intent == CaptureIntent.savingsMove;
  final personNamed = parse.hints.any((h) => h.kind == HintKind.person);
  final whoKnown =
      parse.hints.any((h) => h.kind == HintKind.who) ||
      parse.ruleHits.any((r) => r.field == RuleField.who);
  final categoryIntent =
      intent == null ||
      intent == CaptureIntent.expense ||
      intent == CaptureIntent.income;
  return [
    if (unresolved.contains(UnresolvedField.intent)) 'intent',
    if (unresolved.contains(UnresolvedField.account)) 'account',
    if (transfer) 'to_account',
    if (unresolved.contains(UnresolvedField.category) && categoryIntent)
      'category',
    if (!whoKnown) 'who',
    if (personNamed) 'person',
    if (categoryIntent) 'is_recurring',
    if (_duplicateSearchable(parse)) 'duplicate',
  ];
}

/// Whether the server can look for duplicate candidates: the same amount
/// and currency the request's `parsed` carries.
bool _duplicateSearchable(FastParse parse) {
  final amount = parse.amounts.firstOrNull;
  return amount?.money != null && (amount?.currency ?? parse.currency) != null;
}

/// The `/decide` request for [raw] and its [parse].
DecideRequest decideRequestFor(String raw, FastParse parse) {
  final amount = parse.amounts.firstOrNull;
  final result = parse.toParseResult();
  return DecideRequest(
    text: raw,
    lang: 'en',
    parsed: DecideParsed(
      amountMinor: amount?.money?.minorUnits,
      currency: amount?.currency?.code ?? parse.currency?.code,
      date: parse.date.iso,
    ),
    hints: result.hints,
    ask: decideQuestionsFor(parse),
  );
}

/// The intent the parse settles without a model: a rule, the member's
/// own words, or the kind of a rule-set category.
CaptureIntent? _settledIntent(FastParse parse) {
  String? rule(RuleField f) =>
      parse.ruleHits.where((r) => r.field == f).firstOrNull?.value;
  final fromRule = CaptureIntent.tryParse(rule(RuleField.intent) ?? '');
  if (fromRule != null) return fromRule;
  if (parse.intentCue case final cue?) return cue;
  final category = rule(RuleField.categoryId);
  if (category == null) return null;
  return categoryKindOf(category) == CategoryKind.income.wire
      ? CaptureIntent.income
      : CaptureIntent.expense;
}

/// Where a draft's classification came from.
enum DraftSource {
  /// The fast parser and rules only (path L).
  parser,

  /// The Decisions API (path D).
  decisions,

  /// An on-device extraction, then possibly Decisions (row 7).
  onDevice,
}

/// Builds the draft for one single-entry message.
///
/// [decide] holds the Decisions answers (path D), [extracted] an on-device
/// extraction (row 7, uncalibrated). Fields the parse settled win; then
/// Decisions; then the extraction, capped and always guessed.
EntryDraft buildDraft({
  required String id,
  required String raw,
  required FastParse parse,
  required XpenseHousehold household,
  required ConfidencePolicy policy,
  DecideResponse? decide,
  EntryDraft? extracted,
}) {
  final confidence = <String, double>{};
  final guessed = <String>{};
  final listedMissing = <String>{};
  final calibrated = decide?.calibrated ?? true;
  String? rule(RuleField f) =>
      parse.ruleHits.where((r) => r.field == f).firstOrNull?.value;

  // Intent.
  var intent = _settledIntent(parse);
  if (intent == null) {
    final answer = decide?.intent;
    final choice = CaptureIntent.tryParse(answer?.choice ?? '');
    if (answer != null && choice != null) {
      final p = policy.cap(
        (answer.probabilities?[choice.wire] ?? answer.confidence ?? 0)
            .toDouble(),
        calibrated: calibrated,
      );
      confidence['intent'] = p;
      intent = choice;
      if (!policy.intentSettled(p)) listedMissing.add('intent');
    } else if (CaptureIntent.tryParse(extracted?.intent ?? '')
        case final fromModel?) {
      intent = fromModel;
      listedMissing.add('intent');
    } else {
      intent = CaptureIntent.expense;
      listedMissing.add('intent');
    }
  }
  final hasCategory =
      intent == CaptureIntent.expense || intent == CaptureIntent.income;
  final isTransfer =
      intent == CaptureIntent.transfer || intent == CaptureIntent.savingsMove;

  // Amount and currency.
  final amount = parse.amounts.firstOrNull;
  var amountMinor = amount?.money?.minorUnits;
  var currency = amount?.currency?.code ?? parse.currency?.code;
  final currencyGuessed = amount != null && amount.guessed && currency != null;
  if (currencyGuessed) guessed.add('currency');
  // Set when a guessed currency moved to the chosen account's: the
  // duplicate answer was about the old figures.
  var currencyFollowed = false;

  // As in the agent's `prepareEntries`: an account holds only its own
  // currency. A guessed currency follows the chosen account, with the
  // amount read again in it; a written one is kept. Returns whether
  // [account] can hold the entry's currency now.
  bool followAccount(HouseholdAccount account) {
    if (currency == null || account.currency == currency) return true;
    if (!currencyGuessed) return false;
    final c = Currency.tryParse(account.currency);
    if (c == null) return false;
    if (Money.parseMajor(amount.value.toString(), c) case Ok(:final value)) {
      currency = account.currency;
      amountMinor = value.minorUnits;
      currencyFollowed = true;
      return true;
    }
    return false;
  }

  // Account: a rule, the account named, the only account, then Decisions.
  var accountId = rule(RuleField.accountId);
  var accountNamed = false;
  if (accountId != null) {
    confidence['account'] = ruleHitConfidence;
  } else if (parse.hints
          .where((h) => h.kind == HintKind.account && h.id != null)
          .firstOrNull
      case final named?) {
    accountId = named.id;
    accountNamed = true;
    confidence['account'] = 1;
  } else if (household.accounts.length == 1) {
    accountId = household.accounts.single.id;
    confidence['account'] = 1;
  } else if (policy.pick(decide?.account, calibrated: calibrated)
      case final p?) {
    confidence['account'] = p.confidence;
    final account = household.account(p.value);
    // A written currency rules another account out.
    if (account != null && followAccount(account)) {
      accountId = account.id;
      if (p.show == FieldShow.guessed) guessed.add('accountId');
    }
  }
  // An account the rules, the words or the household settled keeps it;
  // a guessed currency moves to it.
  if (household.account(accountId) case final account?) {
    followAccount(account);
  }
  // A currency the parser could not read: the account's, else the base
  // currency, and the amount read in it. As in the agent's
  // `prepareEntries`, it stays Guessed unless the member named the account.
  if (currency == null && amount != null) {
    final fromAccount = household.account(accountId)?.currency;
    final code = fromAccount ?? household.baseCurrency;
    currency = code;
    if (fromAccount == null || !accountNamed) guessed.add('currency');
    if (Currency.tryParse(code) case final c?) {
      if (Money.parseMajor(amount.value.toString(), c) case Ok(:final value)) {
        amountMinor = value.minorUnits;
      }
    }
  }

  String? toAccountId;
  if (isTransfer) {
    if (policy.pick(decide?.toAccount, calibrated: calibrated) case final p?) {
      if (household.account(p.value) != null && p.value != accountId) {
        toAccountId = p.value;
        if (p.show == FieldShow.guessed) guessed.add('toAccountId');
      }
    }
  }

  // Category: a rule, the category named, Decisions, then the extraction.
  // Only a category of the entry's kind is an answer (an income category
  // on spending is not), as in the agent's `prepareEntries`; one of the
  // other kind leaves the category to ask.
  String? categoryId;
  if (hasCategory) {
    final kind = intent == CaptureIntent.income
        ? CategoryKind.income.wire
        : CategoryKind.expense.wire;
    bool fits(String? id) =>
        id != null &&
        household.category(id) != null &&
        categoryKindOf(id) == kind;
    categoryId = rule(RuleField.categoryId);
    if (categoryId != null) {
      confidence['category'] = ruleHitConfidence;
    } else if (parse.hints
            .where((h) => h.kind == HintKind.category && fits(h.id))
            .firstOrNull
        case final named?) {
      categoryId = named.id;
      confidence['category'] = 1;
    } else if (policy.pick(decide?.category, calibrated: calibrated)
        case final p?) {
      if (fits(p.value)) {
        confidence['category'] = p.confidence;
        categoryId = p.value;
        if (p.show == FieldShow.guessed) guessed.add('categoryId');
      }
    } else if (fits(extracted?.categoryId)) {
      final c = policy.cap(
        extracted?.confidence?.category ?? policy.thresholds.low,
        calibrated: false,
      );
      if (policy.showFor(c) != FieldShow.ask) {
        categoryId = extracted!.categoryId;
        confidence['category'] = c;
        guessed.add('categoryId');
      }
    }
  }

  // Who.
  var who =
      rule(RuleField.who) ??
      parse.hints.where((h) => h.kind == HintKind.who).firstOrNull?.who;
  if (who != null) {
    confidence['who'] = 1;
  } else if (policy.pick(decide?.who, calibrated: calibrated) case final p?) {
    confidence['who'] = p.confidence;
    if (whoValues.contains(p.value)) {
      who = p.value;
      if (p.show == FieldShow.guessed) guessed.add('who');
    }
  }

  // Person.
  final personHint = parse.hints
      .where((h) => h.kind == HintKind.person)
      .firstOrNull;
  var personId = personHint?.id;
  var personName = personHint == null
      ? null
      : household.person(personHint.id)?.name ?? personHint.span;
  if (personId == null && personHint != null) {
    if (policy.pick(decide?.person, calibrated: calibrated) case final p?) {
      if (household.person(p.value) case final person?) {
        personId = person.id;
        personName = person.name;
        if (p.show == FieldShow.guessed) guessed.add('personId');
      }
    }
  }

  // Recurring and duplicate hints.
  RecurringHint? recurring;
  if (decide?.isRecurring?.probability case final p?
      when hasCategory && policy.offersRecurring(p)) {
    recurring = RecurringHint(probability: p, unit: 'month', interval: 1);
  }
  final duplicate = decide == null || currencyFollowed
      ? null
      : duplicateHintFrom(
          decide,
          warnAt: policy.thresholds.duplicateWarn,
          uncalibratedCap: policy.thresholds.onDeviceCap,
        );

  // No exchange-rate quote: the write path prices the entry with the
  // household's rate for the entry's date (the server's first), and the
  // slip shows its preview from the latest rate without storing it.

  final title = titleOf(raw, parse)?.text;
  final draft = EntryDraft(
    id: id,
    intent: intent.wire,
    amountMinor: amountMinor,
    currency: currency,
    accountId: accountId,
    toAccountId: toAccountId,
    categoryId: categoryId,
    who: who,
    occurredOn: parse.date.iso,
    title: title == null || title.length <= 80 ? title : title.substring(0, 80),
    personName: personName,
    personId: personId,
    confidence: confidence.isEmpty
        ? null
        : DraftConfidence(
            intent: confidence['intent'],
            category: confidence['category'],
            account: confidence['account'],
            who: confidence['who'],
          ),
    guessed: guessed.isEmpty ? null : (guessed.toList()..sort()),
    missing: listedMissing.isEmpty ? null : listedMissing.toList(),
    duplicate: duplicate,
    recurring: recurring,
    origin: decide != null
        ? 'decisions'
        : extracted != null
        ? 'on_device'
        : parse.ruleHits.isNotEmpty
        ? 'rule'
        : 'parser',
  );
  final missing = inFollowUpOrder(missingFields(draft));
  return EntryDraft.fromJson(
    {...draft.toJson(), 'missing': missing.isEmpty ? null : missing}
      ..removeWhere((_, v) => v == null),
  );
}
