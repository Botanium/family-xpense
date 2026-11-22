/// The receipt parser (AI_PIPELINE 3, OCR): merchant line, date, total and
/// candidate line items from OCR text lines. Deterministic, shared.
///
/// OCR text is untrusted input; this parser only reads numbers and words
/// from it and never interprets it as instructions.
library;

import 'package:decimal/decimal.dart';
import 'package:meta/meta.dart';
import 'package:xpense_shared/money/currency.dart';
import 'package:xpense_shared/money/money.dart';
import 'package:xpense_shared/money/result.dart';
import 'package:xpense_shared/parse/dates.dart';
import 'package:xpense_shared/parse/fast_parser.dart';
import 'package:xpense_shared/parse/lexicon.dart';
import 'package:xpense_shared/parse/normalize.dart';
import 'package:xpense_shared/parse/numbers.dart';
import 'package:xpense_shared/parse/tokens.dart';
import 'package:xpense_shared/schema/receipt_extraction.dart';

/// Longest merchant name kept (the transaction title limit, DATA_MODEL 2.5).
const int maxMerchantLength = 80;

/// The bounding box of an OCR line, in image pixels (top-left origin).
@immutable
final class OcrBox {
  /// Creates a box.
  const new({
    required this.left,
    required this.top,
    required this.width,
    required this.height,
  });

  /// Left edge.
  final double left;

  /// Top edge.
  final double top;

  /// Width.
  final double width;

  /// Height.
  final double height;

  /// Vertical centre.
  double get centerY => top + height / 2;
}

/// One OCR text line, with its box when the engine gives one.
@immutable
final class OcrLine {
  /// Creates a line.
  const new(this.text, {this.box});

  /// The recognised text.
  final String text;

  /// The line's box, or `null` (lines are then taken in the given order).
  final OcrBox? box;
}

/// The receipt parser's result.
@immutable
final class ReceiptParse {
  /// Creates a result.
  const new({
    required this.extraction,
    required this.rows,
    required this.totalFromKeyword,
    this.currencySource = CurrencySource.none,
  });

  /// Merchant, date, currency, total and line items, in the shared schema.
  final ReceiptExtraction extraction;

  /// The text rows after merging boxes on the same line, top to bottom.
  final List<String> rows;

  /// Whether the total sat next to a total word; when `false` it is the
  /// largest amount on the receipt and should be confirmed.
  final bool totalFromKeyword;

  /// Where the currency came from.
  final CurrencySource currencySource;
}

final class _Price {
  new(this.value, this.start, this.end, this.currency, this.hasDecimals);
  final Decimal value;
  final int start;
  final int end;
  final Currency? currency;
  final bool hasDecimals;
}

final _priceToken = RegExp(
  '(?<![0-9A-Za-z/:.,])'
  r'(\$|usd|iqd)?\s?'
  '([0-9]{1,3}(?:[,.][0-9]{3})+(?:[.,][0-9]{1,2})?|[0-9]+(?:[.,][0-9]{1,2})?)'
  r'\s?(\$|usd|iqd|id|dinars?|dollars?)?'
  '(?![0-9A-Za-z/:%]|[.,][0-9])',
  caseSensitive: false,
);
final _dateNumeric = RegExp(r'\b(\d{1,2})[/.\-](\d{1,2})[/.\-](\d{4}|\d{2})\b');
final _dateIso = RegExp(r'\b(\d{4})[/.\-](\d{1,2})[/.\-](\d{1,2})\b');
final _dateDayMonth = RegExp(
  r'\b(\d{1,2})(?:st|nd|rd|th)?[\s\-]+([a-z]{3,9})\.?[\s\-,]+(\d{4}|\d{2})\b',
);
final _dateMonthDay = RegExp(
  r'\b([a-z]{3,9})\.?\s+(\d{1,2})(?:st|nd|rd|th)?,?\s+(\d{4})\b',
);
final _time = RegExp(r'\b\d{1,2}:\d{2}(?::\d{2})?\b');
final _letters = RegExp(r'\p{L}', unicode: true);
final _qtyTail = RegExp(
  r'(\s+(?:[0-9]+(?:[.,][0-9]+)*|x|@|\$|usd|iqd|qty|pcs))+\s*$',
  caseSensitive: false,
);

