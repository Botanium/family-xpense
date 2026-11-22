/// The fast parser (AI_PIPELINE 5): deterministic, on-device, no model,
/// no I/O. [parseText] runs steps 1 to 8 and returns a [FastParse], whose
/// [FastParse.toParseResult] is the shared `ParseResult` contract.
library;

import 'package:clock/clock.dart';
import 'package:decimal/decimal.dart';
import 'package:meta/meta.dart';
import 'package:xpense_shared/money/currency.dart';
import 'package:xpense_shared/money/money.dart';
import 'package:xpense_shared/money/result.dart';
import 'package:xpense_shared/parse/amounts.dart';
import 'package:xpense_shared/parse/dates.dart';
import 'package:xpense_shared/parse/hints.dart';
import 'package:xpense_shared/parse/lexicon.dart';
import 'package:xpense_shared/parse/normalize.dart';
import 'package:xpense_shared/parse/rules.dart';
import 'package:xpense_shared/parse/signals.dart';
import 'package:xpense_shared/parse/tokens.dart';
import 'package:xpense_shared/schema/parse_result.dart';
import 'package:xpense_shared/taxonomy/intents.dart';

/// An amount of this many major units or more, with no currency word, is
/// assumed to be IQD (AI_PIPELINE 5, step 4).
const int iqdMagnitudeThreshold = 10000;

/// Bare numbers below this many major units may be dropped thousands
/// (AI_PIPELINE 5, step 3).
const int droppedThousandsLimit = 1000;

final _thousand = Decimal.fromInt(1000);
final _four = Decimal.fromInt(4);

/// What the parser knows about the household when it reads a message.
@immutable
final class ParseContext {
  /// Creates a context. [clock] gives the household-local wall time; its
  /// date is "today" for relative dates.
  const new({
    required this.clock,
    this.languageCode = 'en',
    this.accounts = const [],
    this.people = const [],
    this.categories = const [],
    this.rules = const [],
    this.defaultAccountId,
    this.attachment = Attachment.none,
  });

  /// The injected clock; read once per parse.
  final Clock clock;

  /// The message language, which picks the lexicon (English only, D-36).
  final String languageCode;

  /// The accounts the member can see.
  final List<ParserAccount> accounts;

  /// The household's people.
  final List<ParserPerson> people;

  /// The household's categories.
  final List<ParserCategory> categories;

  /// Learned rules from the local cache.
  final List<ParserRule> rules;

  /// The member's default account id.
  final String? defaultAccountId;

  /// The attachment that came with the message.
  final Attachment attachment;

  /// The account with [id], or `null`.
  ParserAccount? accountById(String? id) {
    if (id == null) return null;
    for (final a in accounts) {
      if (a.id == id) return a;
    }
    return null;
  }

  /// The category with [id], or `null`.
  ParserCategory? categoryById(String? id) {
    if (id == null) return null;
    for (final c in categories) {
      if (c.id == id) return c;
    }
    return null;
  }
}

/// Where an amount's currency came from.
enum CurrencySource {
  /// A currency word next to the amount or elsewhere in the message.
  word,

  /// The account named in the message.
  namedAccount,

  /// The account set by a learned rule.
  ruleAccount,

  /// The member's default account.
  defaultAccount,

  /// The magnitude check: 10,000 or more is IQD.
  magnitude,

  /// Fractional digits that IQD cannot hold, so USD.
  decimals,

  /// No source: the currency is unknown.
  none,
}

/// An amount after currency resolution and dropped thousands.
@immutable
final class ResolvedAmount {
  /// Creates a resolved amount.
  const new({
    required this.mention,
    required this.value,
    required this.currency,
    required this.source,
    required this.guessed,
    required this.droppedThousands,
    required this.money,
    required this.span,
  });

  /// The mention as found in the text.
  final AmountMention mention;

  /// The final value in major units (after dropped thousands).
  final Decimal value;

  /// The resolved currency, or `null` when unknown.
  final Currency? currency;

  /// Where [currency] came from.
  final CurrencySource source;

  /// Whether the amount or its currency was inferred and should show the
  /// "Guessed" badge.
  final bool guessed;

  /// Whether the bare number was read as thousands.
  final bool droppedThousands;

  /// The exact money, or `null` when the currency is unknown or the value
  /// does not fit it (`42.5 dinars`, too large).
  final Money? money;

  /// The matched text.
  final String span;

  /// The schema form.
  ParsedAmount toSchema() => ParsedAmount(
    amountMinor: money?.minorUnits,
    currency: currency?.code,
    value: value.toString(),
    span: span,
    start: mention.start,
    end: mention.end,
    guessed: guessed,
  );

  @override
  bool operator ==(Object other) =>
      other is ResolvedAmount &&
      other.mention == mention &&
      other.value == value &&
      other.currency == currency &&
      other.source == source &&
      other.guessed == guessed &&
      other.droppedThousands == droppedThousands &&
      other.money == money;

  @override
  int get hashCode => Object.hash(
    mention,
    value,
    currency,
    source,
    guessed,
    droppedThousands,
    money,
  );

