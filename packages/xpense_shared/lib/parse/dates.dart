/// Step 5 of the fast parser: dates (AI_PIPELINE 5).
///
/// Relative words resolve against an injected "today", never the system
/// clock, so results are deterministic.
library;

import 'package:meta/meta.dart';
import 'package:xpense_shared/parse/lexicon.dart';
import 'package:xpense_shared/parse/tokens.dart';

/// A calendar date with no time zone (household-local).
@immutable
final class LocalDate implements Comparable<LocalDate> {
  const new _(this.year, this.month, this.day);

  /// The calendar date of [dateTime]'s own fields (its wall-clock date).
  new fromDateTime(DateTime dateTime)
    : year = dateTime.year,
      month = dateTime.month,
      day = dateTime.day;

  /// The date for [year], [month] and [day], or `null` when it does not
  /// exist (`31/02`) or the year is outside 1900 to 2999.
  static LocalDate? tryCreate(int year, int month, int day) {
    if (year < 1900 || year > 2999 || month < 1 || month > 12 || day < 1) {
      return null;
    }
    final probe = DateTime.utc(year, month, day);
    if (probe.month != month || probe.day != day) return null;
    return LocalDate._(year, month, day);
  }

  /// The year.
  final int year;

  /// The month, 1 to 12.
  final int month;

  /// The day of the month.
  final int day;

  /// ISO weekday: Monday 1 to Sunday 7.
  int get weekday => DateTime.utc(year, month, day).weekday;

  /// This date moved by [days] (negative for the past).
  LocalDate addDays(int days) {
    final moved = DateTime.utc(year, month, day + days);
    return LocalDate._(moved.year, moved.month, moved.day);
  }

  /// `YYYY-MM-DD`.
  String get iso =>
      '${year.toString().padLeft(4, '0')}-'
      '${month.toString().padLeft(2, '0')}-'
      '${day.toString().padLeft(2, '0')}';

  @override
  int compareTo(LocalDate other) => year != other.year
      ? year.compareTo(other.year)
      : month != other.month
      ? month.compareTo(other.month)
      : day.compareTo(other.day);

  /// Whether this date is after [other].
  bool isAfter(LocalDate other) => compareTo(other) > 0;

  @override
  bool operator ==(Object other) =>
      other is LocalDate &&
      other.year == year &&
      other.month == month &&
      other.day == day;

  @override
  int get hashCode => Object.hash(year, month, day);

  @override
  String toString() => iso;
}

/// A date expression found in the text.
@immutable
final class DateMention {
  /// Creates a mention covering tokens `[tokenStart, tokenEnd)`.
  const new({
    required this.date,
    required this.start,
    required this.end,
    required this.tokenStart,
    required this.tokenEnd,
  });

  /// The resolved date.
  final LocalDate date;

  /// Start offset in the normalised text.
  final int start;

  /// End offset (exclusive) in the normalised text.
  final int end;

  /// Index of the first token of the expression.
  final int tokenStart;

  /// Index after the last token of the expression.
  final int tokenEnd;

  @override
  bool operator ==(Object other) =>
      other is DateMention &&
      other.date == date &&
      other.start == start &&
      other.end == end;

  @override
  int get hashCode => Object.hash(date, start, end);

  @override
  String toString() => 'DateMention($date@$start-$end)';
}

/// Finds the first date expression in [tokens] and resolves it against
/// [today]. Returns `null` when there is none (the caller defaults to
/// today).
///
/// Supported: today words, yesterday, the day before yesterday, weekday
/// names (the most recent such day, today included), `last <weekday>` (the
/// most recent such day before today), `N days ago`, `a week ago`,
/// `dd/mm`, `dd/mm/yyyy` (also `-` and `.`), `5 march`, `march 5th`,
/// `the 5th`. A date without a year (or month) that would fall after
/// [today] is moved back one year (or month): entries are in the past.
DateMention? findDate(
  List<Token> tokens,
  LocalDate today, [
  ParserLexicon lexicon = englishLexicon,
]) {
  for (var i = 0; i < tokens.length; i++) {
    final found = _dateAt(tokens, i, today, lexicon);
    if (found != null) {
      final (date, end) = found;
      return DateMention(
        date: date,
        start: tokens[i].start,
        end: tokens[end - 1].end,
        tokenStart: i,
        tokenEnd: end,
      );
    }
  }
  return null;
}