/// Merges OCR [lines] into rows: lines whose boxes share a vertical band
/// (item on the left, price on the right) are joined left to right. Lines
/// without boxes keep their order, one row each.
List<String> mergeRows(List<OcrLine> lines) {
  final boxed = [
    for (final l in lines)
      if (l.box != null) l,
  ];
  if (boxed.length != lines.length) {
    return [
      for (final l in lines)
        if (l.text.trim().isNotEmpty) l.text.trim(),
    ];
  }
  final sorted = [...boxed]
    ..sort((a, b) => a.box!.centerY.compareTo(b.box!.centerY));
  final rows = <List<OcrLine>>[];
  for (final line in sorted) {
    final box = line.box!;
    final last = rows.isEmpty ? null : rows.last;
    if (last != null) {
      final ref = last.first.box!;
      final band = (ref.height < box.height ? ref.height : box.height) / 2;
      if ((box.centerY - ref.centerY).abs() <= band) {
        last.add(line);
        continue;
      }
    }
    rows.add([line]);
  }
  return [
    for (final row in rows)
      ((row..sort((a, b) => a.box!.left.compareTo(b.box!.left)))
              .map((l) => l.text.trim())
              .where((t) => t.isNotEmpty)
              .join(' '))
          .trim(),
  ]..removeWhere((r) => r.isEmpty);
}

