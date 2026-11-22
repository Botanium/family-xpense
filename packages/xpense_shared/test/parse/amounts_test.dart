import 'package:test/test.dart';
import 'package:xpense_shared/xpense_shared.dart';

import 'fixtures.dart';

typedef AmountCase = ({String text, List<(int?, String?, bool)> amounts});

/// `(amountMinor, currency, guessed)` per amount.
List<(int?, String?, bool)> read(String text, ParseContext context) => [
  for (final a in parseText(text, context).amounts)
    (a.money?.minorUnits, a.currency?.code, a.guessed),
];

void main() {
  group('amounts and currency words, IQD default (AI_PIPELINE 5, 2-4)', () {
    final cases = <AmountCase>[
      (text: 'Spent 25,000 dinars on lunch', amounts: [(25000, 'IQD', false)]),
      (text: 'lunch 15k', amounts: [(15000, 'IQD', false)]),
      (text: 'taxi 5000', amounts: [(5000, 'IQD', false)]),
      (text: 'ten thousand dinars', amounts: [(10000, 'IQD', false)]),
      (text: 'twenty-five thousand', amounts: [(25000, 'IQD', false)]),
      (text: 'one and a half million rent', amounts: [(1500000, 'IQD', false)]),
      (text: 'a million and a half', amounts: [(1500000, 'IQD', false)]),
      (text: 'half a million on the car', amounts: [(500000, 'IQD', false)]),
      (text: 'quarter of a million', amounts: [(250000, 'IQD', false)]),
      (text: '1.250.000 for the car', amounts: [(1250000, 'IQD', false)]),
      (text: '12.500 for fuel', amounts: [(12500, 'IQD', false)]),
      (text: '2.5m', amounts: [(2500000, 'IQD', false)]),
      (text: '1,5k', amounts: [(1500, 'IQD', false)]),
      (text: 'fifty k', amounts: [(50000, 'IQD', false)]),
      (text: '5 grand', amounts: [(5000, 'IQD', false)]),
      (text: r'$42.80 at the market', amounts: [(4280, 'USD', false)]),
      (text: '15 dollars lunch', amounts: [(1500, 'USD', false)]),
      (text: 'usd 50 fuel', amounts: [(5000, 'USD', false)]),
      (text: '50 usd fuel', amounts: [(5000, 'USD', false)]),
      (text: r'50$ fuel', amounts: [(5000, 'USD', false)]),
      (text: 'usd50', amounts: [(5000, 'USD', false)]),
      (text: '20 bucks', amounts: [(2000, 'USD', false)]),
      (text: '20 us dollars', amounts: [(2000, 'USD', false)]),
      (text: 'one dollar', amounts: [(100, 'USD', false)]),
      (text: r'$5k', amounts: [(500000, 'USD', false)]),
      (text: '5 dollars and 50 cents', amounts: [(550, 'USD', false)]),
      (text: '75 cents', amounts: [(75, 'USD', false)]),
      (text: 'paid 1,250.50 dollars', amounts: [(125050, 'USD', false)]),
      (text: 'paid 1.250,50 dollars', amounts: [(125050, 'USD', false)]),
      (text: '12,50 dollars', amounts: [(1250, 'USD', false)]),
      (
        text: 'three hundred and fifty dollars',
        amounts: [(35000, 'USD', false)],
      ),
      (text: '25000 id', amounts: [(25000, 'IQD', false)]),
      (text: '25000 iraqi dinars', amounts: [(25000, 'IQD', false)]),
      (text: 'iqd 25000', amounts: [(25000, 'IQD', false)]),
      (
        text: 'dollars: lunch 15, taxi 5',
        amounts: [(1500, 'USD', false), (500, 'USD', false)],
      ),
      (
        text: 'salary 3,200 and rent 1,400',
        amounts: [(3200, 'IQD', false), (1400, 'IQD', false)],
      ),
      (
        text: 'lunch 15000 and taxi 20 dollars',
        amounts: [(15000, 'IQD', false), (2000, 'USD', false)],
      ),
      (
        text: 'five thousand and twenty thousand',
        amounts: [(5000, 'IQD', false), (20000, 'IQD', false)],
      ),
    ];
    for (final c in cases) {
      test('"${c.text}"', () => expect(read(c.text, iqdHome()), c.amounts));
    }
  });

  group('not money (AI_PIPELINE 5, step 2)', () {
    final cases = <({String text, List<String> spans})>[
      (text: 'bought 2 kg tomatoes for 3000', spans: ['3000']),
      (text: 'two coffees 6000', spans: ['6000']),
      (text: '2 coffees 6000', spans: ['6000']),
      (text: 'one coffee 3000', spans: ['3000']),
      (text: 'meeting at 5pm, lunch 20000', spans: ['20000']),
      (text: 'at 5 pm lunch 20000', spans: ['20000']),
      (text: 'at 5:30 lunch 20000', spans: ['20000']),
      (text: 'call 07701234567 about 30000', spans: ['30000']),
      (text: '10% off, paid 9000', spans: ['9000']),
      (text: '3 x 1500', spans: ['1500']),
      (text: '2x bread 1500', spans: ['1500']),
      (text: '#3 table 25000', spans: ['25000']),
      (text: 'rent for 3 months 1200', spans: ['1200']),
      (text: 'march 2026 3000', spans: ['3000']),
      (text: 'delete the last one', spans: []),
      (text: 'half price shirt 20000', spans: ['20000']),
      (text: 'a coffee and a cake 4000', spans: ['4000']),
      (text: 'paid 3000 on the 5th', spans: ['3000']),
      (text: 'two coffees', spans: ['two']),
    ];
    for (final c in cases) {
      test('"${c.text}" → ${c.spans}', () {
        final spans = parseText(c.text, iqdHome()).amounts.map((a) => a.span);
        expect(spans, c.spans);
      });
    }
  });

  group('dropped thousands and the magnitude check (AI_PIPELINE 5, 3-4)', () {
    final cases = <({String text, String ctx, (int?, String?, bool) amount})>[
      // IQD default account: bare numbers under 1,000 are thousands.
      (text: '25 for lunch', ctx: 'iqd', amount: (25000, 'IQD', true)),
      (text: 'paid 12.5 for bread', ctx: 'iqd', amount: (12500, 'IQD', true)),
      (text: 'tea 0.25', ctx: 'iqd', amount: (250, 'IQD', true)),
      (text: '999 taxi', ctx: 'iqd', amount: (999000, 'IQD', true)),
      (text: 'two hundred fifty', ctx: 'iqd', amount: (250000, 'IQD', true)),
      (text: '1000 taxi', ctx: 'iqd', amount: (1000, 'IQD', false)),
      (text: '25 dinars', ctx: 'iqd', amount: (25000, 'IQD', true)),
      (text: '250 dinars', ctx: 'iqd', amount: (250000, 'IQD', true)),
      (text: 'spent 0', ctx: 'iqd', amount: (0, 'IQD', false)),
      // Not a multiple of 0.25 thousand: not expanded; decimals mean USD.
      (text: '7.3 for tea', ctx: 'iqd', amount: (730, 'USD', true)),
      (text: '0.1 for gum', ctx: 'iqd', amount: (10, 'USD', true)),
      (text: '42.80 snacks', ctx: 'iqd', amount: (4280, 'USD', true)),
      // A multiplier means the number is not bare.
      (text: '5k taxi', ctx: 'iqd', amount: (5000, 'IQD', false)),
      (text: 'five thousand', ctx: 'iqd', amount: (5000, 'IQD', false)),
      // A dollar word is never expanded.
      (text: '25 dollars', ctx: 'iqd', amount: (2500, 'USD', false)),
      // USD default account: no expansion; 10,000 or more is IQD.
      (text: '25 for lunch', ctx: 'usd', amount: (2500, 'USD', false)),
      (text: 'lunch 15', ctx: 'usd', amount: (1500, 'USD', false)),
      (text: '9999 rent', ctx: 'usd', amount: (999900, 'USD', false)),
      (text: '10000 lunch', ctx: 'usd', amount: (10000, 'IQD', true)),
      (text: '15k taxi', ctx: 'usd', amount: (15000, 'IQD', true)),
      (text: '5k taxi', ctx: 'usd', amount: (500000, 'USD', false)),
      (text: '25 dinars', ctx: 'usd', amount: (25000, 'IQD', true)),
      (text: '25000 dollars', ctx: 'usd', amount: (2500000, 'USD', false)),
      // The named account's currency beats the default.
      (text: 'paid with visa 30', ctx: 'iqd', amount: (3000, 'USD', false)),
      (text: 'paid 30 from the card', ctx: 'iqd', amount: (3000, 'USD', false)),
      (text: '20 from cash wallet', ctx: 'usd', amount: (20000, 'IQD', true)),
      // A learned rule's account comes next.
      (text: '42.80 at Costco', ctx: 'iqd', amount: (4280, 'USD', false)),
      // No account at all: only the magnitude check.
      (text: '25 for lunch', ctx: 'bare', amount: (null, null, false)),
      (text: '15000 lunch', ctx: 'bare', amount: (15000, 'IQD', true)),
      (text: '25 dinars', ctx: 'bare', amount: (25000, 'IQD', true)),
      // Too precise for an explicit currency: value kept, no money.
      (text: '42.5 dinars', ctx: 'iqd', amount: (42500, 'IQD', true)),
      (text: '1.2345 dollars', ctx: 'iqd', amount: (null, 'USD', false)),
    ];
    ParseContext context(String name) => switch (name) {
      'usd' => usdHome(),
      'bare' => bareContext(),
      _ => iqdHome(),
    };
    for (final c in cases) {
      test('${c.ctx}: "${c.text}" → ${c.amount}', () {
        expect(read(c.text, context(c.ctx)), [c.amount]);
      });
    }

    test('an amount too large for an int keeps its value but no money', () {
      final a = parseText('99999999999999999999999 dinars', iqdHome()).amounts;
      expect(a.single.money, isNull);
      expect(a.single.value.toString(), '99999999999999999999999');
      expect(a.single.toSchema().amountMinor, isNull);
    });

    test('the source of each currency is reported', () {
      CurrencySource source(String text, ParseContext ctx) =>
          parseText(text, ctx).amounts.single.source;
      expect(source('15 dollars', iqdHome()), CurrencySource.word);
      expect(source('visa 30', iqdHome()), CurrencySource.namedAccount);
      expect(source('costco 30', iqdHome()), CurrencySource.ruleAccount);
      expect(source('taxi 5000', iqdHome()), CurrencySource.defaultAccount);
      expect(source('10000 lunch', usdHome()), CurrencySource.magnitude);
      expect(source('7.3 tea', iqdHome()), CurrencySource.decimals);
      expect(source('25 lunch', bareContext()), CurrencySource.none);
    });
  });

  group('message currency', () {
    final cases = <({String text, String? currency})>[
      (text: 'lunch 15000', currency: 'IQD'),
      (text: 'lunch 15 dollars', currency: 'USD'),
      (text: 'lunch 15000 and taxi 20 dollars', currency: null),
      (text: 'how many dollars did we spend', currency: 'USD'),
      (text: 'hello', currency: null),
    ];
    for (final c in cases) {
      test('"${c.text}" → ${c.currency}', () {
        expect(parseText(c.text, iqdHome()).currency?.code, c.currency);
      });
    }
  });
}