(LocalDate, int)? _dateAt(
  List<Token> tokens,
  int i,
  LocalDate today,
  ParserLexicon lex,
) {
  // Longest phrases first so "the day before yesterday" beats "yesterday".
  for (final phrase in lex.dayBeforeYesterdayWords) {
    if (phraseAt(tokens, i, phrase)) {
      return (today.addDays(-2), i + _phraseLength(phrase));
    }
  }
  for (final phrase in lex.yesterdayWords) {
    if (phraseAt(tokens, i, phrase)) {
      return (today.addDays(-1), i + _phraseLength(phrase));
    }
  }
  for (final phrase in lex.todayWords) {
    if (phraseAt(tokens, i, phrase)) {
      return (today, i + _phraseLength(phrase));
    }
  }
  final token = tokens[i];
  if (token.isWord) {
    return _weekdayAt(tokens, i, today, lex) ??
        _monthFirstAt(tokens, i, today, lex) ??
        _agoAt(tokens, i, today, lex) ??
        _ordinalDayAt(tokens, i, today, lex);
  }
  if (token.isNumber) {
    return _numericAt(tokens, i, today) ??
        _dayFirstAt(tokens, i, today, lex) ??
        _agoAt(tokens, i, today, lex);
  }
  return null;
}

int _phraseLength(String phrase) => tokenize(phrase).length;

// "friday", "on fri", "last friday".
(LocalDate, int)? _weekdayAt(
  List<Token> tokens,
  int i,
  LocalDate today,
  ParserLexicon lex,
) {
  final word = tokens[i].text;
  final isLast = lex.lastWords.contains(word);
  final at = isLast ? i + 1 : i;
  if (at >= tokens.length) return null;
  final target = lex.weekdays[tokens[at].text];
  if (target == null) return null;
  final isFullName = tokens[at].text.length > 4;
  final afterOn = at > 0 && tokens[at - 1].text == 'on';
  if (!isFullName && !isLast && !afterOn) return null;
  var back = (today.weekday - target) % 7;
  if (isLast && back == 0) back = 7;
  return (today.addDays(-back), at + 1);
}

// "3 days ago", "two weeks ago", "a week ago".
(LocalDate, int)? _agoAt(
  List<Token> tokens,
  int i,
  LocalDate today,
  ParserLexicon lex,
) {
  if (i + 2 >= tokens.length) return null;
  final count = _smallCount(tokens[i], lex);
  if (count == null) return null;
  final unit = tokens[i + 1].text;
  if (!lex.agoWords.contains(tokens[i + 2].text)) return null;
  if (lex.dayUnitWords.contains(unit)) {
    return (today.addDays(-count), i + 3);
  }
  if (lex.weekUnitWords.contains(unit)) {
    return (today.addDays(-7 * count), i + 3);
  }
  return null;
}

int? _smallCount(Token token, ParserLexicon lex) {
  if (token.isNumber) {
    final n = int.tryParse(token.text);
    return n != null && n <= 366 ? n : null;
  }
  if (lex.indefiniteArticles.contains(token.text)) return 1;
  return lex.units[token.text];
}

// "22/11", "22/11/2026", "22-11-2026", "22.11.2026".
(LocalDate, int)? _numericAt(List<Token> tokens, int i, LocalDate today) {
  final first = tokens[i];
  final dotted = RegExp(r'^(\d{1,2})\.(\d{1,2})\.(\d{2}|\d{4})$')
      .firstMatch(first.text);
  if (dotted != null) {
    final date = _fromParts(
      int.parse(dotted.group(1)!),
      int.parse(dotted.group(2)!),
      dotted.group(3)!,
      today,
    );
    return date == null ? null : (date, i + 1);
  }
  if (!RegExp(r'^\d{1,2}$').hasMatch(first.text)) return null;
  if (i + 2 >= tokens.length) return null;
  final sep = tokens[i + 1];
  final second = tokens[i + 2];
  if (!sep.glued || !second.glued) return null;
  if (sep.text != '/' && sep.text != '-') return null;
  if (!RegExp(r'^\d{1,2}$').hasMatch(second.text)) return null;
  final day = int.parse(first.text);
  final month = int.parse(second.text);
  if (i + 4 < tokens.length &&
      tokens[i + 3].glued &&
      tokens[i + 3].text == sep.text &&
      tokens[i + 4].glued &&
      RegExp(r'^(\d{2}|\d{4})$').hasMatch(tokens[i + 4].text)) {
    final date = _fromParts(day, month, tokens[i + 4].text, today);
    return date == null ? null : (date, i + 5);
  }
  // Two-part dates need '/', because "5-10" reads as a range.
  if (sep.text != '/') return null;
  final date = _withoutYear(day, month, today);
  return date == null ? null : (date, i + 3);
}

