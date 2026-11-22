/// Exact integer rounding for the money core.
///
/// `package:decimal` 3.2.6 rounds half-up only (`Decimal.round`), so the
/// half-even rule of DATA_MODEL 1 is implemented here on exact integers.
library;

/// Divides [numerator] by a non-zero [denominator] and rounds the exact
/// quotient half-to-even (banker's rounding).
///
/// Ties go to the even neighbour: `5/2 → 2`, `7/2 → 4`, `-5/2 → -2`.
/// This is the only rounding step of an FX conversion (DATA_MODEL 1).
BigInt divideRoundHalfEven(BigInt numerator, BigInt denominator) {
  if (denominator == BigInt.zero) {
    throw ArgumentError.value(denominator, 'denominator', 'must not be zero');
  }
  var n = numerator;
  var d = denominator;
  if (d.isNegative) {
    n = -n;
    d = -d;
  }
  // `~/` truncates toward zero; `remainder` takes the sign of `n`.
  var quotient = n ~/ d;
  final twiceRemainder = n.remainder(d).abs() * BigInt.two;
  final comparison = twiceRemainder.compareTo(d);
  if (comparison > 0 || (comparison == 0 && quotient.isOdd)) {
    quotient += n.isNegative ? -BigInt.one : BigInt.one;
  }
  return quotient;
}

/// `10^exponent` as a [BigInt], for a non-negative [exponent].
BigInt pow10(int exponent) => BigInt.from(10).pow(exponent);
