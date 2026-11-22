import 'package:test/test.dart';
import 'package:xpense_shared/xpense_shared.dart';

void main() {
  group('lexicons keyed by language (AI_PIPELINE 5, D-36)', () {
    final cases = <({String code, String expected})>[
      (code: 'en', expected: 'en'),
      (code: 'en-US', expected: 'en'),
      (code: 'en_GB', expected: 'en'),
      (code: 'EN', expected: 'en'),
      (code: 'ckb', expected: 'en'),
      (code: 'ar', expected: 'en'),
      (code: '', expected: 'en'),
    ];
    for (final c in cases) {
      test('"${c.code}" → ${c.expected}', () {
        expect(lexiconFor(c.code).languageCode, c.expected);
      });
    }

    test('only English is filled for now', () {
      expect(parserLexicons.keys, ['en']);
    });

    test('every lexicon phrase is already normalised', () {
      const lex = englishLexicon;
      final phrases = <String>[
        ...lex.units.keys,
        ...lex.tens.keys,
        ...lex.scaleWords.keys,
        ...lex.currencyWords.keys,
        ...lex.questionPhrases,
        ...lex.commandPhrases,
        ...lex.transferVerbs,
        ...lex.accountWords.keys,
        ...lex.whoWords.keys,
        ...lex.intentCues.keys,
        ...lex.todayWords,
        ...lex.yesterdayWords,
        ...lex.weekdays.keys,
        ...lex.months.keys,
        ...lex.receiptTotalWords,
        ...lex.receiptTotalExclusions,
      ];
      for (final p in phrases) {
        expect(normalizeText(p), p, reason: p);
      }
    });

    test('every intent cue is a money intent', () {
      for (final wire in englishLexicon.intentCues.values) {
        expect(
          CaptureIntent.tryParse(wire)?.recordsMoney,
          isTrue,
          reason: wire,
        );
      }
    });

    test('every who word is a who value', () {
      expect(whoValues, containsAll(englishLexicon.whoWords.values.toSet()));
    });
  });
}
