import 'dart:math';

import 'package:test/test.dart';
import 'package:xpense_shared/money/rounding.dart';
import 'package:xpense_shared/xpense_shared.dart';

FxRate _rate(String rate, [String pair = 'USD/IQD']) =>
    FxRate.parse(pair, rate).valueOrNull!;

void main() {
  group('divideRoundHalfEven', () {
    final cases = <({int n, int d, int q})>[
      (n: 5, d: 2, q: 2),
      (n: 7, d: 2, q: 4),
      (n: 3, d: 2, q: 2),
      (n: 1, d: 2, q: 0),
      (n: -5, d: 2, q: -2),
      (n: -7, d: 2, q: -4),
      (n: -1, d: 2, q: 0),
      (n: 5, d: -2, q: -2),
      (n: 10, d: 3, q: 3),
      (n: 11, d: 3, q: 4),
      (n: -11, d: 3, q: -4),
      (n: 0, d: 7, q: 0),
      (n: 6, d: 3, q: 2),
    ];
    for (final c in cases) {
      test('${c.n} / ${c.d} → ${c.q}', () {
        expect(
          divideRoundHalfEven(BigInt.from(c.n), BigInt.from(c.d)),
          BigInt.from(c.q),
        );
      });
    }

    test('zero denominator is a programmer error', () {
      expect(
        () => divideRoundHalfEven(BigInt.one, BigInt.zero),
        throwsArgumentError,
      );
    });

    test('property: nearest integer, ties to even (seeded random)', () {
      final random = Random(1520);
      for (var i = 0; i < 20000; i++) {
        final n = BigInt.from(random.nextInt(1 << 32) - (1 << 31));
        final d = BigInt.from(1 + random.nextInt(1000));
        final q = divideRoundHalfEven(n, d);
        final twiceError = ((q * d - n) * BigInt.two).abs();
        expect(twiceError <= d, isTrue, reason: '$n / $d → $q');
        if (twiceError == d) expect(q.isEven, isTrue, reason: '$n / $d → $q');
      }
    });
  });

  group('FxPair.parse', () {
    test('USD/IQD and IQD/USD', () {
      expect(FxPair.parse('USD/IQD').valueOrNull, FxPair.usdIqd);
      expect(FxPair.usdIqd.code, 'USD/IQD');
      expect(
        FxPair.parse('IQD/USD').valueOrNull,
        const FxPair(Currency.iqd, Currency.usd),
      );
    });

    final failures = <({String pair, MoneyFailure f})>[
      (pair: 'USDIQD', f: const MalformedPair('USDIQD')),
      (pair: 'usd/iqd', f: const MalformedPair('usd/iqd')),
      (pair: 'USD/USD', f: const MalformedPair('USD/USD')),
      (pair: 'USD / IQD', f: const MalformedPair('USD / IQD')),
      (pair: '', f: const MalformedPair('')),
      (pair: 'USD/EUR', f: const UnknownCurrency('EUR')),
      (pair: 'EUR/IQD', f: const UnknownCurrency('EUR')),
    ];
    for (final c in failures) {
      test('"${c.pair}" → ${c.f.code}', () {
        expect(FxPair.parse(c.pair).failureOrNull, c.f);
      });
    }
  });

  group('FxRate.parse', () {
    final ok = <({String rate, String canonical})>[
      (rate: '1520', canonical: '1520'),
      (rate: '1507.5', canonical: '1507.5'),
      (rate: '1507.50', canonical: '1507.5'),
      (rate: '0.000657', canonical: '0.000657'),
    ];
    for (final c in ok) {
      test('"${c.rate}" → "${c.canonical}"', () {
        final rate = _rate(c.rate);
        expect(rate.rateString, c.canonical);
        expect(rate.pair, FxPair.usdIqd);
      });
    }

    for (final bad in [
      '',
      '0',
      '0.0',
      '-1520',
      '+1520',
      '1,520',
      '1520.',
      '.5',
      '1e3',
      ' 1520',
      'abc',
      '١٥٢٠',
    ]) {
      test('"$bad" → fx.malformed_rate', () {
        expect(FxRate.parse('USD/IQD', bad).failureOrNull, MalformedRate(bad));
      });
    }

    test('a bad pair fails before the rate is read', () {
      expect(
        FxRate.parse('USD/EUR', 'x').failureOrNull,
        const UnknownCurrency('EUR'),
      );
    });
  });

  group('FxRate.convert (USD/IQD, half-even once)', () {
    final cases =
        <
          ({String rate, Money amount, Currency to, Money expected, String why})
        >[
          (
            rate: '1520',
            amount: const Money(1000, Currency.usd),
            to: Currency.iqd,
            expected: const Money(15200, Currency.iqd),
            why: r'$10.00 at 1520',
          ),
          (
            rate: '1705',
            amount: const Money(10000, Currency.usd),
            to: Currency.iqd,
            expected: const Money(170500, Currency.iqd),
            why: r'$100 at the market rate',
          ),
          (
            rate: '1520',
            amount: const Money(1, Currency.usd),
            to: Currency.iqd,
            expected: const Money(15, Currency.iqd),
            why: '15.2 rounds down',
          ),
          (
            rate: '1520',
            amount: const Money(3, Currency.usd),
            to: Currency.iqd,
            expected: const Money(46, Currency.iqd),
            why: '45.6 rounds up',
          ),
          (
            rate: '1507.5',
            amount: const Money(100, Currency.usd),
            to: Currency.iqd,
            expected: const Money(1508, Currency.iqd),
            why: '1507.5 ties to even 1508',
          ),
          (
            rate: '1507.5',
            amount: const Money(300, Currency.usd),
            to: Currency.iqd,
            expected: const Money(4522, Currency.iqd),
            why: '4522.5 ties to even 4522 (half-up would give 4523)',
          ),
          (
            rate: '1507.5',
            amount: const Money(-300, Currency.usd),
            to: Currency.iqd,
            expected: const Money(-4522, Currency.iqd),
            why: 'negative ties mirror',
          ),
          (
            rate: '1520',
            amount: const Money(10000, Currency.iqd),
            to: Currency.usd,
            expected: const Money(658, Currency.usd),
            why: 'IQD 10,000 → 6.578.. USD',
          ),
          (
            rate: '1520',
            amount: const Money(1520, Currency.iqd),
            to: Currency.usd,
            expected: const Money(100, Currency.usd),
            why: 'exactly one dollar',
          ),
          (
            rate: '2000',
            amount: const Money(10, Currency.iqd),
            to: Currency.usd,
            expected: const Money(0, Currency.usd),
            why: '0.5 cent ties to even 0',
          ),
          (
            rate: '2000',
            amount: const Money(30, Currency.iqd),
            to: Currency.usd,
            expected: const Money(2, Currency.usd),
            why: '1.5 cents ties to even 2',
          ),
          (
            rate: '2000',
            amount: const Money(50, Currency.iqd),
            to: Currency.usd,
            expected: const Money(2, Currency.usd),
            why: '2.5 cents ties to even 2 (half-up would give 3)',
          ),
          (
            rate: '1507.5',
            amount: const Money(15075, Currency.iqd),
            to: Currency.usd,
            expected: const Money(1000, Currency.usd),
            why: 'decimal rate divides exactly',
          ),
          (
            rate: '1520',
            amount: const Money(1234, Currency.usd),
            to: Currency.usd,
            expected: const Money(1234, Currency.usd),
            why: 'same currency is unchanged',
          ),
        ];
    for (final c in cases) {
      test(c.why, () {
        expect(_rate(c.rate).convert(c.amount, c.to).valueOrNull, c.expected);
      });
    }

    test('an inverted pair (IQD/USD) converts consistently', () {
      final inverted = _rate('0.0005', 'IQD/USD');
      expect(
        inverted
            .convert(const Money(50, Currency.iqd), Currency.usd)
            .valueOrNull,
        const Money(2, Currency.usd),
      );
      expect(
        inverted
            .convert(const Money(100, Currency.usd), Currency.iqd)
            .valueOrNull,
        const Money(2000, Currency.iqd),
      );
    });

    test('rounds once: no float drift on large amounts', () {
      // 123,456,789.01 USD at 1507.5 = 186,111,109,432.575 IQD exactly.
      expect(
        _rate('1507.5')
            .convert(const Money(12345678901, Currency.usd), Currency.iqd)
            .valueOrNull,
        const Money(186111109433, Currency.iqd),
      );
    });

    test('a result beyond 64 bits is a typed failure', () {
      expect(
        _rate('1520')
            .convert(
              const Money(9223372036854775807, Currency.usd),
              Currency.iqd,
            )
            .failureOrNull,
        isA<AmountOutOfRange>(),
      );
    });
  });

  group('toBaseAmount (baseAmountMinor, base USD per D-37)', () {
    test('same currency needs no rate', () {
      expect(
        toBaseAmount(const Money(1250, Currency.usd), Currency.usd).valueOrNull,
        const Money(1250, Currency.usd),
      );
    });

    test('a different currency without a rate is RateRequired', () {
      expect(
        toBaseAmount(
          const Money(10000, Currency.iqd),
          Currency.usd,
        ).failureOrNull,
        const RateRequired(from: 'IQD', to: 'USD'),
      );
    });

    test('IQD lunch in a USD household', () {
      expect(
        toBaseAmount(
          const Money(10000, Currency.iqd),
          Currency.usd,
          rate: _rate('1705'),
        ).valueOrNull,
        const Money(587, Currency.usd),
      );
    });
  });
}
