import 'package:test/test.dart';
import 'package:xpense_shared/xpense_shared.dart';

List<OcrLine> lines(List<String> texts) => [for (final t in texts) OcrLine(t)];

typedef ReceiptCase = ({
  String name,
  List<OcrLine> lines,
  Currency? defaultCurrency,
  String? merchant,
  String? date,
  String? currency,
  int? total,
  bool keyword,
  List<(String, int)> items,
});

void main() {
  group('receipt parser (AI_PIPELINE 3)', () {
    final cases = <ReceiptCase>[
      (
        name: 'US warehouse receipt',
        lines: lines([
          'COSTCO WHOLESALE',
          '#1234 Main Street',
          'Tel: 555-1234',
          '22/11/2026 14:05',
          'KS WATER 24PK  4.99',
          'BANANAS 1.49',
          'MILK 2 x 1.50  3.00',
          'SUBTOTAL 9.48',
          'TAX 0.76',
          'TOTAL 10.24',
          'VISA 10.24',
          'CHANGE 0.00',
          'THANK YOU',
        ]),
        defaultCurrency: null,
        merchant: 'COSTCO WHOLESALE',
        date: '2026-11-22',
        currency: 'USD',
        total: 1024,
        keyword: true,
        items: [('KS WATER 24PK', 499), ('BANANAS', 149), ('MILK', 300)],
      ),
      (
        name: 'Baghdad supermarket in IQD',
        lines: lines([
          'Al-Mansour Supermarket',
          'Baghdad, Karrada',
          'Date: 2026-11-20',
          'Rice 5kg 12,000',
          'Chicken 9,500',
          'Tomatoes 2,250',
          'Total IQD 23,750',
          'Cash 25,000',
          'Change 1,250',
        ]),
        defaultCurrency: null,
        merchant: 'Al-Mansour Supermarket',
        date: '2026-11-20',
        currency: 'IQD',
        total: 23750,
        keyword: true,
        items: [('Rice 5kg', 12000), ('Chicken', 9500), ('Tomatoes', 2250)],
      ),
      (
        name: 'total on the next line, month-day date',
        lines: lines([
          'Fuel Station 7',
          'Grand Total',
          '45,000 IQD',
          '21-11-2026',
        ]),
        defaultCurrency: Currency.usd,
        merchant: 'Fuel Station 7',
        date: '2026-11-21',
        currency: 'IQD',
        total: 45000,
        keyword: true,
        items: [],
      ),
      (
        name: 'US date, balance due',
        lines: lines(['TARGET', '11/21/2026', 'SOAP 3.99', 'Balance due 3.99']),
        defaultCurrency: null,
        merchant: 'TARGET',
        date: '2026-11-21',
        currency: 'USD',
        total: 399,
        keyword: true,
        items: [('SOAP', 399)],
      ),
      (
        name: 'no total word uses the largest amount',
        lines: lines(['Bakery Ali', 'Samoon 10 1,000', 'Kahi 3,000']),
        defaultCurrency: Currency.iqd,
        merchant: 'Bakery Ali',
        date: null,
        currency: 'IQD',
        total: 3000,
        keyword: false,
        items: [('Samoon', 1000), ('Kahi', 3000)],
      ),
      (
        name: 'no currency and a small total stays unknown',
        lines: lines(['Bakery Ali', 'Samoon 10 1,000', 'Kahi 3,000']),
        defaultCurrency: null,
        merchant: 'Bakery Ali',
        date: null,
        currency: null,
        total: null,
        keyword: false,
        items: [],
      ),
      (
        name: 'magnitude check on the total',
        lines: lines(['Kebab Erbil', 'Kebab 12,000', 'Total 18,000']),
        defaultCurrency: null,
        merchant: 'Kebab Erbil',
        date: null,
        currency: 'IQD',
        total: 18000,
        keyword: true,
        items: [('Kebab', 12000)],
      ),
      (
        name: 'written month date',
        lines: lines([
          'Corner Shop',
          '22 Nov 2026',
          'Water 1.00',
          'Amount due 1.00',
        ]),
        defaultCurrency: null,
        merchant: 'Corner Shop',
        date: '2026-11-22',
        currency: 'USD',
        total: 100,
        keyword: true,
        items: [('Water', 100)],
      ),
      (
        name: 'largest of several total words wins',
        lines: lines([
          'Mall Cafe',
          'Total 10.00',
          'Service 1.00',
          'Grand total 11.00',
        ]),
        defaultCurrency: null,
        merchant: 'Mall Cafe',
        date: null,
        currency: 'USD',
        total: 1100,
        keyword: true,
        items: [],
      ),
      (
        name: 'empty receipt',
        lines: const [],
        defaultCurrency: null,
        merchant: null,
        date: null,
        currency: null,
        total: null,
        keyword: false,
        items: [],
      ),
      (
        name: 'unreadable receipt',
        lines: lines(['@@@', '---', '', '***']),
        defaultCurrency: null,
        merchant: null,
        date: null,
        currency: null,
        total: null,
        keyword: false,
        items: [],
      ),
    ];
    for (final c in cases) {
      test(c.name, () {
        final r = parseReceipt(c.lines, defaultCurrency: c.defaultCurrency);
        final e = r.extraction;
        expect(e.merchant, c.merchant, reason: 'merchant');
        expect(e.date, c.date, reason: 'date');
        expect(e.currency, c.currency, reason: 'currency');
        expect(e.totalMinor, c.total, reason: 'total');
        expect(r.totalFromKeyword, c.keyword, reason: 'keyword');
        expect([
          for (final l in e.lines ?? <ReceiptLine>[]) (l.text, l.amountMinor),
        ], c.items);
      });
    }

    test('boxes on the same band are merged into rows', () {
      final r = parseReceipt(const [
        OcrLine(
          'CAFE NERO',
          box: OcrBox(left: 10, top: 10, width: 200, height: 20),
        ),
        OcrLine('Latte', box: OcrBox(left: 10, top: 60, width: 80, height: 18)),
        OcrLine('4.50', box: OcrBox(left: 300, top: 62, width: 40, height: 18)),
        OcrLine(
          'Croissant',
          box: OcrBox(left: 10, top: 90, width: 90, height: 18),
        ),
        OcrLine('3.25', box: OcrBox(left: 300, top: 88, width: 40, height: 18)),
        OcrLine(
          'AMOUNT DUE',
          box: OcrBox(left: 10, top: 130, width: 120, height: 18),
        ),
        OcrLine(
          r'$7.75',
          box: OcrBox(left: 290, top: 131, width: 50, height: 18),
        ),
        OcrLine(
          'Nov 21, 2026',
          box: OcrBox(left: 10, top: 170, width: 120, height: 18),
        ),
      ]);
      expect(r.rows, [
        'CAFE NERO',
        'Latte 4.50',
        'Croissant 3.25',
        r'AMOUNT DUE $7.75',
        'Nov 21, 2026',
      ]);
      final e = r.extraction;
      expect(e.merchant, 'CAFE NERO');
      expect(e.date, '2026-11-21');
      expect(e.currency, 'USD');
      expect(e.totalMinor, 775);
      expect(e.lines!.map((l) => (l.text, l.amountMinor)), [
        ('Latte', 450),
        ('Croissant', 325),
      ]);
    });

    test('a long merchant line is cut to the title limit', () {
      final r = parseReceipt(lines(['A' * 120, 'Total 5.00']));
      expect(r.extraction.merchant!.length, maxMerchantLength);
    });

    test('the receipt extraction passes its own schema', () {
      final r = parseReceipt(lines(['Shop', 'Tea 1.00', 'Total 1.00']));
      expect(
        ReceiptExtraction.$schema.parse(r.extraction.toJson()).totalMinor,
        100,
      );
    });
  });
}
