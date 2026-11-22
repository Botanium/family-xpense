/// Step 2 of the fast parser, numbers: digits with separators, `k` and `m`
/// suffixes, number words and multipliers (AI_PIPELINE 5).
///
/// Values are exact [Decimal]s; nothing here uses `double`.
library;

import 'package:decimal/decimal.dart';
import 'package:meta/meta.dart';
import 'package:xpense_shared/parse/lexicon.dart';
import 'package:xpense_shared/parse/tokens.dart';

final _digitsOnly = RegExp(r'^[0-9]+$');
final Decimal _half = Decimal.parse('0.5');
final Decimal _quarter = Decimal.parse('0.25');

/// Parses one number token with `,` or `.` separators into an exact value,
/// or `null` when the separators make no sense (`1.2.3`).
///
/// Rules, in order:
/// - Both `,` and `.`: the one that comes last is the decimal point
///   (`1,250.50`, `1.250,50`).
/// - Only `,`: one comma followed by one or two digits is a decimal comma
///   (`12,5`); otherwise commas group thousands (`25,000`, `1,000,000`).
/// - Only `.`: several dots with three-digit groups group thousands
///   (`1.250.000`); a single dot followed by exactly three digits after a
///   non-zero whole part also groups thousands (`12.500` is 12,500, because
///   neither USD nor IQD has three decimals); otherwise it is the decimal
///   point (`12.5`, `0.500`).
Decimal? parseDigitGroup(String text) {
  if (text.isEmpty) return null;
  if (_digitsOnly.hasMatch(text)) return Decimal.parse(text);
  final lastComma = text.lastIndexOf(',');
  final lastDot = text.lastIndexOf('.');
  if (lastComma >= 0 && lastDot >= 0) {
    final decimalSep = lastComma > lastDot ? ',' : '.';
    final groupSep = decimalSep == ',' ? '.' : ',';
    final at = text.lastIndexOf(decimalSep);
    final whole = text.substring(0, at);
    final fraction = text.substring(at + 1);
    if (whole.contains(decimalSep)) return null;
    final digits = _ungroup(whole, groupSep);
    if (digits == null || !_digitsOnly.hasMatch(fraction)) return null;
    return Decimal.parse('$digits.$fraction');
  }
  final sep = lastComma >= 0 ? ',' : '.';
  final parts = text.split(sep);
  if (parts.any((p) => !_digitsOnly.hasMatch(p))) return null;
  if (parts.length == 2) {
    final whole = parts[0];
    final after = parts[1];
    final groups = after.length == 3 && (sep == ',' || whole != '0');
    if (groups && whole.length <= 3) return Decimal.parse('$whole$after');
    if (sep == '.' || after.length <= 2) {
      return Decimal.parse('$whole.$after');
    }
    // "1234,567": a comma that groups badly; read the digits as written.
    return Decimal.parse('$whole$after');
  }
  // Several separators of one kind: grouping.
  if (sep == '.' && parts.skip(1).any((p) => p.length != 3)) return null;
  return Decimal.parse(parts.join());
}

String? _ungroup(String whole, String groupSep) {
  final groups = whole.split(groupSep);
  if (groups.any((g) => !_digitsOnly.hasMatch(g))) return null;
  if (groups.length > 1) {
    if (groups.first.length > 3) return null;
    if (groups.skip(1).any((g) => g.length != 3)) return null;
  }
  return groups.join();
}

/// A number read from one or more tokens.
@immutable
final class NumberPhrase {
  /// Creates a phrase covering tokens `[tokenStart, tokenEnd)`.
  const new({
    required this.value,
    required this.tokenStart,
    required this.tokenEnd,
    required this.scaled,
    required this.words,
  });

  /// The exact value in major units.
  final Decimal value;

  /// Index of the first token.
  final int tokenStart;

  /// Index after the last token.
  final int tokenEnd;

  /// Whether a thousand-or-larger multiplier was applied (`k`, `thousand`,
  /// `million`), which means the number is not "bare" for dropped
  /// thousands.
  final bool scaled;

  /// Whether number words were used (`ten`, `half`).
  final bool words;

  @override
  bool operator ==(Object other) =>
      other is NumberPhrase &&
      other.value == value &&
      other.tokenStart == tokenStart &&
      other.tokenEnd == tokenEnd &&
      other.scaled == scaled &&
      other.words == words;

  @override
  int get hashCode => Object.hash(value, tokenStart, tokenEnd, scaled, words);

  @override
  String toString() => 'NumberPhrase($value, $tokenStart-$tokenEnd)';
}

