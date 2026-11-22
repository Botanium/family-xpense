import 'dart:math';

import 'package:test/test.dart';
import 'package:xpense_shared/xpense_shared.dart';

void main() {
  group('allocate verified vectors (value-objects skill)', () {
    final cases = <({int amount, List<int> weights, List<int> expected})>[
      (amount: 1001, weights: [1, 1, 1], expected: [334, 334, 333]),
      (amount: 660, weights: [1584, 4033, 1933], expected: [138, 353, 169]),
      (amount: 1510, weights: [1584, 4033, 1933], expected: [317, 807, 386]),
    ];
    for (final c in cases) {
      test('allocate(${c.amount}, ${c.weights}) == ${c.expected}', () {
        expect(allocate(c.amount, c.weights), c.expected);
      });
    }
  });

  group('allocate edge policies', () {
    final cases =
        <({String name, int amount, List<int> weights, List<int> expected})>[
          (name: 'empty weights', amount: 100, weights: [], expected: []),
          (name: 'single weight', amount: 7, weights: [3], expected: [7]),
          (name: 'zero amount', amount: 0, weights: [1, 2], expected: [0, 0]),
          (
            name: 'all-zero weights split equally',
            amount: 10,
            weights: [0, 0, 0],
            expected: [4, 3, 3],
          ),
          (
            name: 'negative weight counts as zero',
            amount: 10,
            weights: [-5, 1, 1],
            expected: [0, 5, 5],
          ),
          (
            name: 'negative amount mirrors',
            amount: -1001,
            weights: [1, 1, 1],
            expected: [-334, -334, -333],
          ),
          (
            name: 'ties go to the lower index',
            amount: 2,
            weights: [1, 1, 1],
            expected: [1, 1, 0],
          ),
          (
            name: 'zero weight gets nothing',
            amount: 5,
            weights: [1, 0, 1],
            expected: [3, 0, 2],
          ),
          (
            name: 'large values do not overflow',
            amount: 9000000000000000000,
            weights: [1000000000, 1000000000, 1000000001],
            expected: [
              2999999999000000000,
              2999999999000000000,
              3000000002000000000,
            ],
          ),
        ];
    for (final c in cases) {
      test(c.name, () => expect(allocate(c.amount, c.weights), c.expected));
    }

    test('the most negative int does not overflow', () {
      const minInt = -9223372036854775808;
      final shares = allocate(minInt, [1, 1]);
      expect(shares, [-4611686018427387904, -4611686018427387904]);
    });
  });

  group('allocate properties (seeded random)', () {
    const iterations = 5000;
    final random = Random(20261122);

    int randomAmount() {
      final magnitude = switch (random.nextInt(4)) {
        0 => random.nextInt(10),
        1 => random.nextInt(100000),
        2 => random.nextInt(1 << 31) * 1000,
        _ => random.nextInt(1 << 31) * (1 << 20),
      };
      return random.nextBool() ? magnitude : -magnitude;
    }

    List<int> randomWeights() {
      final count = 1 + random.nextInt(25);
      return [
        for (var i = 0; i < count; i++)
          switch (random.nextInt(6)) {
            0 => 0,
            1 => 1,
            5 => -random.nextInt(10),
            2 => random.nextInt(100),
            _ => random.nextInt(1000000),
          },
      ];
    }

    test('parts always sum exactly to the amount', () {
      for (var i = 0; i < iterations; i++) {
        final amount = randomAmount();
        final weights = randomWeights();
        final shares = allocate(amount, weights);
        expect(shares, hasLength(weights.length));
        expect(
          shares.fold<int>(0, (a, b) => a + b),
          amount,
          reason: 'allocate($amount, $weights) = $shares',
        );
      }
    });

    test('each part is within one unit of its exact share', () {
      for (var i = 0; i < iterations; i++) {
        final amount = randomAmount();
        final weights = randomWeights();
        final shares = allocate(amount, weights);
        final positive = [for (final w in weights) max(w, 0)];
        var total = positive.fold<int>(0, (a, b) => a + b);
        final effective = total == 0
            ? List<int>.filled(weights.length, 1)
            : positive;
        if (total == 0) total = weights.length;
        for (var k = 0; k < shares.length; k++) {
          // |share * total - amount * weight| < total, in exact arithmetic.
          final error =
              BigInt.from(shares[k]) * BigInt.from(total) -
              BigInt.from(amount) * BigInt.from(effective[k]);
          expect(
            error.abs() < BigInt.from(total),
            isTrue,
            reason: 'allocate($amount, $weights)[$k] = ${shares[k]}',
          );
        }
      }
    });

    test('parts carry the sign of the amount', () {
      for (var i = 0; i < iterations; i++) {
        final amount = randomAmount();
        final shares = allocate(amount, randomWeights());
        for (final share in shares) {
          expect(amount >= 0 ? share >= 0 : share <= 0, isTrue);
        }
      }
    });

    test('is deterministic', () {
      for (var i = 0; i < 500; i++) {
        final amount = randomAmount();
        final weights = randomWeights();
        expect(allocate(amount, weights), allocate(amount, weights));
      }
    });
  });

  group('Money.allocate and split', () {
    test('keep the currency and sum to the whole', () {
      const total = Money(1510, Currency.usd);
      final parts = total.allocate([1584, 4033, 1933]);
      expect(parts, const [
        Money(317, Currency.usd),
        Money(807, Currency.usd),
        Money(386, Currency.usd),
      ]);
      expect(parts.reduce((a, b) => a + b), total);
    });

    test('split into equal parts', () {
      expect(const Money(10000, Currency.iqd).split(3), const [
        Money(3334, Currency.iqd),
        Money(3333, Currency.iqd),
        Money(3333, Currency.iqd),
      ]);
      expect(const Money(5, Currency.usd).split(0), isEmpty);
      expect(const Money(5, Currency.usd).split(-1), isEmpty);
    });
  });
}
