import 'package:test/test.dart';
import 'package:xpense_shared/xpense_shared.dart';

import 'fixtures.dart';

void main() {
  group('ParseResult output (AI_PIPELINE 5, step 8)', () {
    test('maps every field to the shared schema', () {
      final json = parseText(
        'Gave Alex 300 yesterday from cash',
        iqdHome(),
      ).toParseResult().toJson();
      expect(json, {
        'amounts': [
          {
            'amountMinor': 300000,
            'currency': 'IQD',
            'value': '300000',
            'span': '300',
            'start': 10,
            'end': 13,
            'guessed': true,
          },
        ],
        'currency': 'IQD',
        'date': '2026-11-21',
        'hints': [
          {'kind': 'person', 'span': 'alex', 'id': 'p_alex', 'confidence': 0.9},
          {
            'kind': 'account',
            'span': 'cash',
            'id': 'acc_cash',
            'confidence': 0.8,
          },
        ],
        'ruleHits': [
          {
            'ruleId': 'r_alex',
            'field': 'accountId',
            'value': 'acc_cash',
            'confidence': 0.99,
          },
        ],
        'signals': {
          'amountCount': 1,
          'hasConjunction': false,
          'isQuestion': false,
          'isCommand': false,
          'hasPersonTransfer': true,
          'unresolved': ['category', 'intent'],
          'attachment': 'none',
        },
      });
    });

    final samples = [
      'lunch 15000 and taxi 20 dollars yesterday',
      'gave Omar 20000',
      r'$42.80 at Costco',
      'how much did we spend?',
      '',
    ];
    for (final text in samples) {
      test('"$text" round-trips through the schema', () {
        final result = parseText(text, iqdHome()).toParseResult();
        final again = ParseResult.$schema.parse(result.toJson());
        expect(again.toJson(), result.toJson());
      });
    }

    test('spans and offsets point into the normalised text', () {
      final parse = parseText('  Spent  25,000 DINARS on lunch ', iqdHome());
      final a = parse.amounts.single.toSchema();
      expect(parse.text.substring(a.start!, a.end), a.span);
      expect(a.span, '25,000 dinars');
    });
  });

  group('totality: any input gives a result', () {
    final inputs = [
      '',
      ' ',
      '?',
      r'$',
      r'$$$',
      'and and and',
      'a a a a',
      'half half half',
      '0',
      '00000000',
      '9' * 400,
      '1.2.3.4',
      ',,,..',
      '-5000',
      '5000-',
      '/',
      '1/',
      '/1/',
      '99/99/9999',
      '31/12/2026',
      'last',
      'last last friday',
      'the',
      'the 99th',
      'k',
      '5kk',
      'million million',
      'one one one',
      'twenty-',
      '-five',
      'x',
      '🙂 5000 🙂',
      'دينار ٢٥',
      '\u0000\u0001',
      'İİİ 5000',
      'please please please',
      'Gave',
      'A' * 1000,
    ];
    for (final input in inputs) {
      test('"${input.length > 20 ? '${input.substring(0, 20)}…' : input}"', () {
        final parse = parseText(input, iqdHome());
        final json = parse.toParseResult().toJson();
        expect(ParseResult.$schema.parse(json).toJson(), json);
        for (final a in parse.amounts) {
          expect(a.mention.start, lessThanOrEqualTo(a.mention.end));
          expect(a.mention.end, lessThanOrEqualTo(parse.text.length));
        }
        expect(
          parseReceipt([OcrLine(input)]).rows.length,
          lessThanOrEqualTo(1),
        );
      });
    }
  });
}
