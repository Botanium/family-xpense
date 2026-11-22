// Learned rules (DATA_MODEL 2.12, story S3.11): lessons, ids, the stored
// form, and the lesson a corrected guess teaches.
import 'package:flutter_test/flutter_test.dart';
import 'package:xpense_app/a2ui/xpense_surface_host.dart';
import 'package:xpense_app/data/rules_repository.dart';
import 'package:xpense_app/data/rules_repository_firestore.dart';
import 'package:xpense_app/features/ask/ask_actions.dart';
import 'package:xpense_shared/xpense_shared.dart';

void main() {
  group('MemoryRulesRepository', () {
    test('a lesson becomes a rule the parser applies', () async {
      final repo = MemoryRulesRepository();
      addTearDown(repo.dispose);
      final changes = <List<ParserRule>>[];
      repo.watch().listen(changes.add);
      await repo.learn(
        const RuleLesson(
          kind: RuleKind.merchant,
          pattern: 'Costco',
          categoryId: 'groceries',
          accountId: 'acc_chk',
        ),
      );
      await Future<void>.delayed(Duration.zero);
      expect(changes, hasLength(1));
      final rule = repo.current.single;
      expect(rule.id, 'merchant_costco');
      expect(rule.pattern, 'costco');
      expect(
        applyRules('paid 30 at costco', repo.current).map((r) => r.value),
        ['groceries', 'acc_chk'],
      );
    });

    test('learning the same pattern again updates one rule', () async {
      final repo = MemoryRulesRepository();
      addTearDown(repo.dispose);
      await repo.learn(
        const RuleLesson(
          kind: RuleKind.merchant,
          pattern: 'Costco',
          categoryId: 'groceries',
          accountId: 'acc_chk',
        ),
      );
      await repo.learn(
        const RuleLesson(
          kind: RuleKind.merchant,
          pattern: 'costco ',
          categoryId: 'household',
        ),
      );
      final rule = repo.current.single;
      expect(rule.categoryId, 'household');
      expect(rule.accountId, 'acc_chk', reason: 'kept from the first lesson');
      expect(repo.hits['merchant_costco'], 2);
    });

    test('an empty lesson or pattern teaches nothing', () async {
      final repo = MemoryRulesRepository();
      addTearDown(repo.dispose);
      await repo.learn(
        const RuleLesson(kind: RuleKind.keyword, pattern: 'lunch'),
      );
      await repo.learn(
        const RuleLesson(kind: RuleKind.keyword, pattern: '  ', who: 'me'),
      );
      expect(repo.current, isEmpty);
    });
  });

  test('rule ids are stable and Firestore-safe', () {
    expect(
      ruleIdFor(RuleKind.merchant, "Joe's Café #2"),
      'merchant_joe_s_caf_2',
    );
    expect(ruleIdFor(RuleKind.keyword, '!!!'), 'keyword_x');
    expect(ruleIdFor(RuleKind.keyword, 'a' * 300).length, 120);
  });

  group('stored form (DATA_MODEL 2.12)', () {
    test('who is stored relative to the household and read back', () {
      final sets = storedSets(
        const RuleLesson(
          kind: RuleKind.merchant,
          pattern: 'costco',
          categoryId: 'groceries',
          who: 'me',
          intent: 'expense',
        ),
        uid: 'u_dara',
      );
      expect(sets, {
        'categoryId': 'groceries',
        'type': 'expense',
        'whoScope': 'member',
        'whoUid': 'u_dara',
      });
      final data = {'kind': 'merchant', 'pattern': 'costco', 'sets': sets};
      expect(ruleFromDoc('r1', data, uid: 'u_dara')!.who, 'me');
      expect(ruleFromDoc('r1', data, uid: 'u_shilan')!.who, 'partner');
      expect(ruleFromDoc('r1', data, uid: 'u_dara')!.intent, 'expense');
    });

    test('joint is a scope; partner is not stored', () {
      expect(
        storedSets(
          const RuleLesson(
            kind: RuleKind.keyword,
            pattern: 'rent',
            who: 'joint',
          ),
          uid: 'u',
        ),
        {'whoScope': 'joint'},
      );
      expect(
        storedSets(
          const RuleLesson(
            kind: RuleKind.keyword,
            pattern: 'rent',
            who: 'partner',
          ),
          uid: 'u',
        ),
        isEmpty,
      );
    });

    test('a malformed document is skipped', () {
      expect(ruleFromDoc('r', {'kind': 'nope'}, uid: 'u'), isNull);
      expect(
        ruleFromDoc('r', {'kind': 'merchant', 'pattern': ''}, uid: 'u'),
        isNull,
      );
    });
  });

  group('the lesson of a corrected guess', () {
    final saved = EntryDraft(
      id: 'd1',
      intent: 'expense',
      amountMinor: 4280,
      currency: 'USD',
      accountId: 'acc_chk',
      categoryId: 'household',
      title: 'Costco',
    );

    test('a category correction keeps the account the member saved with', () {
      expect(
        lessonFor(
          const DraftCorrection(
            draftId: 'd1',
            field: 'categoryId',
            guessed: 'groceries',
            chosen: 'household',
            title: 'Costco',
          ),
          kind: RuleKind.merchant,
          saved: saved,
          txnId: 't1',
        ),
        const RuleLesson(
          kind: RuleKind.merchant,
          pattern: 'Costco',
          categoryId: 'household',
          accountId: 'acc_chk',
          fromTxnId: 't1',
        ),
      );
    });

    test('an account correction keeps the category', () {
      final lesson = lessonFor(
        const DraftCorrection(
          draftId: 'd1',
          field: 'accountId',
          guessed: 'acc_sav',
          chosen: 'acc_chk',
          title: 'Costco',
        ),
        kind: RuleKind.merchant,
        saved: saved,
      )!;
      expect(lesson.accountId, 'acc_chk');
      expect(lesson.categoryId, 'household');
    });

    test('no title, a cleared value or another field teaches nothing', () {
      expect(
        lessonFor(
          const DraftCorrection(
            draftId: 'd1',
            field: 'categoryId',
            guessed: 'a',
            chosen: 'b',
          ),
          kind: RuleKind.merchant,
        ),
        isNull,
      );
      expect(
        lessonFor(
          const DraftCorrection(
            draftId: 'd1',
            field: 'categoryId',
            guessed: 'a',
            chosen: null,
            title: 'x',
          ),
          kind: RuleKind.merchant,
        ),
        isNull,
      );
      expect(
        lessonFor(
          const DraftCorrection(
            draftId: 'd1',
            field: 'occurredOn',
            guessed: 'a',
            chosen: 'b',
            title: 'x',
          ),
          kind: RuleKind.merchant,
        ),
        isNull,
      );
    });
  });
}