  @override
  String toString() =>
      'ResolvedAmount($value ${currency?.code} ${source.name}'
      '${guessed ? ' guessed' : ''})';
}

/// The full result of one fast parse.
@immutable
final class FastParse {
  /// Creates a result.
  const new({
    required this.text,
    required this.amounts,
    required this.currency,
    required this.date,
    required this.dateMention,
    required this.hints,
    required this.ruleHits,
    required this.intentCue,
    required this.signals,
  });

  /// The normalised text all offsets refer to.
  final String text;

  /// Amounts in message order.
  final List<ResolvedAmount> amounts;

  /// The message-level currency when every amount agrees (or, with no
  /// amount, the one currency word in the message).
  final Currency? currency;

  /// The resolved date (today when [dateMention] is `null`).
  final LocalDate date;

  /// The date expression found, if any.
  final DateMention? dateMention;

  /// Account, person, category and who hints, by position.
  final List<HintMatch> hints;

  /// Winning rule hits, one per field.
  final List<AppliedRule> ruleHits;

  /// The intent the message states in so many words, if any.
  ///
  /// `ParseResult` has no field for it yet; it is why `intent` can be
  /// missing from [Signals.unresolved] without a rule hit.
  final CaptureIntent? intentCue;

  /// The router's complexity signals.
  final Signals signals;

  /// The shared schema form (AI_PIPELINE 5, step 8).
  ParseResult toParseResult() => ParseResult(
    amounts: [for (final a in amounts) a.toSchema()],
    currency: currency?.code,
    date: date.iso,
    hints: [
      for (final h in hints)
        ParseHint(
          kind: h.kind.wire,
          span: h.span,
          id: h.id,
          who: h.who,
          confidence: h.confidence,
        ),
    ],
    ruleHits: [for (final r in ruleHits) r.toSchema()],
    signals: signals.toSchema(),
  );
}

/// Parses one typed or transcribed message. Total: any string gives a
/// result, never an exception.
FastParse parseText(String raw, ParseContext context) {
  final lex = lexiconFor(context.languageCode);
  final normalized = normalize(raw);
  final text = normalized.text;
  final tokens = tokenize(text);
  final today = LocalDate.fromDateTime(context.clock.now());

  // Step 5: dates first, so their numbers are never read as money.
  final dateMention = findDate(tokens, today, lex);

  // Step 6: hints, so names with digits are never read as money.
  final hints = findHints(
    text,
    accounts: context.accounts,
    people: context.people,
    categories: context.categories,
    lexicon: lex,
  );

  final blocked = <int>{
    if (dateMention != null)
      for (var k = dateMention.tokenStart; k < dateMention.tokenEnd; k++) k,
    for (var k = 0; k < tokens.length; k++)
      if (hints.any((h) => _inside(tokens[k], h.start, h.end))) k,
  };

  // Steps 2 and 4: amounts with any currency word next to them.
  final mentions = findAmounts(tokens, blocked: blocked, lexicon: lex);

  // Currency words not attached to an amount ("dollars: lunch 15").
  final amountTokens = {
    for (final m in mentions)
      for (var k = m.tokenStart; k < m.tokenEnd; k++) k,
  };
  final floating = <Currency>{
    for (var k = 0; k < tokens.length; k++)
      if (!amountTokens.contains(k) &&
          !blocked.contains(k) &&
          !lex.gluedOnlyCurrencyWords.contains(tokens[k].text))
        ?lex.currencyWords[tokens[k].text],
  };
  final floatingCurrency = floating.length == 1 ? floating.single : null;

  // Step 7: learned rules.
  final ruleHits = applyRules(text, context.rules);
  String? ruleValue(RuleField field) {
    for (final r in ruleHits) {
      if (r.field == field) return r.value;
    }
    return null;
  }

  final namedAccount = hints
      .where((h) => h.kind == HintKind.account && h.currency != null)
      .firstOrNull;
  final ruleAccount = context.accountById(ruleValue(RuleField.accountId));
  final defaultAccount = context.accountById(context.defaultAccountId);

  final amounts = [
    for (final m in mentions)
      _resolve(
        m,
        text: text,
        floatingCurrency: floatingCurrency,
        namedAccount: namedAccount?.currency,
        ruleAccount: ruleAccount?.currency,
        defaultAccount: defaultAccount?.currency,
      ),
  ];

  final currencies = {for (final a in amounts) ?a.currency};
  final messageCurrency = amounts.isEmpty
      ? floatingCurrency
      : currencies.length == 1 && amounts.every((a) => a.currency != null)
      ? currencies.single
      : null;

  // Names not yet saved, next to a transfer verb.
  final transferVerbs = findTransferVerbs(tokens, lex);
  final unknownNames = findUnknownNames(
    normalized,
    tokens,
    transferVerbs,
    taken: [for (final h in hints) (h.start, h.end)],
    lexicon: lex,
  );
  final allHints = [...hints, ...unknownNames]
    ..sort((a, b) => a.start.compareTo(b.start));

  final personNamed =
      allHints.any((h) => h.kind == HintKind.person) ||
      tokens.any((t) => lex.relationWords.contains(t.text));
  final isQuestion = detectQuestion(text, tokens, lex);
  final isCommand = detectCommand(text, tokens, lex);
  // Questions and commands record nothing, so they state no money intent.
  final intentCue = isQuestion || isCommand
      ? null
      : detectIntentCue(tokens, personNamed: personNamed, lexicon: lex);

  final ignored = <int>{
    ...blocked,
    for (var k = 0; k < tokens.length; k++)
      if (allHints.any((h) => _inside(tokens[k], h.start, h.end))) k,
  };

  final signals = Signals(
    amountCount: amounts.length,
    hasConjunction: detectConjunction(
      tokens,
      mentions,
      ignored: ignored,
      lexicon: lex,
    ),
    isQuestion: isQuestion,
    isCommand: isCommand,
    hasPersonTransfer: detectPersonTransfer(tokens, allHints, lexicon: lex),
    unresolved: _unresolved(
      context: context,
      hints: allHints,
      ruleIntent: ruleValue(RuleField.intent),
      ruleCategory: ruleValue(RuleField.categoryId),
      ruleAccount: ruleValue(RuleField.accountId),
      intentCue: intentCue,
    ),
    attachment: context.attachment,
  );

  return FastParse(
    text: text,
    amounts: amounts,
    currency: messageCurrency,
    date: dateMention?.date ?? today,
    dateMention: dateMention,
    hints: allHints,
    ruleHits: ruleHits,
    intentCue: intentCue,
    signals: signals,
  );
}

