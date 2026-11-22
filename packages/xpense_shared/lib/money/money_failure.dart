import 'package:meta/meta.dart';
import 'package:xpense_shared/money/result.dart';

/// Recoverable failures of the money and FX core.
///
/// Every subtype carries a stable [code] and typed parameters only; the
/// presentation layer localises from the code.
@immutable
sealed class MoneyFailure implements Failure {
  const new();
}

/// A currency code that is not in the app's exponent table (DATA_MODEL 1).
///
/// An unknown code is never defaulted to two decimals.
final class UnknownCurrency extends MoneyFailure {
  /// Creates the failure for the rejected [currencyCode].
  const new(this.currencyCode);

  /// The code exactly as it was given.
  final String currencyCode;

  @override
  String get code => 'money.unknown_currency';

  @override
  bool operator ==(Object other) =>
      other is UnknownCurrency && other.currencyCode == currencyCode;

  @override
  int get hashCode => Object.hash(UnknownCurrency, currencyCode);
}

/// An amount string that is not a plain ASCII decimal (`123`, `12.5`).
///
/// Grouping separators, signs, exponents and non-ASCII digits are rejected:
/// digit folding for other scripts is deferred (D-36).
final class MalformedAmount extends MoneyFailure {
  /// Creates the failure for the rejected [input].
  const new(this.input);

  /// The input exactly as it was given.
  final String input;

  @override
  String get code => 'money.malformed_amount';

  @override
  bool operator ==(Object other) =>
      other is MalformedAmount && other.input == input;

  @override
  int get hashCode => Object.hash(MalformedAmount, input);
}

/// An amount with more fractional digits than its currency allows
/// (for example `12.345` USD or `0.5` IQD).
///
/// The core does not round user input; only the base-amount conversion
/// rounds, once (DATA_MODEL 1).
final class AmountTooPrecise extends MoneyFailure {
  /// Creates the failure for [input] in a currency with [exponent] decimals.
  const new(this.input, this.exponent);

  /// The input exactly as it was given.
  final String input;

  /// The number of decimals the currency allows.
  final int exponent;

  @override
  String get code => 'money.amount_too_precise';

  @override
  bool operator ==(Object other) =>
      other is AmountTooPrecise &&
      other.input == input &&
      other.exponent == exponent;

  @override
  int get hashCode => Object.hash(AmountTooPrecise, input, exponent);
}

/// An amount whose minor units do not fit in a 64-bit integer.
final class AmountOutOfRange extends MoneyFailure {
  /// Creates the failure for [input].
  const new(this.input);

  /// The input (or the computed value) as text.
  final String input;

  @override
  String get code => 'money.amount_out_of_range';

  @override
  bool operator ==(Object other) =>
      other is AmountOutOfRange && other.input == input;

  @override
  int get hashCode => Object.hash(AmountOutOfRange, input);
}

/// A currency pair that is not `BASE/QUOTE` with two distinct known codes.
final class MalformedPair extends MoneyFailure {
  /// Creates the failure for the rejected [pair].
  const new(this.pair);

  /// The pair exactly as it was given.
  final String pair;

  @override
  String get code => 'fx.malformed_pair';

  @override
  bool operator ==(Object other) =>
      other is MalformedPair && other.pair == pair;

  @override
  int get hashCode => Object.hash(MalformedPair, pair);
}

/// A rate that is not a positive plain ASCII decimal string.
///
/// Rates are stored as decimal strings such as `"1520"`, never floats.
final class MalformedRate extends MoneyFailure {
  /// Creates the failure for the rejected [rate].
  const new(this.rate);

  /// The rate exactly as it was given.
  final String rate;

  @override
  String get code => 'fx.malformed_rate';

  @override
  bool operator ==(Object other) =>
      other is MalformedRate && other.rate == rate;

  @override
  int get hashCode => Object.hash(MalformedRate, rate);
}

/// A conversion asked of a rate whose pair does not contain both currencies.
final class PairMismatch extends MoneyFailure {
  /// Creates the failure for converting [from] to [to] with [pair].
  const new({required this.pair, required this.from, required this.to});

  /// The rate's pair, for example `USD/IQD`.
  final String pair;

  /// The source currency code.
  final String from;

  /// The target currency code.
  final String to;

  @override
  String get code => 'fx.pair_mismatch';

  @override
  bool operator ==(Object other) =>
      other is PairMismatch &&
      other.pair == pair &&
      other.from == from &&
      other.to == to;

  @override
  int get hashCode => Object.hash(PairMismatch, pair, from, to);
}

/// A conversion between two different currencies with no rate supplied.
final class RateRequired extends MoneyFailure {
  /// Creates the failure for converting [from] to [to].
  const new({required this.from, required this.to});

  /// The source currency code.
  final String from;

  /// The target currency code.
  final String to;

  @override
  String get code => 'fx.rate_required';

  @override
  bool operator ==(Object other) =>
      other is RateRequired && other.from == from && other.to == to;

  @override
  int get hashCode => Object.hash(RateRequired, from, to);
}
