/// Step 2 of the fast parser, amounts: numbers that are money, with any
/// currency word written next to them (AI_PIPELINE 5).
library;

import 'package:decimal/decimal.dart';
import 'package:meta/meta.dart';
import 'package:xpense_shared/money/currency.dart';
import 'package:xpense_shared/parse/lexicon.dart';
import 'package:xpense_shared/parse/numbers.dart';
import 'package:xpense_shared/parse/tokens.dart';

final Decimal _hundredth = Decimal.parse('0.01');
final _phoneLike = RegExp(r'^0[0-9]{6,}$');

/// A money amount found in the text, before currency resolution.
@immutable
final class AmountMention {
  /// Creates a mention covering tokens `[tokenStart, tokenEnd)`.
  const new({
    required this.value,
    required this.start,
    required this.end,
    required this.tokenStart,
    required this.tokenEnd,
    required this.scaled,
    required this.words,
    this.currency,
  });

  /// The exact value in major units, as written (before dropped thousands).
  final Decimal value;

  /// Start offset in the normalised text (including a currency word).
  final int start;

  /// End offset (exclusive) in the normalised text.
  final int end;

  /// Index of the first token.
  final int tokenStart;

  /// Index after the last token.
  final int tokenEnd;

  /// Whether a thousand-or-larger multiplier was written.
  final bool scaled;

  /// Whether number words were used.
  final bool words;

  /// The currency named next to the number, if any.
  final Currency? currency;

  /// A copy with other values.
  AmountMention copyWith({
    Decimal? value,
    int? start,
    int? end,
    int? tokenStart,
    int? tokenEnd,
    Currency? currency,
  }) => AmountMention(
    value: value ?? this.value,
    start: start ?? this.start,
    end: end ?? this.end,
    tokenStart: tokenStart ?? this.tokenStart,
    tokenEnd: tokenEnd ?? this.tokenEnd,
    scaled: scaled,
    words: words,
    currency: currency ?? this.currency,
  );

  @override
  bool operator ==(Object other) =>
      other is AmountMention &&
      other.value == value &&
      other.start == start &&
      other.end == end &&
      other.scaled == scaled &&
      other.words == words &&
      other.currency == currency;

  @override
  int get hashCode => Object.hash(value, start, end, scaled, words, currency);

  @override
  String toString() => 'AmountMention($value ${currency?.code}@$start-$end)';
}

/// Finds the money amounts in [tokens], left to right.
///
/// Tokens whose index is in [blocked] (a date, an account name) are never
/// read as money. Numbers that are times (`5pm`, `5:30`), percentages,
/// ordinals (`5th`), fractions or dates with `/`, phone numbers (a leading
/// zero and seven or more digits) and quantities (`2 kg`, `x2`) are skipped.
/// A small number followed by a counted noun (`two coffees 6000`) is a
/// quantity when the message holds another amount. `5 dollars and 50 cents`
/// is one amount.
List<AmountMention> findAmounts(
  List<Token> tokens, {
  Set<int> blocked = const {},
  ParserLexicon lexicon = englishLexicon,
}) {
  final lex = lexicon;
  final found = <AmountMention>[];
  final counted = <int>{};
  var i = 0;
  while (i < tokens.length) {
    if (blocked.contains(i)) {
      i++;
      continue;
    }
    var phraseStart = i;
    Currency? prefix;
    final word = tokens[i].text;
    if (lex.prefixCurrencyWords.contains(word) &&
        i + 1 < tokens.length &&
        !blocked.contains(i + 1) &&
        canStartNumber(tokens[i + 1], lex)) {
      prefix = lex.currencyWords[word];
      phraseStart = i + 1;
    }
    final phrase = readNumber(tokens, phraseStart, lex);
    if (phrase == null ||
        _anyBlocked(blocked, phrase.tokenStart, phrase.tokenEnd)) {
      i++;
      continue;
    }
    if (_isNotMoney(tokens, phrase, lex)) {
      i = phrase.tokenEnd;
      continue;
    }
    var end = phrase.tokenEnd;
    var value = phrase.value;
    var currency = prefix;
    final suffix = _currencySuffix(tokens, end, lex, blocked);
    if (suffix != null) {
      final (suffixCurrency, minorUnit, suffixEnd) = suffix;
      currency ??= suffixCurrency;
      if (minorUnit && prefix == null) value = value * _hundredth;
      end = suffixEnd;
    }
    // A lone "one" with no currency is a pronoun ("the last one").
    if (currency == null &&
        phrase.words &&
        phrase.tokenEnd - phrase.tokenStart == 1 &&
        phrase.value == Decimal.one) {
      i = phrase.tokenEnd;
      continue;
    }
    final startToken = prefix != null ? i : phrase.tokenStart;
    final mention = AmountMention(
      value: value,
      start: tokens[startToken].start,
      end: tokens[end - 1].end,
      tokenStart: startToken,
      tokenEnd: end,
      scaled: phrase.scaled,
      words: phrase.words,
      currency: currency,
    );
    if (currency == null && _isCountedNoun(tokens, phrase, lex)) {
      counted.add(found.length);
    }
    found.add(mention);
    i = end;
  }
  final merged = _mergeCents(tokens, found, lex);
  if (counted.isEmpty || merged.length != found.length) return merged;
  // Drop counted quantities only when another amount remains.
  final kept = [
    for (var k = 0; k < found.length; k++)
      if (!counted.contains(k)) found[k],
  ];
  return kept.isEmpty ? found : kept;
}