bool _inside(Token token, int start, int end) =>
    token.start >= start && token.end <= end;

ResolvedAmount _resolve(
  AmountMention mention, {
  required String text,
  required Currency? floatingCurrency,
  required Currency? namedAccount,
  required Currency? ruleAccount,
  required Currency? defaultAccount,
}) {
  final raw = mention.value;
  var guessed = false;
  Currency? currency;
  CurrencySource source;

  if (mention.currency != null) {
    currency = mention.currency;
    source = CurrencySource.word;
  } else if (floatingCurrency != null) {
    currency = floatingCurrency;
    source = CurrencySource.word;
  } else {
    final fromAccount = namedAccount != null
        ? (namedAccount, CurrencySource.namedAccount)
        : ruleAccount != null
        ? (ruleAccount, CurrencySource.ruleAccount)
        : defaultAccount != null
        ? (defaultAccount, CurrencySource.defaultAccount)
        : (null, CurrencySource.none);
    (currency, source) = fromAccount;
    final large = raw >= Decimal.fromInt(iqdMagnitudeThreshold);
    if (large && currency != Currency.iqd) {
      currency = Currency.iqd;
      source = CurrencySource.magnitude;
      guessed = true;
    }
  }

  // Step 3: dropped thousands.
  var value = raw;
  var dropped = false;
  final bare = !mention.scaled;
  if (currency == Currency.iqd &&
      source != CurrencySource.magnitude &&
      bare &&
      raw > Decimal.zero &&
      raw < Decimal.fromInt(droppedThousandsLimit) &&
      (raw * _four).isInteger) {
    value = raw * _thousand;
    dropped = true;
    guessed = true;
  }

  Money? money;
  if (currency != null) {
    money = Money.parseMajor(value.toString(), currency).valueOrNull;
    if (money == null &&
        currency == Currency.iqd &&
        source != CurrencySource.word &&
        !value.isInteger) {
      // IQD has no decimals: "42.80" with an IQD default is dollars.
      final usd = Money.parseMajor(value.toString(), Currency.usd).valueOrNull;
      if (usd != null) {
        currency = Currency.usd;
        source = CurrencySource.decimals;
        guessed = true;
        money = usd;
      }
    }
  }

  return ResolvedAmount(
    mention: mention,
    value: value,
    currency: currency,
    source: source,
    guessed: guessed,
    droppedThousands: dropped,
    money: money,
    span: text.substring(mention.start, mention.end),
  );
}

List<UnresolvedField> _unresolved({
  required ParseContext context,
  required List<HintMatch> hints,
  required String? ruleIntent,
  required String? ruleCategory,
  required String? ruleAccount,
  required CaptureIntent? intentCue,
}) {
  // Intent: a rule, else explicit words, else a rule-set category's kind.
  var intent = CaptureIntent.tryParse(ruleIntent ?? '') ?? intentCue;
  final ruleCategoryKind = context.categoryById(ruleCategory)?.kind;
  intent ??= ruleCategoryKind == 'income'
      ? CaptureIntent.income
      : ruleCategoryKind == 'expense'
      ? CaptureIntent.expense
      : null;
  final needsCategory =
      intent == null ||
      intent == CaptureIntent.expense ||
      intent == CaptureIntent.income;
  final accountSettled =
      ruleAccount != null ||
      context.accounts.length == 1 ||
      hints.any((h) => h.kind == HintKind.account && h.id != null);
  return [
    if (needsCategory && ruleCategory == null) UnresolvedField.category,
    if (!accountSettled) UnresolvedField.account,
    if (intent == null) UnresolvedField.intent,
  ];
}