/// Parses OCR [lines] of a receipt.
///
/// - **Merchant:** the first of the top five rows with at least three
///   letters, more letters than digits, no price, no date and no skip word
///   (`invoice`, `tel`).
/// - **Date:** the first valid `dd/mm/yyyy` (day first unless the second
///   number is over 12), `yyyy-mm-dd`, `22 Nov 2026` or `Nov 22, 2026`.
/// - **Total:** the largest amount on a row with a total word (`TOTAL`,
///   `AMOUNT DUE`, `BALANCE`) and no excluded word (`SUBTOTAL`, `CHANGE`,
///   `CASH`), or on the row after it; else the largest amount on the
///   receipt, flagged with [ReceiptParse.totalFromKeyword] `false`.
/// - **Currency:** currency marks on the receipt (the most frequent), else
///   [defaultCurrency], else IQD when the total is 10,000 or more, else USD
///   when amounts carry cents.
/// - **Lines:** rows above the total that end in a price, have letters and
///   no non-item word; the text is the row without its trailing numbers.
ReceiptParse parseReceipt(
  List<OcrLine> lines, {
  Currency? defaultCurrency,
  ParserLexicon lexicon = englishLexicon,
}) {
  final lex = lexicon;
  final rows = mergeRows(lines);
  final lower = [for (final r in rows) normalizeText(r)];
  final prices = [for (final r in lower) _prices(r, lex)];

  // Merchant.
  String? merchant;
  for (var i = 0; i < rows.length && i < 5; i++) {
    if (_isMerchant(rows[i], lower[i], prices[i], lex)) {
      final name = normalize(rows[i]).cased;
      merchant = name.length > maxMerchantLength
          ? name.substring(0, maxMerchantLength).trim()
          : name;
      break;
    }
  }

  // Date.
  LocalDate? date;
  for (final row in lower) {
    date = _receiptDate(row, lex);
    if (date != null) break;
  }

  // Total.
  _Price? total;
  int? totalRow;
  var fromKeyword = false;
  for (var i = 0; i < rows.length; i++) {
    if (!_hasAny(lower[i], lex.receiptTotalWords)) continue;
    if (_hasAny(lower[i], lex.receiptTotalExclusions)) continue;
    final candidates = prices[i].isNotEmpty
        ? [prices[i].last]
        : i + 1 < rows.length && !_hasAny(lower[i + 1], lex.receiptTotalWords)
        ? prices[i + 1].take(1).toList()
        : const <_Price>[];
    for (final p in candidates) {
      if (total == null || p.value > total.value) {
        total = p;
        totalRow = i;
        fromKeyword = true;
      }
    }
  }
  if (total == null) {
    for (var i = 0; i < rows.length; i++) {
      if (_hasAny(lower[i], lex.receiptTotalExclusions)) continue;
      for (final p in prices[i]) {
        if (total == null || p.value > total.value) {
          total = p;
          totalRow = i;
        }
      }
    }
  }

  // Currency.
  // Symbols and short marks count where they touch a price; currency words
  // count wherever they appear.
  final marks = <Currency, int>{};
  void mark(Currency c, int n) {
    if (n > 0) marks[c] = (marks[c] ?? 0) + n;
  }

  for (var i = 0; i < rows.length; i++) {
    for (final p in prices[i]) {
      final markText = lower[i].substring(p.start, p.end);
      if (p.currency != null &&
          (markText.contains(r'$') || markText.endsWith('id'))) {
        mark(p.currency!, 1);
      }
    }
    for (final entry in lex.currencyWords.entries) {
      if (entry.key.length < 3) continue;
      mark(entry.value, findWholeWord(lower[i], entry.key).length);
    }
  }
  Currency? currency;
  var currencySource = CurrencySource.none;
  if (marks.isNotEmpty) {
    final ranked = marks.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    if (ranked.length == 1 || ranked[0].value > ranked[1].value) {
      currency = ranked.first.key;
      currencySource = CurrencySource.word;
    }
  }
  if (currency == null && defaultCurrency != null) {
    currency = defaultCurrency;
    currencySource = CurrencySource.defaultAccount;
  }
  if (currency == null && total != null) {
    if (total.value >= Decimal.fromInt(iqdMagnitudeThreshold)) {
      currency = Currency.iqd;
      currencySource = CurrencySource.magnitude;
    } else if (prices.any((r) => r.any((p) => p.hasDecimals))) {
      currency = Currency.usd;
      currencySource = CurrencySource.decimals;
    }
  }

  int? minor(Decimal value) => currency == null
      ? null
      : Money.parseMajor(value.toString(), currency).valueOrNull?.minorUnits;

  // Line items.
  final items = <ReceiptLine>[];
  final itemEnd = fromKeyword && totalRow != null ? totalRow : rows.length;
  if (currency != null) {
    final merchantRow = merchant == null
        ? -1
        : rows.indexWhere((r) => normalize(r).cased.startsWith(merchant!));
    for (var i = merchantRow + 1; i < itemEnd; i++) {
      if (prices[i].isEmpty) continue;
      if (_hasAny(lower[i], lex.receiptNonItemWords)) continue;
      if (_receiptDate(lower[i], lex) != null) continue;
      final price = prices[i].last;
      if (price.end < lower[i].trimRight().length) continue;
      final amount = minor(price.value);
      if (amount == null) continue;
      final text = _itemText(normalize(rows[i]).cased, price.start);
      if (_letters.allMatches(text).length < 2) continue;
      items.add(ReceiptLine(text: text, amountMinor: amount));
    }
  }

  return ReceiptParse(
    extraction: ReceiptExtraction(
      merchant: merchant,
      date: date?.iso,
      currency: currency?.code,
      totalMinor: total == null ? null : minor(total.value),
      lines: items,
    ),
    rows: rows,
    totalFromKeyword: fromKeyword,
    currencySource: currencySource,
  );
}

bool _hasAny(String row, List<String> phrases) =>
    phrases.any((p) => findWholeWord(row, p).isNotEmpty);