bool _anyBlocked(Set<int> blocked, int from, int to) {
  for (var k = from; k < to; k++) {
    if (blocked.contains(k)) return true;
  }
  return false;
}

bool _isNotMoney(List<Token> tokens, NumberPhrase phrase, ParserLexicon lex) {
  final first = tokens[phrase.tokenStart];
  final end = phrase.tokenEnd;
  final next = end < tokens.length ? tokens[end] : null;
  final prev = phrase.tokenStart > 0 ? tokens[phrase.tokenStart - 1] : null;
  if (first.isNumber && _phoneLike.hasMatch(first.text)) return true;
  if (next != null && next.glued) {
    if (next.text == '%' || next.text == ':' || next.text == '/') return true;
    if (lex.ordinalSuffixes.contains(next.text)) return true;
    if (lex.timeSuffixes.contains(next.text)) return true;
    if (next.text == 'x') return true;
  }
  if (next != null && lex.timeSuffixes.contains(next.text)) return true;
  if (next != null && lex.quantityUnits.contains(next.text)) return true;
  if (prev != null && first.glued) {
    if (prev.text == '/' || prev.text == ':' || prev.text == '#') return true;
    if (prev.text == 'x') return true;
  }
  if (prev != null && prev.text == '#') return true;
  // "march 2026": a year after a month name.
  if (prev != null &&
      lex.months.containsKey(prev.text) &&
      first.isNumber &&
      RegExp(r'^(19|20)[0-9]{2}$').hasMatch(first.text)) {
    return true;
  }
  return false;
}

// (currency, isMinorUnit, endTokenIndex) for a currency word at [at].
(Currency, bool, int)? _currencySuffix(
  List<Token> tokens,
  int at,
  ParserLexicon lex,
  Set<int> blocked,
) {
  if (at >= tokens.length || blocked.contains(at)) return null;
  var k = at;
  if (lex.currencyQualifiers.contains(tokens[k].text) &&
      k + 1 < tokens.length &&
      lex.currencyWords.containsKey(tokens[k + 1].text)) {
    k++;
  }
  final text = tokens[k].text;
  final minor = lex.minorUnitWords[text];
  if (minor != null) return (minor, true, k + 1);
  final currency = lex.currencyWords[text];
  if (currency == null) return null;
  if (lex.gluedOnlyCurrencyWords.contains(text) && k != at) return null;
  return (currency, false, k + 1);
}

bool _isCountedNoun(
  List<Token> tokens,
  NumberPhrase phrase,
  ParserLexicon lex,
) {
  if (phrase.scaled) return false;
  if (phrase.value > Decimal.fromInt(20)) return false;
  if (!phrase.value.isInteger) return false;
  final end = phrase.tokenEnd;
  if (end >= tokens.length) return false;
  final next = tokens[end];
  if (!next.isWord || next.glued) return false;
  final w = next.text;
  if (lex.stopWords.contains(w) ||
      lex.currencyWords.containsKey(w) ||
      lex.minorUnitWords.containsKey(w) ||
      lex.scaleWords.containsKey(w) ||
      lex.conjunctions.contains(w) ||
      lex.activityVerbs.contains(w)) {
    return false;
  }
  // Digits need a plural noun (`2 coffees`); words take any noun
  // (`one coffee`), since "15 lunch" style entries are common with digits.
  return phrase.words || (w.length > 2 && w.endsWith('s'));
}

List<AmountMention> _mergeCents(
  List<Token> tokens,
  List<AmountMention> found,
  ParserLexicon lex,
) {
  if (found.length < 2) return found;
  final merged = <AmountMention>[];
  var k = 0;
  while (k < found.length) {
    final a = found[k];
    if (k + 1 < found.length) {
      final b = found[k + 1];
      final joined =
          a.currency == Currency.usd &&
          b.currency == Currency.usd &&
          b.tokenStart == a.tokenEnd + 1 &&
          lex.numberConnectives.contains(tokens[a.tokenEnd].text) &&
          lex.minorUnitWords.containsKey(tokens[b.tokenEnd - 1].text) &&
          !lex.minorUnitWords.containsKey(tokens[a.tokenEnd - 1].text);
      if (joined) {
        merged.add(
          a.copyWith(
            value: a.value + b.value,
            end: b.end,
            tokenEnd: b.tokenEnd,
          ),
        );
        k += 2;
        continue;
      }
    }
    merged.add(a);
    k++;
  }
  return merged;
}
