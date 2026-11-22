import 'package:test/test.dart';
import 'package:xpense_shared/xpense_shared.dart';

void main() {
  group('Currency exponent table (DATA_MODEL 1, D-14)', () {
    final cases = <({String code, Currency currency, int exp, int perMajor})>[
      (code: 'USD', currency: Currency.usd, exp: 2, perMajor: 100),
      (code: 'IQD', currency: Currency.iqd, exp: 0, perMajor: 1),
    ];
    for (final c in cases) {
      test(c.code, () {
        expect(Currency.tryParse(c.code), c.currency);
        expect(Currency.parse(c.code), Ok<Currency, MoneyFailure>(c.currency));
        expect(c.currency.exponent, c.exp);
        expect(c.currency.minorPerMajor, c.perMajor);
      });
    }

    test('only USD and IQD are supported, in step with the const list', () {
      expect(Currency.values.map((c) => c.code), supportedCurrencyCodes);
    });

    test('table version is 1', () => expect(moneySchemaVersion, 1));

    for (final code in ['EUR', 'usd', 'iqd', '', 'US D', 'IQD ', 'XXX']) {
      test('unknown code "$code" is a typed failure, not a default', () {
        expect(Currency.tryParse(code), isNull);
        final result = Currency.parse(code);
        expect(result.failureOrNull, UnknownCurrency(code));
        expect(result.failureOrNull?.code, 'money.unknown_currency');
      });
    }
  });

  group('Money.parseMajor', () {
    final ok = <({String input, Currency currency, int minor})>[
      (input: '12.50', currency: Currency.usd, minor: 1250),
      (input: '12.5', currency: Currency.usd, minor: 1250),
      (input: '12', currency: Currency.usd, minor: 1200),
      (input: '0.01', currency: Currency.usd, minor: 1),
      (input: '0', currency: Currency.usd, minor: 0),
      (input: '12.340', currency: Currency.usd, minor: 1234),
      (input: '007.10', currency: Currency.usd, minor: 710),
      (input: '25000', currency: Currency.iqd, minor: 25000),
      (input: '25000.0', currency: Currency.iqd, minor: 25000),
      (input: '250', currency: Currency.iqd, minor: 250),
      (input: '1', currency: Currency.iqd, minor: 1),
    ];
    for (final c in ok) {
      test('"${c.input}" ${c.currency} → ${c.minor}', () {
        expect(
          Money.parseMajor(c.input, c.currency).valueOrNull,
          Money(c.minor, c.currency),
        );
      });
    }

    final failures = <({String input, Currency currency, MoneyFailure f})>[
      (
        input: '12.345',
        currency: Currency.usd,
        f: const AmountTooPrecise('12.345', 2),
      ),
      (
        input: '0.5',
        currency: Currency.iqd,
        f: const AmountTooPrecise('0.5', 0),
      ),
      (
        input: '1,000',
        currency: Currency.iqd,
        f: const MalformedAmount('1,000'),
      ),
      (input: '', currency: Currency.usd, f: const MalformedAmount('')),
      (input: '-5', currency: Currency.usd, f: const MalformedAmount('-5')),
      (input: '+5', currency: Currency.usd, f: const MalformedAmount('+5')),
      (input: '.5', currency: Currency.usd, f: const MalformedAmount('.5')),
      (input: '5.', currency: Currency.usd, f: const MalformedAmount('5.')),
      (input: '1e3', currency: Currency.usd, f: const MalformedAmount('1e3')),
      (input: ' 5', currency: Currency.usd, f: const MalformedAmount(' 5')),
      // Arabic-Indic digits: folding is deferred (D-36).
      (input: '١٢', currency: Currency.iqd, f: const MalformedAmount('١٢')),
      (
        input: '99999999999999999999',
        currency: Currency.iqd,
        f: const AmountOutOfRange('99999999999999999999'),
      ),
    ];
    for (final c in failures) {
      test('"${c.input}" ${c.currency} → ${c.f.code}', () {
        expect(Money.parseMajor(c.input, c.currency).failureOrNull, c.f);
      });
    }
  });

  group('Money.toMajorString', () {
    final cases = <({Money money, String text})>[
      (money: const Money(1250, Currency.usd), text: '12.50'),
      (money: const Money(5, Currency.usd), text: '0.05'),
      (money: const Money(-5, Currency.usd), text: '-0.05'),
      (money: const Money(0, Currency.usd), text: '0.00'),
      (money: const Money(100, Currency.usd), text: '1.00'),
      (money: const Money(25000, Currency.iqd), text: '25000'),
      (money: const Money(-3, Currency.iqd), text: '-3'),
      (money: const Money.zero(Currency.iqd), text: '0'),
    ];
    for (final c in cases) {
      test('${c.money.minorUnits} ${c.money.currency} → ${c.text}', () {
        expect(c.money.toMajorString(), c.text);
        expect(c.money.toString(), '${c.text} ${c.money.currency.code}');
      });
    }

    test('round-trips through parseMajor for non-negative amounts', () {
      for (final minor in [0, 1, 9, 10, 99, 100, 101, 123456789]) {
        for (final currency in Currency.values) {
          final money = Money(minor, currency);
          expect(
            Money.parseMajor(money.toMajorString(), currency).valueOrNull,
            money,
          );
        }
      }
    });
  });

  group('Money arithmetic', () {
    const a = Money(1250, Currency.usd);
    const b = Money(250, Currency.usd);
    const dinars = Money(1000, Currency.iqd);

    test('same-currency operations', () {
      expect(a + b, const Money(1500, Currency.usd));
      expect(a - b, const Money(1000, Currency.usd));
      expect(-a, const Money(-1250, Currency.usd));
      expect(a.compareTo(b), greaterThan(0));
      expect(b.compareTo(a), lessThan(0));
      expect(a.compareTo(const Money(1250, Currency.usd)), 0);
      expect(const Money.zero(Currency.usd).isZero, isTrue);
      expect((-a).isNegative, isTrue);
    });

    test('cross-currency arithmetic is a programmer error', () {
      expect(() => a + dinars, throwsArgumentError);
      expect(() => a - dinars, throwsArgumentError);
      expect(() => a.compareTo(dinars), throwsArgumentError);
    });

    test('value equality includes the currency', () {
      expect(const Money(1000, Currency.usd), isNot(dinars));
      expect(const Money(1000, Currency.iqd).hashCode, dinars.hashCode);
    });
  });

  group('Money arithmetic at the 64-bit boundaries', () {
    const maxInt = 9223372036854775807;
    const minInt = -9223372036854775808;
    Money iqd(int minor) => Money(minor, Currency.iqd);

    final inRange = <({String name, Money Function() op, int expected})>[
      (name: 'max + 0', op: () => iqd(maxInt) + iqd(0), expected: maxInt),
      (name: 'max + -1', op: () => iqd(maxInt) + iqd(-1), expected: maxInt - 1),
      (name: 'min + 0', op: () => iqd(minInt) + iqd(0), expected: minInt),
      (name: 'max + min', op: () => iqd(maxInt) + iqd(minInt), expected: -1),
      (name: 'min + 1', op: () => iqd(minInt) + iqd(1), expected: minInt + 1),
      (
        name: '(max - 1) + 1',
        op: () => iqd(maxInt - 1) + iqd(1),
        expected: maxInt,
      ),
      (name: 'max - 0', op: () => iqd(maxInt) - iqd(0), expected: maxInt),
      (name: 'min - 0', op: () => iqd(minInt) - iqd(0), expected: minInt),
      (name: 'max - max', op: () => iqd(maxInt) - iqd(maxInt), expected: 0),
      (name: 'min - min', op: () => iqd(minInt) - iqd(minInt), expected: 0),
      (name: '-1 - max', op: () => iqd(-1) - iqd(maxInt), expected: minInt),
      (name: '0 - max', op: () => iqd(0) - iqd(maxInt), expected: -maxInt),
      (
        name: '(min + 1) - 1',
        op: () => iqd(minInt + 1) - iqd(1),
        expected: minInt,
      ),
      (name: '-max', op: () => -iqd(maxInt), expected: -maxInt),
      (name: '-(min + 1)', op: () => -iqd(minInt + 1), expected: maxInt),
      (name: '-0', op: () => -iqd(0), expected: 0),
    ];
    for (final c in inRange) {
      test('${c.name} stays exact', () {
        expect(c.op(), iqd(c.expected));
      });
    }

    final overflowing = <({String name, Money Function() op})>[
      (name: 'max + 1', op: () => iqd(maxInt) + iqd(1)),
      (name: 'max + max', op: () => iqd(maxInt) + iqd(maxInt)),
      (name: 'min + -1', op: () => iqd(minInt) + iqd(-1)),
      (name: 'min + min', op: () => iqd(minInt) + iqd(minInt)),
      (name: 'min - 1', op: () => iqd(minInt) - iqd(1)),
      (name: 'max - -1', op: () => iqd(maxInt) - iqd(-1)),
      (name: 'max - min', op: () => iqd(maxInt) - iqd(minInt)),
      (name: '0 - min', op: () => iqd(0) - iqd(minInt)),
      (name: 'min - max', op: () => iqd(minInt) - iqd(maxInt)),
      (name: '-min', op: () => -iqd(minInt)),
    ];
    for (final c in overflowing) {
      test('${c.name} throws instead of wrapping', () {
        expect(c.op, throwsStateError);
      });
    }

    test('USD overflows the same way', () {
      expect(
        () => const Money(maxInt, Currency.usd) + const Money(1, Currency.usd),
        throwsStateError,
      );
    });

    test('a currency mismatch is reported before overflow', () {
      expect(
        () => iqd(maxInt) + const Money(1, Currency.usd),
        throwsArgumentError,
      );
    });
  });
}
