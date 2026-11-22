import 'package:decimal/decimal.dart';
import 'package:test/test.dart';
import 'package:xpense_shared/xpense_shared.dart';

void main() {
  group('parseDigitGroup separators (AI_PIPELINE 5, step 2)', () {
    final cases = <({String text, String? value})>[
      (text: '25000', value: '25000'),
      (text: '25,000', value: '25000'),
      (text: '1,000,000', value: '1000000'),
      (text: '1.250.000', value: '1250000'),
      (text: '12.5', value: '12.5'),
      (text: '42.80', value: '42.8'),
      (text: '12,5', value: '12.5'),
      (text: '12,50', value: '12.5'),
      (text: '1,250.50', value: '1250.5'),
      (text: '1.250,50', value: '1250.5'),
      (text: '12.500', value: '12500'),
      (text: '0.500', value: '0.5'),
      (text: '1234.567', value: '1234.567'),
      (text: '1,23,456', value: '123456'),
      (text: '1.2.3', value: null),
      (text: '1,250.5.0', value: null),
      (text: '', value: null),
    ];
    for (final c in cases) {
      test('"${c.text}" → ${c.value}', () {
        expect(
          parseDigitGroup(c.text),
          c.value == null ? isNull : Decimal.parse(c.value!),
        );
      });
    }
  });

  group('readNumber words and multipliers (AI_PIPELINE 5, step 2)', () {
    final cases = <({String text, String value, int tokens, bool scaled})>[
      (text: '5k', value: '5000', tokens: 2, scaled: true),
      (text: '1.5m', value: '1500000', tokens: 2, scaled: true),
      (text: '5 k', value: '5000', tokens: 2, scaled: true),
      (text: '5 thousand', value: '5000', tokens: 2, scaled: true),
      (text: '2.5 million', value: '2500000', tokens: 2, scaled: true),
      (text: '5 grand', value: '5000', tokens: 2, scaled: true),
      (text: 'ten thousand', value: '10000', tokens: 2, scaled: true),
      (text: 'twenty five thousand', value: '25000', tokens: 3, scaled: true),
      (text: 'twenty-five thousand', value: '25000', tokens: 4, scaled: true),
      (
        text: 'two hundred fifty thousand',
        value: '250000',
        tokens: 4,
        scaled: true,
      ),
      (
        text: 'one hundred and fifty thousand',
        value: '150000',
        tokens: 5,
        scaled: true,
      ),
      (text: 'three hundred and fifty', value: '350', tokens: 4, scaled: false),
      (
        text: 'one and a half million',
        value: '1500000',
        tokens: 5,
        scaled: true,
      ),
      (text: 'a million and a half', value: '1500000', tokens: 5, scaled: true),
      (text: 'half a million', value: '500000', tokens: 3, scaled: true),
      (text: 'half million', value: '500000', tokens: 2, scaled: true),
      (text: 'quarter of a million', value: '250000', tokens: 4, scaled: true),
      (text: 'a quarter million', value: '250000', tokens: 3, scaled: true),
      (text: 'two and a half thousand', value: '2500', tokens: 5, scaled: true),
      (text: '1 and a half million', value: '1500000', tokens: 5, scaled: true),
      (text: 'two and a half', value: '2.5', tokens: 4, scaled: false),
      (text: 'a thousand', value: '1000', tokens: 2, scaled: true),
      (text: 'a hundred', value: '100', tokens: 2, scaled: false),
      (text: 'twenty five hundred', value: '2500', tokens: 3, scaled: false),
      (
        text: 'one thousand five hundred',
        value: '1500',
        tokens: 4,
        scaled: true,
      ),
      (text: 'fifty k', value: '50000', tokens: 2, scaled: true),
      (text: 'ninety nine', value: '99', tokens: 2, scaled: false),
      (text: 'seventeen', value: '17', tokens: 1, scaled: false),
      // Stops where English grammar stops.
      (text: 'five fifty', value: '5', tokens: 1, scaled: false),
      (text: 'twenty twenty', value: '20', tokens: 1, scaled: false),
      (text: '5000 and 2000', value: '5000', tokens: 1, scaled: false),
      (
        text: 'five thousand and twenty thousand',
        value: '5000',
        tokens: 2,
        scaled: true,
      ),
      (text: '5 thousand 500', value: '5000', tokens: 2, scaled: true),
    ];
    for (final c in cases) {
      test('"${c.text}" → ${c.value}', () {
        final phrase = readNumber(tokenize(c.text), 0);
        expect(phrase, isNotNull);
        expect(phrase!.value, Decimal.parse(c.value));
        expect(phrase.tokenEnd, c.tokens);
        expect(phrase.scaled, c.scaled);
      });
    }

    for (final text in ['half price', 'a coffee', 'million', 'and five', '']) {
      test('"$text" is not a number', () {
        expect(readNumber(tokenize(text), 0), isNull);
      });
    }
  });
}
