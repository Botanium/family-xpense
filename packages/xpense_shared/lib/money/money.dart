import 'package:meta/meta.dart';
import 'package:xpense_shared/money/allocate.dart';
import 'package:xpense_shared/money/currency.dart';
import 'package:xpense_shared/money/money_failure.dart';
import 'package:xpense_shared/money/result.dart';
import 'package:xpense_shared/money/rounding.dart';

final _plainDecimal = RegExp(r'^([0-9]+)(?:\.([0-9]+))?$');

/// An amount of money: integer minor units plus a [Currency].
///
/// Never a `double` (DATA_MODEL 1). Arithmetic across currencies is a
/// programmer error and throws [ArgumentError]; convert through an `FxRate`
/// first.
@immutable
final class Money implements Comparable<Money> {
  /// Creates [minorUnits] of [currency] (cents for USD, dinars for IQD).
  const new(this.minorUnits, this.currency);

  /// Zero of [currency].
  const new zero(this.currency) : minorUnits = 0;

  /// Parses a plain ASCII decimal in major units, such as `"12.50"` USD or
  /// `"25000"` IQD, into exact minor units.
  ///
  /// The input must already be ASCII digits with `.` as the decimal point
  /// and no grouping or sign (digit folding is deferred, D-36). Extra
  /// fractional digits are allowed only when they are zeros (`"12.500"` USD);
  /// otherwise the result is [AmountTooPrecise]. Nothing is rounded.
  @useResult
  static Result<Money, MoneyFailure> parseMajor(
    String input,
    Currency currency,
  ) {
    final match = _plainDecimal.firstMatch(input);
    if (match == null) return Err(MalformedAmount(input));
    final whole = match.group(1)!;
    var fraction = match.group(2) ?? '';
    if (fraction.length > currency.exponent) {
      final dropped = fraction.substring(currency.exponent);
      if (dropped.replaceAll('0', '').isNotEmpty) {
        return Err(AmountTooPrecise(input, currency.exponent));
      }
      fraction = fraction.substring(0, currency.exponent);
    }
    fraction = fraction.padRight(currency.exponent, '0');
    final minor = BigInt.parse('$whole$fraction');
    if (!minor.isValidInt) return Err(AmountOutOfRange(input));
    return Ok(Money(minor.toInt(), currency));
  }

  /// The amount in minor units of [currency].
  final int minorUnits;

  /// The currency of this amount.
  final Currency currency;

  /// Whether the amount is zero.
  bool get isZero => minorUnits == 0;

  /// Whether the amount is below zero.
  bool get isNegative => minorUnits < 0;

  /// The sum of two amounts in the same currency.
  Money operator +(Money other) {
    _checkSameCurrency(other);
    return Money(minorUnits + other.minorUnits, currency);
  }

  /// The difference of two amounts in the same currency.
  Money operator -(Money other) {
    _checkSameCurrency(other);
    return Money(minorUnits - other.minorUnits, currency);
  }

  /// The negated amount.
  Money operator -() => Money(-minorUnits, currency);

  /// Splits this amount across [weights] with [allocate], so the parts sum
  /// exactly to this amount.
  List<Money> allocate(List<int> weights) => [
    for (final share in _allocate(minorUnits, weights)) Money(share, currency),
  ];

  /// Splits this amount into [parts] near-equal parts that sum exactly to it.
  ///
  /// Returns an empty list when [parts] is zero or negative.
  List<Money> split(int parts) =>
      parts <= 0 ? const [] : allocate(List<int>.filled(parts, 1));

  /// The exact amount in major units as a plain ASCII decimal, for example
  /// `"12.50"` USD or `"25000"` IQD.
  ///
  /// This is a canonical machine form, not a display format: no grouping,
  /// no symbol, Western digits.
  String toMajorString() {
    final digits = BigInt.from(minorUnits).abs().toString();
    final sign = minorUnits < 0 ? '-' : '';
    final exponent = currency.exponent;
    if (exponent == 0) return '$sign$digits';
    final padded = digits.padLeft(exponent + 1, '0');
    final split = padded.length - exponent;
    return '$sign${padded.substring(0, split)}.${padded.substring(split)}';
  }

  /// Orders amounts of the same currency; throws [ArgumentError] otherwise.
  @override
  int compareTo(Money other) {
    _checkSameCurrency(other);
    return minorUnits.compareTo(other.minorUnits);
  }

  void _checkSameCurrency(Money other) {
    if (other.currency != currency) {
      throw ArgumentError(
        'currency mismatch: ${currency.code} vs ${other.currency.code}',
      );
    }
  }

  @override
  bool operator ==(Object other) =>
      other is Money &&
      other.minorUnits == minorUnits &&
      other.currency == currency;

  @override
  int get hashCode => Object.hash(minorUnits, currency);

  @override
  String toString() => '${toMajorString()} ${currency.code}';
}

/// Alias so [Money.allocate] can call the top-level function.
const List<int> Function(int amount, List<int> weights) _allocate = allocate;

/// Rounds the exact ratio [numerator] / [denominator] of minor units
/// half-to-even into a [Money] of [currency], or [AmountOutOfRange].
@useResult
Result<Money, MoneyFailure> moneyFromRatio(
  BigInt numerator,
  BigInt denominator,
  Currency currency,
) {
  final minor = divideRoundHalfEven(numerator, denominator);
  if (!minor.isValidInt) return Err(AmountOutOfRange(minor.toString()));
  return Ok(Money(minor.toInt(), currency));
}
