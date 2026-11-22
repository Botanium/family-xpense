import 'package:test/test.dart';
import 'package:xpense_shared/xpense_shared.dart';

import 'fixtures.dart';

void main() {
  group('hints (AI_PIPELINE 5, step 6)', () {
    // (kind, span, id or who) per hint.
    final cases = <({String text, List<(String, String, String?)> hints})>[
      (text: 'paid with visa 30', hints: [('account', 'visa', 'acc_visa')]),
      (
        text: 'paid 30 from the card',
        hints: [('account', 'the card', 'acc_visa')],
      ),
      (text: 'cash 10000 for bread', hints: [('account', 'cash', 'acc_cash')]),
      (
        text: 'moved 200 to trip fund',
        hints: [('account', 'trip fund', 'acc_savings')],
      ),
      (
        text: 'transferred 100 to Rafidain bank',
        hints: [('account', 'rafidain bank', 'acc_bank')],
      ),
      (text: 'from the bank 5000', hints: [('account', 'bank', 'acc_bank')]),
      (text: 'gave Alex 300', hints: [('person', 'alex', 'p_alex')]),
      (text: 'lent sarah 5000', hints: [('person', 'sarah', 'p_sara')]),
      (text: 'borrowed 500 from dad', hints: [('person', 'dad', 'p_dad')]),
      (text: 'gave Omar 20000', hints: [('person', 'omar', null)]),
      (
        text: 'groceries 40000',
        hints: [('category', 'groceries', 'c_groceries')],
      ),
      (text: 'petrol 30000', hints: [('category', 'petrol', 'c_fuel')]),
      (text: 'city mall 40000 joint', hints: [('who', 'joint', 'joint')]),
      (text: 'my wife spent 30000', hints: [('who', 'my wife', 'partner')]),
      (
        text: 'lunch with Alex on visa',
        hints: [
          ('category', 'lunch', 'c_dining'),
          ('person', 'alex', 'p_alex'),
          ('account', 'visa', 'acc_visa'),
        ],
      ),
      (text: 'taxi 5000', hints: []),
    ];
    for (final c in cases) {
      test('"${c.text}"', () {
        final hints = parseText(c.text, iqdHome()).hints;
        expect([
          for (final h in hints) (h.kind.wire, h.span, h.id ?? h.who),
        ], c.hints);
      });
    }

    test('a generic word shared by two accounts stays unresolved', () {
      final hints = findHints(
        'paid cash',
        accounts: const [
          ParserAccount(id: 'a', name: 'Cash wallet', currency: Currency.iqd),
          ParserAccount(id: 'b', name: 'Dollar cash', currency: Currency.usd),
        ],
      );
      expect(hints.single.id, isNull);
      expect(hints.single.confidence, unresolvedHintConfidence);
    });

    test('a generic word picks the one account of its kind', () {
      final hints = findHints(
        'on the card',
        accounts: const [
          ParserAccount(
            id: 'v',
            name: 'Joint Visa',
            currency: Currency.usd,
            kind: 'credit',
          ),
          ParserAccount(id: 'c', name: 'Wallet', currency: Currency.iqd),
        ],
      );
      expect(hints.single.id, 'v');
      expect(hints.single.confidence, genericAccountConfidence);
    });

    test('a name shared by two people stays unresolved', () {
      final hints = findHints(
        'gave ali 5000',
        people: const [
          ParserPerson(id: 'p1', name: 'Ali'),
          ParserPerson(id: 'p2', name: 'Ali Hassan', aliases: ['ali']),
        ],
      );
      expect(hints.single.id, isNull);
    });

    test('digits inside an account name are not money', () {
      final result = parseText('paid 30 with Joint Visa ••4021', iqdHome());
      expect(result.amounts.map((a) => a.span), ['30']);
      expect(result.hints.single.id, 'acc_visa');
    });
  });

  group('learned rules (AI_PIPELINE 5, step 7)', () {
    final cases = <({String text, List<(String, String, String)> hits})>[
      (
        text: '42.80 at Costco',
        hits: [
          ('r_costco', 'categoryId', 'c_groceries'),
          ('r_costco', 'accountId', 'acc_visa'),
        ],
      ),
      (
        text: 'COSTCO 30',
        hits: [
          ('r_costco', 'categoryId', 'c_groceries'),
          ('r_costco', 'accountId', 'acc_visa'),
        ],
      ),
      (text: 'costcos 30', hits: []),
      (
        text: 'generator 25000',
        hits: [('r_generator', 'categoryId', 'c_generator')],
      ),
      (text: 'gave alex 300', hits: [('r_alex', 'accountId', 'acc_cash')]),
      (
        text: 'carrefour 18000',
        hits: [
          ('r_carrefour', 'categoryId', 'c_groceries'),
          ('r_carrefour', 'intent', 'expense'),
        ],
      ),
      (text: 'city mall 40000', hits: [('r_mall', 'who', 'joint')]),
      (text: 'mall 40000', hits: []),
      // Merchant beats keyword for the same field.
      (
        text: 'costco shop 30',
        hits: [
          ('r_costco', 'categoryId', 'c_groceries'),
          ('r_costco', 'accountId', 'acc_visa'),
        ],
      ),
      // Merchant account beats person account.
      (
        text: 'costco with alex 30',
        hits: [
          ('r_costco', 'categoryId', 'c_groceries'),
          ('r_costco', 'accountId', 'acc_visa'),
        ],
      ),
      (text: 'taxi 5000', hits: []),
    ];
    for (final c in cases) {
      test('"${c.text}"', () {
        final hits = parseText(c.text, iqdHome()).ruleHits;
        expect([
          for (final h in hits) (h.ruleId, h.field.wire, h.value),
        ], c.hits);
      });
    }

    test('the winner does not depend on rule order', () {
      const a = ParserRule(
        id: 'a',
        kind: RuleKind.keyword,
        pattern: 'tea',
        categoryId: 'c1',
      );
      const b = ParserRule(
        id: 'b',
        kind: RuleKind.keyword,
        pattern: 'green tea',
        categoryId: 'c2',
      );
      const c = ParserRule(
        id: 'c',
        kind: RuleKind.keyword,
        pattern: 'green tea',
        categoryId: 'c3',
      );
      for (final rules in [
        [a, b, c],
        [c, b, a],
        [b, a, c],
      ]) {
        final hits = applyRules('green tea 500', rules);
        expect(hits.single.ruleId, 'b');
      }
    });

    test('an empty pattern never matches', () {
      const rule = ParserRule(
        id: 'x',
        kind: RuleKind.keyword,
        pattern: '  ',
        categoryId: 'c',
      );
      expect(applyRules('anything', [rule]), isEmpty);
    });

    test('rule hits carry confidence 0.99 in the schema', () {
      final hit = parseText('costco 30', iqdHome()).toParseResult().ruleHits!;
      expect(hit.map((h) => h.confidence), [0.99, 0.99]);
    });
  });
}
