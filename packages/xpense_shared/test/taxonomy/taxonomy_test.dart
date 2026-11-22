import 'package:test/test.dart';
import 'package:xpense_shared/xpense_shared.dart';

void main() {
  group('CaptureIntent taxonomy (AI_PIPELINE 4)', () {
    // The table in AI_PIPELINE 4: intent → ledger type written.
    const expected = <String, String?>{
      'expense': 'expense',
      'income': 'income',
      'transfer': 'transfer',
      'savings_move': 'transfer',
      'loan_given': 'loan_given',
      'loan_taken': 'loan_taken',
      'repayment_received': 'repayment_received',
      'repayment_made': 'repayment_made',
      'adjustment': 'adjustment',
      'question': null,
      'command': null,
      'other': null,
    };

    for (final entry in expected.entries) {
      test('${entry.key} writes ${entry.value ?? 'nothing'}', () {
        final intent = CaptureIntent.tryParse(entry.key);
        expect(intent, isNotNull);
        expect(intent!.wire, entry.key);
        expect(intent.ledgerType?.wire, entry.value);
        expect(intent.recordsMoney, entry.value != null);
      });
    }

    test('enum order and const lists match the table', () {
      expect(CaptureIntent.values.map((i) => i.wire), expected.keys);
      expect(intentWireValues, expected.keys);
      expect(entryIntentWireValues, [
        for (final i in CaptureIntent.values)
          if (i.recordsMoney) i.wire,
      ]);
    });

    test('ledger types match transactions.type (DATA_MODEL 2.5)', () {
      expect(LedgerType.values.map((t) => t.wire), [
        'expense',
        'income',
        'transfer',
        'loan_given',
        'loan_taken',
        'repayment_received',
        'repayment_made',
        'adjustment',
      ]);
      for (final type in LedgerType.values) {
        expect(LedgerType.tryParse(type.wire), type);
      }
    });

    for (final bad in ['Expense', 'savingsMove', '', 'spend']) {
      test('unknown intent "$bad" parses to null', () {
        expect(CaptureIntent.tryParse(bad), isNull);
        expect(LedgerType.tryParse(bad), isNull);
      });
    }
  });

  group('Default category tree (AI_PIPELINE 4)', () {
    // The tables in AI_PIPELINE 4, group → sub-categories, in order.
    const expenseTree = <String, List<String>>{
      'food': ['groceries', 'dining', 'bakery_tea'],
      'home': [
        'electricity_generator',
        'water',
        'apartment_gas',
        'internet_fee',
        'phone_mobile_credit',
        'household_goods',
        'repairs',
      ],
      'transport': ['fuel', 'taxi', 'car_maintenance', 'public_transport'],
      'family': ['kids_school', 'clothing', 'health', 'personal_care'],
      'social': ['gifts', 'family_support', 'charity', 'occasions'],
      'leisure': ['entertainment', 'travel', 'online_subscriptions'],
      'finance': ['fees', 'interest', 'taxes'],
      'other_expense': [],
    };
    const incomeTree = <String, List<String>>{
      'earned': ['salary', 'freelance', 'business'],
      'received': ['gift_received', 'refund', 'sale', 'rental_income'],
      'other_income': [],
    };

    for (final (kind, tree) in [
      (CategoryKind.expense, expenseTree),
      (CategoryKind.income, incomeTree),
    ]) {
      test('${kind.wire} groups and children match the doc', () {
        expect(defaultGroups(kind).map((c) => c.slug), tree.keys);
        for (final entry in tree.entries) {
          final children = defaultChildren(entry.key);
          expect(children.map((c) => c.slug), entry.value, reason: entry.key);
          for (final child in children) {
            expect(child.kind, kind, reason: child.slug);
          }
        }
      });
    }

    test('the tree has no other entries', () {
      final documented = {
        for (final tree in [expenseTree, incomeTree])
          for (final entry in tree.entries) ...[entry.key, ...entry.value],
      };
      expect(defaultCategories.map((c) => c.slug).toSet(), documented);
      expect(defaultCategories, hasLength(documented.length));
    });

    test('slugs are unique, stable-looking keys', () {
      final slugs = defaultCategories.map((c) => c.slug).toList();
      expect(slugs.toSet(), hasLength(slugs.length));
      for (final slug in slugs) {
        expect(slug, matches(RegExp(r'^[a-z][a-z_]*$')));
      }
    });

    test('every parent is a group of the same kind, one level deep', () {
      for (final category in defaultCategories) {
        final parentSlug = category.parentSlug;
        if (parentSlug == null) continue;
        final parent = defaultCategory(parentSlug);
        expect(parent, isNotNull, reason: category.slug);
        expect(parent!.isGroup, isTrue, reason: category.slug);
        expect(parent.kind, category.kind, reason: category.slug);
      }
    });

    test('children follow their group in seed order', () {
      String? currentGroup;
      for (final category in defaultCategories) {
        if (category.isGroup) {
          currentGroup = category.slug;
        } else {
          expect(category.parentSlug, currentGroup, reason: category.slug);
        }
      }
    });

    test('names are keyed by language and English is always present', () {
      for (final category in defaultCategories) {
        expect(category.names.keys, contains(fallbackLanguage));
        expect(category.names['en'], isNotEmpty);
        // Other languages fall back to English until they are added (D-36).
        expect(category.nameIn('ar'), category.names['en']);
        expect(category.nameIn('ckb'), category.names['en']);
      }
      expect(defaultCategory('groceries')!.nameIn('en'), 'Groceries');
    });

    test('catch-all slugs exist as childless groups', () {
      for (final slug in [otherExpenseSlug, otherIncomeSlug]) {
        expect(defaultCategory(slug)!.isGroup, isTrue);
        expect(defaultChildren(slug), isEmpty);
      }
      expect(defaultCategory('nope'), isNull);
    });
  });
}