LocalDate? _fromParts(int day, int month, String yearText, LocalDate today) {
  var year = int.parse(yearText);
  if (yearText.length == 2) year += 2000;
  return LocalDate.tryCreate(year, month, day);
}

LocalDate? _withoutYear(int day, int month, LocalDate today) {
  final date = LocalDate.tryCreate(today.year, month, day);
  if (date == null) {
    // 29/02 in a non-leap year: try the previous year.
    return LocalDate.tryCreate(today.year - 1, month, day);
  }
  if (date.isAfter(today)) {
    return LocalDate.tryCreate(today.year - 1, month, day);
  }
  return date;
}

int? _dayNumber(List<Token> tokens, int i, ParserLexicon lex) {
  final token = tokens[i];
  if (!token.isNumber || !RegExp(r'^\d{1,2}$').hasMatch(token.text)) {
    return null;
  }
  return int.parse(token.text);
}

// Index after an optional glued ordinal suffix ("5th").
int _skipOrdinal(List<Token> tokens, int i, ParserLexicon lex) =>
    i < tokens.length &&
        tokens[i].glued &&
        lex.ordinalSuffixes.contains(tokens[i].text)
    ? i + 1
    : i;

// A written year is taken only near today; "march 5 3000" is a day and
// an amount.
bool _plausibleYear(int year, LocalDate today) =>
    year >= today.year - 10 && year <= today.year + 1;

int? _yearAt(List<Token> tokens, int i) {
  if (i >= tokens.length) return null;
  final text = tokens[i].text;
  if (!RegExp(r'^\d{4}$').hasMatch(text)) return null;
  return int.parse(text);
}

// "5 march", "5th of march 2026".
(LocalDate, int)? _dayFirstAt(
  List<Token> tokens,
  int i,
  LocalDate today,
  ParserLexicon lex,
) {
  final day = _dayNumber(tokens, i, lex);
  if (day == null) return null;
  var at = _skipOrdinal(tokens, i + 1, lex);
  if (at < tokens.length && tokens[at].text == 'of') at++;
  if (at >= tokens.length) return null;
  final month = lex.months[tokens[at].text];
  if (month == null) return null;
  return _withMonth(tokens, at + 1, day, month, today);
}

// "march 5", "march 5th, 2026".
(LocalDate, int)? _monthFirstAt(
  List<Token> tokens,
  int i,
  LocalDate today,
  ParserLexicon lex,
) {
  final month = lex.months[tokens[i].text];
  if (month == null || i + 1 >= tokens.length) return null;
  final day = _dayNumber(tokens, i + 1, lex);
  if (day == null) return null;
  final at = _skipOrdinal(tokens, i + 2, lex);
  return _withMonth(tokens, at, day, month, today);
}

(LocalDate, int)? _withMonth(
  List<Token> tokens,
  int at,
  int day,
  int month,
  LocalDate today,
) {
  var next = at;
  if (next < tokens.length && tokens[next].text == ',') next++;
  final year = _yearAt(tokens, next);
  if (year != null && _plausibleYear(year, today)) {
    final date = LocalDate.tryCreate(year, month, day);
    if (date != null) return (date, next + 1);
  }
  final date = _withoutYear(day, month, today);
  return date == null ? null : (date, at);
}

// "the 5th" (this month, or last month when that is still ahead).
(LocalDate, int)? _ordinalDayAt(
  List<Token> tokens,
  int i,
  LocalDate today,
  ParserLexicon lex,
) {
  if (tokens[i].text != 'the' || i + 2 >= tokens.length) return null;
  final day = _dayNumber(tokens, i + 1, lex);
  if (day == null) return null;
  final suffix = tokens[i + 2];
  if (!suffix.glued || !lex.ordinalSuffixes.contains(suffix.text)) {
    return null;
  }
  var date = LocalDate.tryCreate(today.year, today.month, day);
  if (date == null || date.isAfter(today)) {
    final previous = DateTime.utc(today.year, today.month - 1);
    date = LocalDate.tryCreate(previous.year, previous.month, day);
  }
  return date == null ? null : (date, i + 3);
}
