import 'package:test/test.dart';
import 'package:xpense_shared/xpense_shared.dart';

void main() {
  group('normalize (AI_PIPELINE 5, step 1)', () {
    final cases = <({String raw, String text})>[
      (raw: '  Spent 25,000  dinars  ', text: 'spent 25,000 dinars'),
      (raw: 'LUNCH\t15K', text: 'lunch 15k'),
      (raw: 'line\nbreak\r\nhere', text: 'line break here'),
      (raw: 'non breaking space', text: 'non breaking space'),
      (raw: 'Alex’s gift', text: "alex's gift"),
      (raw: '“quoted”', text: '"quoted"'),
      (raw: '5–6 and 7—8 and 9−1', text: '5-6 and 7-8 and 9-1'),
      (raw: 'zero​width﻿', text: 'zerowidth'),
      (raw: '', text: ''),
      (raw: '   \n\t ', text: ''),
      (raw: 'Café 3000', text: 'café 3000'),
      (raw: r'$42.80 AT COSTCO', text: r'$42.80 at costco'),
    ];
    for (final c in cases) {
      final name = c.raw
          .replaceAll('\n', r'\n')
          .replaceAll('\r', r'\r')
          .replaceAll('\t', r'\t');
      test('"$name" → "${c.text}"', () {
        final n = normalize(c.raw);
        expect(n.text, c.text);
        expect(normalizeText(c.raw), c.text);
        expect(n.cased.length, n.text.length);
        expect(n.cased.toLowerCase(), n.text);
      });
    }

    test('keeps original case in the aligned copy', () {
      final n = normalize('  Gave  Alex 300 ');
      expect(n.text, 'gave alex 300');
      expect(n.cased, 'Gave Alex 300');
    });

    test('a letter whose lower case changes length keeps its form', () {
      final n = normalize('İstanbul');
      expect(n.text.length, n.cased.length);
    });
  });
}