/// Whether [token] can start a number phrase.
bool canStartNumber(Token token, ParserLexicon lex) {
  if (token.isNumber) return true;
  if (!token.isWord) return false;
  final w = token.text;
  return lex.units.containsKey(w) ||
      lex.tens.containsKey(w) ||
      lex.indefiniteArticles.contains(w) ||
      lex.halfWords.contains(w) ||
      lex.quarterWords.contains(w);
}

enum _State { start, digits, unit, teen, tens, hundred, scale, fraction }

/// Reads the longest number phrase starting at token [start], or `null`.
///
/// Digits may only open a phrase (`5 thousand`, `2.5 million`, `5k`);
/// number words follow English grammar (`two hundred and fifty thousand`,
/// `one and a half million`, `a million and a half`, `half a million`,
/// `quarter of a million`). A second scale that is not smaller than the one
/// before starts a new number (`five thousand and twenty thousand` reads as
/// two numbers). Digits after a word phrase also start a new number.
NumberPhrase? readNumber(
  List<Token> tokens,
  int start, [
  ParserLexicon lex = englishLexicon,
]) {
  if (start < 0 || start >= tokens.length) return null;
  if (!canStartNumber(tokens[start], lex)) return null;

  var total = Decimal.zero;
  var current = Decimal.zero;
  var hasCurrent = false;
  var lastScale = 0;
  var state = _State.start;
  var scaled = false;
  var words = false;
  // Last accepted end and value.
  int? end;
  var value = Decimal.zero;
  // Snapshot taken when the current group began, for backtracking.
  int? groupEnd;
  var groupValue = Decimal.zero;
  var groupScaled = false;
  var pendingFraction = false;

  void commit(int at) {
    end = at;
    value = total + current;
  }

  NumberPhrase? result() {
    final e = end;
    if (e == null) return null;
    return NumberPhrase(
      value: value,
      tokenStart: start,
      tokenEnd: e,
      scaled: scaled,
      words: words,
    );
  }

  var j = start;
  while (j < tokens.length) {
    final token = tokens[j];
    final w = token.text;

    if (token.isNumber) {
      if (j != start) break;
      final parsed = parseDigitGroup(w);
      if (parsed == null) return null;
      current = parsed;
      hasCurrent = true;
      state = _State.digits;
      commit(j + 1);
      // Glued suffix: 5k, 1.5m.
      if (j + 1 < tokens.length && tokens[j + 1].glued) {
        final factor = lex.gluedSuffixes[tokens[j + 1].text];
        if (factor != null) {
          total += current * Decimal.fromInt(factor);
          current = Decimal.zero;
          hasCurrent = false;
          lastScale = factor;
          scaled = true;
          state = _State.scale;
          j += 2;
          commit(j);
          groupEnd = end;
          groupValue = value;
          groupScaled = scaled;
          continue;
        }
      }
      j++;
      continue;
    }
    if (!token.isWord && w != '-') break;

    // Hyphen inside number words: twenty-five.
    if (w == '-') {
      final prevWord = j > start && tokens[j - 1].isWord;
      final nextOk =
          j + 1 < tokens.length && lex.units.containsKey(tokens[j + 1].text);
      if (state == _State.tens && prevWord && nextOk) {
        j++;
        continue;
      }
      break;
    }

    final unit = lex.units[w];
    final ten = lex.tens[w];
    final scale = lex.scaleWords[w] ?? lex.standaloneSuffixes[w];
    final isHundred = lex.hundredWords.contains(w);
    final isHalf = lex.halfWords.contains(w);
    final isQuarter = lex.quarterWords.contains(w);
    final isArticle = lex.indefiniteArticles.contains(w);
    final isAnd = lex.numberConnectives.contains(w);

    if (unit != null) {
      final ok =
          state == _State.start ||
          state == _State.hundred ||
          state == _State.scale ||
          (state == _State.tens && unit > 0 && unit < 10);
      if (!ok) break;
      if (state == _State.start || state == _State.scale) {
        groupEnd = end;
        groupValue = value;
        groupScaled = scaled;
      }
      current += Decimal.fromInt(unit);
      hasCurrent = true;
      words = true;
      state = unit < 10 ? _State.unit : _State.teen;
      j++;
      commit(j);
      continue;
    }
    if (ten != null) {
      final ok =
          state == _State.start ||
          state == _State.hundred ||
          state == _State.scale;
      if (!ok) break;
      if (state == _State.start || state == _State.scale) {
        groupEnd = end;
        groupValue = value;
        groupScaled = scaled;
      }
      current += Decimal.fromInt(ten);
      hasCurrent = true;
      words = true;
      state = _State.tens;
      j++;
      commit(j);
      continue;
    }
    if (isHundred) {
      final ok =
          (state == _State.unit ||
              state == _State.teen ||
              state == _State.tens ||
              state == _State.digits) &&
          current < Decimal.fromInt(100);
      final afterArticle =
          j > start &&
          lex.indefiniteArticles.contains(tokens[j - 1].text) &&
          !hasCurrent;
      if (!ok && !afterArticle) break;
      current = (hasCurrent ? current : Decimal.one) * Decimal.fromInt(100);
      hasCurrent = true;
      words = true;
      state = _State.hundred;
      j++;
      commit(j);
      continue;
    }
    if (scale != null) {
      final afterArticle =
          j > start &&
          lex.indefiniteArticles.contains(tokens[j - 1].text) &&
          !hasCurrent &&
          !pendingFraction;
      if (!hasCurrent && !afterArticle) break;
      if (lastScale != 0 && scale >= lastScale) {
        // A new number begins with the current group.
        if (groupEnd == null) break;
        end = groupEnd;
        value = groupValue;
        scaled = groupScaled;
        return result();
      }
      // Standalone suffixes (k, mn) need a number right before them.
      if (lex.standaloneSuffixes.containsKey(w) &&
          !lex.scaleWords.containsKey(w) &&
          (pendingFraction || j != end)) {
        break;
      }
      final base = hasCurrent ? current : Decimal.one;
      total += base * Decimal.fromInt(scale);
      current = Decimal.zero;
      hasCurrent = false;
      pendingFraction = false;
      lastScale = scale;
      scaled = true;
      words = words || lex.scaleWords.containsKey(w);
      state = _State.scale;
      j++;
      commit(j);
      groupEnd = end;
      groupValue = value;
      groupScaled = scaled;
      continue;
    }
    if (isArticle) {
      // "a thousand", "and a half", "half a million".
      final next = j + 1 < tokens.length ? tokens[j + 1].text : '';
      final nextIsScaleish =
          lex.scaleWords.containsKey(next) ||
          lex.hundredWords.contains(next) ||
          lex.halfWords.contains(next) ||
          lex.quarterWords.contains(next);
      final prev = j > start ? tokens[j - 1].text : '';
      final allowed =
          j == start ||
          lex.numberConnectives.contains(prev) ||
          lex.halfWords.contains(prev) ||
          lex.quarterWords.contains(prev) ||
          prev == 'of';
      if (!nextIsScaleish || !allowed) break;
      j++;
      continue;
    }
    if (isHalf || isQuarter) {
      final fraction = isHalf ? _half : _quarter;
      final prev = j > start ? tokens[j - 1].text : '';
      final prev2 = j - 1 > start ? tokens[j - 2].text : '';
      final afterAnd =
          lex.numberConnectives.contains(prev) ||
          (lex.indefiniteArticles.contains(prev) &&
              lex.numberConnectives.contains(prev2));
      if (afterAnd && hasCurrent) {
        // "one and a half (million)".
        current += fraction;
        words = true;
        state = _State.fraction;
        j++;
        commit(j);
        continue;
      }
      if (afterAnd && !hasCurrent && lastScale > 0) {
        // "a million and a half".
        total += fraction * Decimal.fromInt(lastScale);
        words = true;
        j++;
        commit(j);
        break;
      }
      final atOpening =
          j == start ||
          (j == start + 1 && lex.indefiniteArticles.contains(prev));
      if (atOpening) {
        // "half a million", "quarter of a million", "a quarter million":
        // only a number when a scale follows.
        current = fraction;
        hasCurrent = true;
        pendingFraction = true;
        words = true;
        state = _State.fraction;
        j++;
        continue;
      }
      break;
    }
    if (w == 'of' && pendingFraction) {
      j++;
      continue;
    }
    if (isAnd) {
      if (!hasCurrent && total == Decimal.zero) break;
      if (j + 1 >= tokens.length) break;
      final next = tokens[j + 1].text;
      final continues =
          lex.units.containsKey(next) ||
          lex.tens.containsKey(next) ||
          lex.halfWords.contains(next) ||
          lex.quarterWords.contains(next) ||
          (lex.indefiniteArticles.contains(next) &&
              j + 2 < tokens.length &&
              (lex.halfWords.contains(tokens[j + 2].text) ||
                  lex.quarterWords.contains(tokens[j + 2].text)));
      if (!continues) break;
      // After digits only a fraction may follow ("2 and a half").
      if (state == _State.digits &&
          !(lex.indefiniteArticles.contains(next) ||
              lex.halfWords.contains(next) ||
              lex.quarterWords.contains(next))) {
        break;
      }
      j++;
      continue;
    }
    break;
  }
  return result();
}
