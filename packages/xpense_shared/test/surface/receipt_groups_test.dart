import 'package:test/test.dart';
import 'package:xpense_shared/xpense_shared.dart';

const _receipt = SurfaceReceipt(
  merchant: 'Family Mart',
  occurredOn: '2026-11-22',
  currency: 'IQD',
  totalMinor: 60500,
  lines: [
    SurfaceReceiptLine(
      text: 'Rice',
      amountMinor: 18000,
      categoryId: 'groceries',
    ),
    SurfaceReceiptLine(
      text: 'Soap',
      amountMinor: 4000,
      categoryId: 'household',
    ),
    SurfaceReceiptLine(
      text: 'Chicken',
      amountMinor: 14500,
      categoryId: 'groceries',
    ),
    SurfaceReceiptLine(text: 'Card', amountMinor: 19000, categoryId: 'gifts'),
  ],
);

int _sum(Iterable<ReceiptGroup> groups) =>
    groups.fold(0, (s, g) => s + g.amountMinor);

void main() {
  test('unsplit: one group with the total and the main category', () {
    expect(groupReceipt(_receipt, split: false), [
      const ReceiptGroup(
        categoryId: 'groceries',
        lineCount: 4,
        amountMinor: 60500,
      ),
    ]);
  });

  test('split: groups in order of first line, summing to the total', () {
    final groups = groupReceipt(_receipt, split: true);
    expect(groups.map((g) => g.categoryId), [
      'groceries',
      'household',
      'gifts',
    ]);
    expect(groups.map((g) => g.lineCount), [2, 1, 1]);
    expect(_sum(groups), 60500);
  });

  test('groups sum to the total for awkward totals', () {
    for (final total in [1, 7, 99999, 60499, 1000000000001]) {
      final receipt = SurfaceReceipt(
        merchant: 'M',
        occurredOn: '2026-11-22',
        currency: 'USD',
        totalMinor: total,
        lines: _receipt.lines,
      );
      expect(_sum(groupReceipt(receipt, split: true)), total, reason: '$total');
    }
  });

  test('lines without a category form their own group', () {
    const receipt = SurfaceReceipt(
      merchant: 'M',
      occurredOn: '2026-11-22',
      currency: 'USD',
      totalMinor: 300,
      lines: [
        SurfaceReceiptLine(text: 'a', amountMinor: 100),
        SurfaceReceiptLine(text: 'b', amountMinor: 200, categoryId: 'dining'),
      ],
    );
    final groups = groupReceipt(receipt, split: true);
    expect(groups.first.categoryId, isNull);
    expect(_sum(groups), 300);
  });

  test('draftsForGroups copies the first draft per group', () {
    final drafts = draftsForGroups([
      {
        'id': 'r_1',
        'intent': 'expense',
        'currency': 'IQD',
        'accountId': 'acc_cash',
        'missing': ['categoryId'],
      },
    ], groupReceipt(_receipt, split: true));
    expect(drafts.map((d) => d['id']), ['r_1', 'r_2', 'r_3']);
    expect(drafts.map((d) => d['categoryId']), [
      'groceries',
      'household',
      'gifts',
    ]);
    expect(drafts.every((d) => !d.containsKey('missing')), isTrue);
    expect(drafts.every((d) => d['accountId'] == 'acc_cash'), isTrue);
    final one = draftsForGroups(drafts, groupReceipt(_receipt, split: false));
    expect(one.single['id'], 'r');
    expect(one.single['amountMinor'], 60500);
  });

  test('regrouping divides the converted total, never copies it', () {
    // 60,500 IQD at 1705 ≈ 35.48 USD.
    final unsplit = [
      {
        'id': 'r',
        'intent': 'expense',
        'currency': 'IQD',
        'amountMinor': 60500,
        'fx': {
          'pair': 'USD/IQD',
          'pairRate': '1705',
          'source': 'market',
          'baseAmountMinor': 3548,
        },
      },
    ];
    final split = draftsForGroups(unsplit, groupReceipt(_receipt, split: true));
    final converted = [
      for (final d in split) ((d['fx']! as Map)['baseAmountMinor']! as int),
    ];
    // In proportion to 35,428 / 4,360 / 20,712 IQD, and exact in total.
    expect(converted, [2078, 256, 1214]);
    expect(convertedTotal(split), 3548);
    expect(
      split.map((d) => (d['fx']! as Map)['pairRate']),
      everyElement('1705'),
    );

    final merged = draftsForGroups(split, groupReceipt(_receipt, split: false));
    expect((merged.single['fx']! as Map)['baseAmountMinor'], 3548);
  });

  test('without a converted amount on every draft, copies carry none', () {
    final drafts = draftsForGroups([
      {
        'id': 'r',
        'intent': 'expense',
        'fx': {'pair': 'USD/IQD', 'pairRate': '1705'},
      },
    ], groupReceipt(_receipt, split: true));
    for (final d in drafts) {
      expect(d['fx'], {'pair': 'USD/IQD', 'pairRate': '1705'});
    }
    expect(convertedTotal(drafts), isNull);
    expect(convertedTotal(const []), isNull);
  });

  test('receiptFromJson reads the data model and rejects bad shapes', () {
    expect(receiptFromJson(_receipt.toJson())!.lines, hasLength(4));
    expect(receiptFromJson(null), isNull);
    expect(receiptFromJson({..._receipt.toJson(), 'totalMinor': 'x'}), isNull);
    expect(
      receiptFromJson({
        ..._receipt.toJson(),
        'lines': [
          {'text': 'a', 'amountMinor': 1.5},
        ],
      }),
      isNull,
    );
  });
}
