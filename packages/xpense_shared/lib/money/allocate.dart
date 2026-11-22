/// Splits [amount] minor units across [weights] by largest remainder
/// (Hamilton), so that the parts always sum exactly to [amount].
///
/// Every division of money (receipt split, shared items, proration) goes
/// through this function (DATA_MODEL 1). It is total and never throws:
///
/// - empty [weights] returns an empty list;
/// - a negative [amount] is split as its absolute value and negated, so
///   refunds mirror charges;
/// - negative weights count as zero;
/// - if every weight is zero, the amount is split equally;
/// - leftover units go to the largest remainders, ties to the lower index,
///   so the result is deterministic.
///
/// Arithmetic is exact ([BigInt] internally), so large amounts and weights
/// cannot overflow mid-computation.
List<int> allocate(int amount, List<int> weights) {
  final count = weights.length;
  if (count == 0) return const [];

  final negative = amount < 0;
  final whole = BigInt.from(amount).abs();
  final effective = [for (final w in weights) BigInt.from(w < 0 ? 0 : w)];
  var total = effective.fold(BigInt.zero, (sum, w) => sum + w);
  if (total == BigInt.zero) {
    effective.fillRange(0, count, BigInt.one);
    total = BigInt.from(count);
  }

  final shares = List<BigInt>.filled(count, BigInt.zero);
  final remainders = <({BigInt remainder, int index})>[];
  var distributed = BigInt.zero;
  for (var i = 0; i < count; i++) {
    // Multiply first, then divide: no fractional intermediate.
    final product = whole * effective[i];
    final share = product ~/ total;
    shares[i] = share;
    distributed += share;
    remainders.add((remainder: product % total, index: i));
  }

  // The leftover is always in 0 ..< count.
  var leftover = (whole - distributed).toInt();
  remainders.sort(
    (a, b) => a.remainder != b.remainder
        ? b.remainder.compareTo(a.remainder)
        : a.index.compareTo(b.index),
  );
  for (var k = 0; leftover > 0; k++, leftover--) {
    final index = remainders[k].index;
    shares[index] += BigInt.one;
  }

  final result = [for (final s in shares) (negative ? -s : s).toInt()];
  assert(
    result.fold<int>(0, (sum, s) => sum + s) == amount,
    'allocate must be exact',
  );
  return result;
}
