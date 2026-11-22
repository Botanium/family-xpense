import 'package:test/test.dart';
import 'package:xpense_shared/xpense_shared.dart';

import 'fixtures.dart';

void main() {
  group('findDate against Sunday 2026-11-22 (AI_PIPELINE 5, step 5)', () {
    final cases = <({String text, String? date})>[
      (text: 'lunch today', date: '2026-11-22'),
      (text: 'this morning taxi', date: '2026-11-22'),
      (text: 'tonight dinner', date: '2026-11-22'),
      (text: 'spent 25000 yesterday', date: '2026-11-21'),
      (text: 'last night pizza', date: '2026-11-21'),
      (text: 'the day before yesterday', date: '2026-11-20'),
      (text: 'day before yesterday fuel', date: '2026-11-20'),
      (text: 'friday groceries', date: '2026-11-20'),
      (text: 'on friday', date: '2026-11-20'),
      (text: 'on fri', date: '2026-11-20'),
      (text: 'last friday', date: '2026-11-20'),
      (text: 'sunday', date: '2026-11-22'),
      (text: 'last sunday', date: '2026-11-15'),
      (text: 'monday', date: '2026-11-16'),
      (text: 'last saturday', date: '2026-11-21'),
      (text: '3 days ago', date: '2026-11-19'),
      (text: 'two days ago', date: '2026-11-20'),
      (text: 'a week ago', date: '2026-11-15'),
      (text: '2 weeks ago', date: '2026-11-08'),
      (text: 'on 20/11 paid 30000', date: '2026-11-20'),
      (text: '25/11', date: '2025-11-25'),
      (text: '1/11/2026', date: '2026-11-01'),
      (text: '5/1/2026', date: '2026-01-05'),
      (text: '22-11-2026', date: '2026-11-22'),
      (text: '22.11.2026', date: '2026-11-22'),
      (text: '22-11-26', date: '2026-11-22'),
      (text: 'march 5th', date: '2026-03-05'),
      (text: '5 march', date: '2026-03-05'),
      (text: '5th of march 2025', date: '2025-03-05'),
      (text: 'march 5, 2026', date: '2026-03-05'),
      (text: 'dec 1 3000', date: '2025-12-01'),
      (text: 'the 5th', date: '2026-11-05'),
      (text: 'the 25th', date: '2026-10-25'),
      // Not dates.
      (text: '31/02', date: null),
      (text: '5-10', date: null),
      (text: 'sat with alex', date: null),
      (text: 'lunch 15000', date: null),
      (text: '', date: null),
    ];
    for (final c in cases) {
      test('"${c.text}" → ${c.date}', () {
        final found = findDate(tokenize(normalizeText(c.text)), fixtureToday);
        expect(found?.date.iso, c.date);
      });
    }

    test('parseText defaults to today and reports no mention', () {
      final result = parseText('lunch 15000', iqdHome());
      expect(result.date.iso, '2026-11-22');
      expect(result.dateMention, isNull);
      expect(result.toParseResult().date, '2026-11-22');
    });

    test('the clock is read, not the system time', () {
      final result = parseText('yesterday 5000', iqdHome());
      expect(result.date.iso, '2026-11-21');
    });

    test('a date number is never an amount', () {
      final result = parseText('rent 400 on 1/11/2026', iqdHome());
      expect(result.amounts.map((a) => a.span), ['400']);
    });
  });

  group('LocalDate', () {
    test('rejects impossible dates', () {
      expect(LocalDate.tryCreate(2026, 2, 29), isNull);
      expect(LocalDate.tryCreate(2028, 2, 29)?.iso, '2028-02-29');
      expect(LocalDate.tryCreate(2026, 13, 1), isNull);
      expect(LocalDate.tryCreate(1800, 1, 1), isNull);
    });

    test('moves across month and year ends', () {
      expect(LocalDate.tryCreate(2026, 1, 1)!.addDays(-1).iso, '2025-12-31');
      expect(fixtureToday.weekday, DateTime.sunday);
    });
  });
}
