import 'package:decimal/decimal.dart';
import 'package:meta/meta.dart';
import 'package:xpense_shared/money/currency.dart';
import 'package:xpense_shared/money/money.dart';
import 'package:xpense_shared/money/money_failure.dart';
import 'package:xpense_shared/money/result.dart';
import 'package:xpense_shared/money/rounding.dart';

final _pairPattern = RegExp(r'^([A-Z]{3})/([A-Z]{3})$');
final _ratePattern = RegExp(r'^[0-9]+(?:\.[0-9]+)?$');

/// A currency pair in market convention, `BASE/QUOTE` (for example
/// `USD/IQD`): one unit of [base] costs the rate in [quote].
@immutable
final class FxPair {
  /// Creates the pair [base]/[quote]. The two must differ.
  const new(this.base, this.quote) : assert(base != quote, 'same currency');

  /// The household's stored pair (DATA_MODEL 1, D-16).
  static const usdIqd = FxPair(Currency.usd, Currency.iqd);

  /// Parses `"USD/IQD"`. Both codes must be known and distinct.
  @useResult
  static Result<FxPair, MoneyFailure> parse(String pair) {
    final match = _pairPattern.firstMatch(pair);
    if (match == null) return Err(MalformedPair(pair));
    final base = Currency.tryParse(match.group(1)!);
    final quote = Currency.tryParse(match.group(2)!);
    if (base == null) return Err(UnknownCurrency(match.group(1)!));
    if (quote == null) return Err(UnknownCurrency(match.group(2)!));
    if (base == quote) return Err(MalformedPair(pair));
    return Ok(FxPair(base, quote));
  }

  /// The currency priced by the rate (`USD` in `USD/IQD`).
  final Currency base;

  /// The currency the rate is expressed in (`IQD` in `USD/IQD`).
  final Currency quote;

  /// The stored form, for example `USD/IQD`.
  String get code => '${base.code}/${quote.code}';

  /// Whether this pair converts between [a] and [b], in either direction.
  bool connects(Currency a, Currency b) =>
      (a == base && b == quote) || (a == quote && b == base);

  @override
  bool operator ==(Object other) =>
      other is FxPair && other.base == base && other.quote == quote;

  @override
  int get hashCode => Object.hash(base, quote);

  @override
  String toString() => code;
}

/// An exchange rate for an [FxPair], held exactly as a decimal.
///
/// Rates come from and go to storage as decimal strings (`fx.pairRate`,
/// `fxRates/{day}.usdIqd`), never floats (DATA_MODEL 1).
@immutable
final class FxRate {
  const new _(this.pair, this.rate);

  /// Parses a stored pair and rate, for example `("USD/IQD", "1520")`.
  ///
  /// The rate must be a positive plain ASCII decimal (`"1520"`,
  /// `"1507.5"`): no grouping, sign or exponent.
  @useResult
  static Result<FxRate, MoneyFailure> parse(String pair, String rate) =>
      FxPair.parse(pair).flatMap((p) => forPair(p, rate));

  /// Parses [rate] as the rate of [pair].
  @useResult
  static Result<FxRate, MoneyFailure> forPair(FxPair pair, String rate) {
    if (!_ratePattern.hasMatch(rate)) return Err(MalformedRate(rate));
    final value = Decimal.parse(rate);
    if (value <= Decimal.zero) return Err(MalformedRate(rate));
    return Ok(FxRate._(pair, value));
  }

  /// The pair this rate prices.
  final FxPair pair;

  /// Units of [FxPair.quote] per one unit of [FxPair.base].
  final Decimal rate;

  /// The canonical decimal string to store (`"1520"`, `"1507.5"`).
  String get rateString => rate.toString();

  /// Converts [amount] into [to] with this rate, rounding half-to-even once.
  ///
  /// Converting to the amount's own currency returns it unchanged. A
  /// currency outside the pair is [PairMismatch]. The computation is exact
  /// until the single rounding of the result to [to]'s minor units.
  @useResult
  Result<Money, MoneyFailure> convert(Money amount, Currency to) {
    final from = amount.currency;
    if (from == to) return Ok(amount);
    if (!pair.connects(from, to)) {
      return Err(PairMismatch(pair: pair.code, from: from.code, to: to.code));
    }
    final ratio = rate.toRational();
    final minor = BigInt.from(amount.minorUnits);
    final scaleTo = pow10(to.exponent);
    final scaleFrom = pow10(from.exponent);
    // base → quote multiplies by the rate; quote → base divides by it.
    final multiply = from == pair.base;
    final numerator = multiply
        ? minor * ratio.numerator * scaleTo
        : minor * ratio.denominator * scaleTo;
    final denominator = multiply
        ? ratio.denominator * scaleFrom
        : ratio.numerator * scaleFrom;
    return moneyFromRatio(numerator, denominator, to);
  }

  @override
  bool operator ==(Object other) =>
      other is FxRate && other.pair == pair && other.rate == rate;

  @override
  int get hashCode => Object.hash(pair, rate);

  @override
  String toString() => '$pair $rateString';
}

/// Computes a transaction's `baseAmountMinor` (DATA_MODEL 1).
///
/// When [amount] is already in [base] the result is the same minor units and
/// no rate is needed. Otherwise [rate] must connect the two currencies; a
/// missing rate is [RateRequired]. Rounding is half-to-even, once.
@useResult
Result<Money, MoneyFailure> toBaseAmount(
  Money amount,
  Currency base, {
  FxRate? rate,
}) {
  if (amount.currency == base) return Ok(amount);
  if (rate == null) {
    return Err(RateRequired(from: amount.currency.code, to: base.code));
  }
  return rate.convert(amount, base);
}
