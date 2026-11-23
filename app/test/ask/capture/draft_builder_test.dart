// Drafts for paths L and D (ARCHITECTURE 5.1 and 5.2) and the confidence
// policy applied to them (story S3.10).
import 'package:clock/clock.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xpense_app/a2ui/testing/fake_xpense_actions.dart';
import 'package:xpense_app/features/ask/capture/confidence_policy.dart';
import 'package:xpense_app/features/ask/capture/draft_builder.dart';
import 'package:xpense_app/services/feature_flags.dart';
import 'package:xpense_shared/xpense_shared.dart';

final _clock = Clock.fixed(DateTime(2026, 11, 22, 13, 20));
const _policy = ConfidencePolicy(CaptureThresholds.defaults);

FastParse _parse(String text, {List<ParserRule> rules = const []}) => parseText(
  text,
  parseContextFor(sampleHousehold, clock: _clock, rules: rules),
);

EntryDraft _draft(
  String text, {
  List<ParserRule> rules = const [],
  DecideResponse? decide,
  EntryDraft? extracted,
}) => buildDraft(
  id: 'd1',
  raw: text,
  parse: _parse(text, rules: rules),
  household: sampleHousehold,
  policy: _policy,
  decide: decide,
  extracted: extracted,
);

const _costco = ParserRule(
  id: 'merchant_costco',
  kind: RuleKind.merchant,
  pattern: 'costco',
  categoryId: 'groceries',
  accountId: 'acc_chk',
);