List<_Price> _prices(String row, ParserLexicon lex) {
  final masked = row.replaceAllMapped(_time, (m) => ' ' * (m.end - m.start));
  final found = <_Price>[];
  for (final m in _priceToken.allMatches(masked)) {
    final digits = m.group(2)!;
    if (_overlapsDate(row, m.start, m.end, lex)) continue;
    if (digits.length >= 7 && digits.startsWith('0')) continue;
    final value = parseDigitGroup(digits);
    if (value == null) continue;
    final mark = (m.group(1) ?? m.group(3) ?? '').toLowerCase();
    final currency = mark.isEmpty
        ? null
        : englishLexicon.currencyWords[mark] ??
              (mark.startsWith('dinar') ? Currency.iqd : Currency.usd);
    final hasDecimals = RegExp(r'[.,][0-9]{2}$').hasMatch(digits);
    found.add(_Price(value, m.start, m.end, currency, hasDecimals));
  }
  return found;
}

bool _overlapsDate(String row, int start, int end, ParserLexicon lex) {
  bool overlaps(RegExpMatch m) => start < m.end && end > m.start;
  for (final pattern in [_dateNumeric, _dateIso]) {
    if (pattern.allMatches(row).any(overlaps)) return true;
  }
  // Written months count only when the word really is a month, so
  // "rice 5 bags 12,000" keeps its prices.
  for (final m in _dateDayMonth.allMatches(row)) {
    if (lex.months.containsKey(m.group(2)) && overlaps(m)) return true;
  }
  for (final m in _dateMonthDay.allMatches(row)) {
    if (lex.months.containsKey(m.group(1)) && overlaps(m)) return true;
  }
  return false;
}

bool _isMerchant(
  String row,
  String lower,
  List<_Price> prices,
  ParserLexicon lex,
) {
  final letters = _letters.allMatches(row).length;
  final digits = RegExp('[0-9]').allMatches(row).length;
  if (letters < 3 || digits >= letters) return false;
  if (_hasAny(lower, lex.receiptMerchantSkipWords)) return false;
  if (_hasAny(lower, lex.receiptTotalWords)) return false;
  if (_receiptDate(lower, lex) != null) return false;
  if (prices.any((p) => p.hasDecimals || p.currency != null)) return false;
  return true;
}

LocalDate? _receiptDate(String row, ParserLexicon lex) {
  for (final m in _dateIso.allMatches(row)) {
    final d = LocalDate.tryCreate(
      int.parse(m.group(1)!),
      int.parse(m.group(2)!),
      int.parse(m.group(3)!),
    );
    if (d != null) return d;
  }
  for (final m in _dateNumeric.allMatches(row)) {
    final a = int.parse(m.group(1)!);
    final b = int.parse(m.group(2)!);
    var year = int.parse(m.group(3)!);
    if (m.group(3)!.length == 2) year += 2000;
    // Day first (Iraq); month first only when the second part is a day.
    final d = b > 12
        ? LocalDate.tryCreate(year, a, b)
        : LocalDate.tryCreate(year, b, a);
    if (d != null) return d;
  }
  for (final m in _dateDayMonth.allMatches(row)) {
    final month = lex.months[m.group(2)!];
    if (month == null) continue;
    var year = int.parse(m.group(3)!);
    if (m.group(3)!.length == 2) year += 2000;
    final d = LocalDate.tryCreate(year, month, int.parse(m.group(1)!));
    if (d != null) return d;
  }
  for (final m in _dateMonthDay.allMatches(row)) {
    final month = lex.months[m.group(1)!];
    if (month == null) continue;
    final d = LocalDate.tryCreate(
      int.parse(m.group(3)!),
      month,
      int.parse(m.group(2)!),
    );
    if (d != null) return d;
  }
  return null;
}

String _itemText(String cased, int priceStart) {
  var text = cased.substring(0, priceStart.clamp(0, cased.length)).trim();
  text = text.replaceFirst(_qtyTail, '').trim();
  return text.replaceAll(RegExp(r'[\s.:\-]+$'), '').trim();
}