void main() {
  group('titles', () {
    test('the words after "at" are a merchant', () {
      const text = 'Spent 42.80 at Costco Wholesale';
      expect(
        titleOf(text, _parse(text)),
        const DraftTitle('Costco Wholesale', RuleKind.merchant),
      );
    });

    test('otherwise the content words are a keyword', () {
      const text = 'spent 25 dollars on lunch';
      expect(
        titleOf(text, _parse(text)),
        const DraftTitle('lunch', RuleKind.keyword),
      );
    });

    test("a rule's own words are the title", () {
      const text = 'costco 30';
      expect(
        titleOf(text, _parse(text, rules: [_costco])),
        const DraftTitle('costco', RuleKind.merchant),
      );
    });

    test('nothing left is no title', () {
      const text = '25 dollars';
      expect(titleOf(text, _parse(text)), isNull);
    });
  });

  group('path L', () {
    test('a learned merchant settles category, account and intent, so the '
        'parse has nothing unresolved and the router keeps it local', () {
      final parse = _parse('Costco 42.80', rules: [_costco]);
      expect(parse.signals.unresolved, isEmpty);
      expect(
        routeCapture(
          RouteInput(
            mode: CapturePrivacyMode.smart,
            online: true,
            onDeviceModel: false,
            signals: parse.signals,
          ),
        ).path,
        CapturePath.local,
      );
      final d = _draft('Costco 42.80', rules: [_costco]);
      expect(d.intent, 'expense');
      expect(d.amountMinor, 4280);
      expect(d.currency, 'USD');
      expect(d.categoryId, 'groceries');
      expect(d.accountId, 'acc_chk');
      expect(d.occurredOn, '2026-11-22');
      expect(d.title, 'Costco');
      expect(d.origin, 'rule');
      expect(d.guessed, isNull);
      expect(d.missing, isNull);
      expect(d.confidence?.category, ruleHitConfidence);
    });

    test('a named account and category are taken from the words', () {
      final d = _draft('spent 12 on groceries from Checking');
      expect(d.categoryId, 'groceries');
      expect(d.accountId, 'acc_chk');
      expect(d.missing, isNull);
      expect(d.currency, 'USD');
      expect(
        d.guessed ?? const <String>[],
        isNot(contains('currency')),
        reason: 'the member named the account, so its currency is known',
      );
    });

    test('with nothing to go on, the slip asks in follow-up order', () {
      final d = _draft('42.80 at Costco');
      expect(d.intent, 'expense', reason: 'provisional, asked');
      expect(d.amountMinor, 4280);
      expect(d.currency, 'USD');
      expect(d.guessed, ['currency'], reason: 'the base currency, guessed');
      expect(d.missing, ['intent', 'accountId', 'categoryId']);
      expect(d.origin, 'parser');
    });

    test('IQD carries no quote: the save prices it for its date', () {
      final d = _draft('lunch 10000 dinars from cash');
      expect(d.currency, 'IQD');
      expect(d.accountId, 'acc_cash');
      // The latest rate (1705) is only the slip's preview.
      expect(d.fx, isNull);
    });

    test('a currency read from the magnitude alone is Guessed', () {
      final d = _draft('lunch 15000');
      expect(d.currency, 'IQD');
      expect(d.guessed, contains('currency'));
    });
  });

  group('path D', () {
    DecideResponse answers({
      double intent = 0.97,
      double category = 0.94,
      double account = 0.70,
      bool? calibrated,
      double? recurring,
    }) => DecideResponse(
      intent: ChoiceAnswer(
        choice: 'expense',
        confidence: intent,
        probabilities: {'expense': intent, 'income': 1 - intent},
      ),
      category: ChoiceAnswer(choice: 'groceries', confidence: category),
      account: ChoiceAnswer(choice: 'acc_chk', confidence: account),
      who: ChoiceAnswer(choice: 'unspecified', confidence: 0.9),
      isRecurring: recurring == null
          ? null
          : YesNoAnswer(probability: recurring),
      calibrated: calibrated,
    );

    test('high answers prefill; middle ones are Guessed', () {
      final d = _draft('42.80 at Costco', decide: answers());
      expect(d.intent, 'expense');
      expect(d.categoryId, 'groceries');
      expect(d.accountId, 'acc_chk');
      expect(d.currency, 'USD', reason: "the account's currency");
      // The account was not named, so the currency that followed it stays
      // Guessed, as in the agent's prepareEntries.
      expect(d.guessed, unorderedEquals(['accountId', 'currency']));
      expect(d.missing, isNull);
      expect(d.origin, 'decisions');
      expect(d.confidence?.intent, 0.97);
      expect(d.confidence?.category, 0.94);
      expect(d.confidence?.account, 0.70);
      expect(d.who, isNull, reason: 'the catch-all is not a value');
    });

    test('a low answer is not prefilled and is asked', () {
      final d = _draft('42.80 at Costco', decide: answers(category: 0.4));
      expect(d.categoryId, isNull);
      expect(d.missing, ['categoryId']);
    });

    test('an intent under conf_intent_min is asked first', () {
      final d = _draft('42.80 at Costco', decide: answers(intent: 0.8));
      expect(d.missing, ['intent']);
    });

    test('the uncalibrated fallback is capped and so always Guessed', () {
      final d = _draft(
        '42.80 at Costco',
        decide: answers(category: 0.99, account: 0.99, calibrated: false),
      );
      expect(d.confidence?.category, 0.80);
      expect(
        d.guessed,
        unorderedEquals(['accountId', 'categoryId', 'currency']),
      );
    });

    test('an account in another currency is not taken', () {
      final d = _draft(
        '42.80 dollars at Costco',
        decide: DecideResponse(
          account: ChoiceAnswer(choice: 'acc_cash', confidence: 0.99),
        ),
      );
      expect(d.accountId, isNull);
      expect(d.missing, contains('accountId'));
    });

    test('a likely recurring entry carries the offer', () {
      final d = _draft('Netflix 15.99', decide: answers(recurring: 0.9));
      expect(d.recurring?.probability, 0.9);
      expect(d.recurring?.unit, 'month');
    });

    test('rules beat Decisions', () {
      final d = _draft(
        'Costco 42.80',
        rules: [_costco],
        decide: DecideResponse(
          category: ChoiceAnswer(choice: 'dining', confidence: 0.99),
        ),
      );
      expect(d.categoryId, 'groceries');
    });
  });

  group("answers are checked as the agent's prepareEntries does", () {
    test('a Decisions category of the other kind is left to ask', () {
      final d = _draft(
        'spent 42.80 dollars at Costco',
        decide: DecideResponse(
          category: ChoiceAnswer(choice: 'salary', confidence: 0.95),
        ),
      );
      expect(d.intent, 'expense');
      expect(d.categoryId, isNull);
      expect(d.confidence?.category, isNull);
      expect(d.missing, contains('categoryId'));
    });

    test('an on-device category of the other kind is left to ask', () {
      final d = _draft(
        '42.80 at Costco',
        extracted: EntryDraft(
          id: 'x',
          intent: 'expense',
          categoryId: 'salary',
          confidence: DraftConfidence(category: 0.95),
        ),
      );
      expect(d.categoryId, isNull);
      expect(d.missing, contains('categoryId'));
    });

    test('a named category of the other kind is not taken', () {
      final d = _draft('spent 20 dollars on salary');
      expect(d.intent, 'expense');
      expect(d.categoryId, isNull);
    });

    test('a guessed currency follows the account Decisions picks; the '
        'duplicate answer about the old figures is dropped', () {
      final d = _draft(
        'lunch 15000',
        decide: DecideResponse(
          account: ChoiceAnswer(choice: 'acc_chk', confidence: 0.95),
          duplicate: YesNoAnswer(probability: 0.95),
          duplicateOf: 'txn_iqd',
        ),
      );
      expect(d.accountId, 'acc_chk');
      expect(d.currency, 'USD');
      expect(d.amountMinor, 1500000);
      expect(d.guessed, contains('currency'));
      expect(d.duplicate, isNull);
    });

    test('a guessed currency follows the account a rule picks', () {
      // 15000 alone reads as IQD; the rule says Costco is Checking (USD).
      final d = _draft('Costco 15000', rules: [_costco]);
      expect(d.accountId, 'acc_chk');
      expect(d.currency, 'USD');
      expect(d.amountMinor, 1500000);
      expect(d.guessed, contains('currency'));
      expect(d.fx, isNull, reason: 'USD is the base currency');
    });

    test('a question Decisions is unsure of is a provisional expense, '
        'Guessed and asked', () {
      final decide = DecideResponse(
        intent: ChoiceAnswer(
          choice: 'question',
          confidence: 0.6,
          probabilities: {'question': 0.6},
        ),
      );
      const text = '42.80 dollars at Costco';
      expect(nonEntryIntent(_parse(text), decide, _policy), isNull);
      final d = _draft(text, decide: decide);
      expect(d.intent, 'expense');
      expect(d.guessed, contains('intent'));
      expect(d.missing, contains('intent'));
    });

    test('a question Decisions is sure of is not an entry', () {
      const text = '42.80 dollars at Costco';
      final decide = DecideResponse(
        intent: ChoiceAnswer(
          choice: 'question',
          confidence: 0.96,
          probabilities: {'question': 0.96},
        ),
      );
      expect(
        nonEntryIntent(_parse(text), decide, _policy),
        CaptureIntent.question,
      );
    });

    test('an on-device "other" never becomes the slip\'s intent', () {
      final d = _draft(
        '42.80 at Costco',
        extracted: EntryDraft(id: 'x', intent: 'other'),
      );
      expect(d.intent, 'expense');
      expect(d.missing, contains('intent'));
    });

    test('a transfer never goes to the account it leaves from', () {
      final d = _draft(
        'moved 200 dollars from checking',
        decide: DecideResponse(
          intent: ChoiceAnswer(
            choice: 'transfer',
            confidence: 0.97,
            probabilities: {'transfer': 0.97},
          ),
          toAccount: ChoiceAnswer(choice: 'acc_chk', confidence: 0.95),
        ),
      );
      expect(d.accountId, 'acc_chk');
      expect(d.toAccountId, isNull);
    });
  });

  group('the request to /decide', () {
    test('asks only what the parse left open', () {
      const text = 'spent 42.80 dollars at Costco';
      final r = decideRequestFor(text, _parse(text));
      expect(r.ask, [
        'account',
        'category',
        'who',
        'is_recurring',
        'duplicate',
      ]);
      expect(r.parsed?.amountMinor, 4280);
      expect(r.parsed?.currency, 'USD');
      expect(r.parsed?.date, '2026-11-22');
      expect(r.lang, 'en');
    });

    test('asks duplicate only when the amount and currency are known', () {
      const known = 'spent 42.80 dollars at Costco';
      expect(decideRequestFor(known, _parse(known)).ask, contains('duplicate'));
      const bare = '42.80 at Costco';
      final r = decideRequestFor(bare, _parse(bare));
      expect(r.parsed?.currency, isNull);
      expect(r.ask, isNot(contains('duplicate')));
    });

    test('asks person only when a person is named', () {
      const text = 'gave Alex 300 dollars';
      expect(decideRequestFor(text, _parse(text)).ask, contains('person'));
    });
  });

  test('an on-device extraction is capped and Guessed', () {
    final d = _draft(
      '42.80 at Costco',
      extracted: EntryDraft(
        id: 'x',
        intent: 'expense',
        categoryId: 'groceries',
        confidence: DraftConfidence(category: 0.95),
      ),
    );
    expect(d.categoryId, 'groceries');
    expect(d.confidence?.category, 0.80);
    expect(d.guessed, contains('categoryId'));
    expect(d.origin, 'on_device');
  });
}
