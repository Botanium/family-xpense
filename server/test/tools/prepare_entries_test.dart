import 'package:test/test.dart';
import 'package:xpense_agent/decide/classifier.dart';
import 'package:xpense_agent/tools/prepare_entries.dart';
import 'package:xpense_agent/tools/schemas.dart';
import 'package:xpense_shared/xpense_shared.dart';

import 'support.dart';

PrepareEntriesInput _input(List<ProposedEntry> entries) =>
    PrepareEntriesInput(entries: entries);

void main() {
  group('prepareEntries', () {
    test(
      'two entries in one message become two drafts with fresh ids',
      () async {
        const text = 'Salary came in 3200 and I paid rent 1400';
        final out = await prepareEntries(
          _input([
            ProposedEntry(
              intent: 'income',
              amount: '3200',
              text: 'Salary came in 3200',
              categoryHint: 'salary',
              title: 'Salary',
            ),
            ProposedEntry(
              intent: 'expense',
              amount: '1400',
              text: 'I paid rent 1400',
              categoryHint: 'rent',
              accountHint: 'checking',
              title: 'Rent',
            ),
          ]),
          dara,
          demoDeps(texts: [text]),
        );
        final [salary, rent] = out.drafts;
        expect(salary.id, 'd1');
        expect(salary.intent, 'income');
        expect(salary.amountMinor, 320000);
        expect(salary.currency, 'USD');
        expect(salary.categoryId, 'salary');
        expect(salary.occurredOn, '2026-11-22');
        expect(salary.origin, 'agent');
        // No account words and no classifier: the account is asked.
        expect(salary.accountId, isNull);
        expect(salary.missing, ['accountId']);
        // "dollars" was never said: the currency is a guess.
        expect(salary.guessed, contains('currency'));

        expect(rent.id, 'd2');
        expect(rent.amountMinor, 140000);
        expect(rent.accountId, 'acc_chk');
        // D-41 removed the `rent` category, so it is asked.
        expect(rent.categoryId, isNull);
        expect(rent.missing, ['categoryId']);

        expect(out.ask?.draftId, 'd1');
        expect(out.ask?.field, 'accountId');
        expect(out.ask?.options?.map((o) => o.value), ['acc_chk', 'acc_visa']);
      },
    );

    test('an amount the user never wrote is dropped and asked for', () async {
      final out = await prepareEntries(
        _input([
          ProposedEntry(
            intent: 'expense',
            amount: '45',
            text: 'groceries at Carrefour',
            categoryHint: 'groceries',
          ),
        ]),
        dara,
        demoDeps(texts: ['groceries at Carrefour']),
      );
      final draft = out.drafts.single;
      expect(draft.amountMinor, isNull);
      expect(draft.missing, containsAllInOrder(['amountMinor', 'currency']));
      expect(out.notes?.single, contains('not in the message'));
      // The slip asks for the amount itself; the question is the account.
      expect(out.ask?.field, 'accountId');
    });

    test(
      'amounts may come from an earlier user message of the session',
      () async {
        final out = await prepareEntries(
          _input([
            ProposedEntry(intent: 'expense', amount: '1500', text: 'rent'),
          ]),
          dara,
          demoDeps(texts: ['I paid rent', 'it was 1,500 dollars']),
        );
        expect(out.drafts.single.amountMinor, 150000);
        expect(
          out.drafts.single.guessed ?? const [],
          isNot(contains('currency')),
        );
      },
    );

    test('dinars are whole units and get the day rate', () async {
      final out = await prepareEntries(
        _input([
          ProposedEntry(
            intent: 'expense',
            amount: '25000',
            currency: 'IQD',
            text: 'taxi 25,000 dinars from my cash wallet',
            accountHint: 'cash wallet',
            categoryHint: 'taxi',
          ),
        ]),
        dara,
        demoDeps(texts: ['taxi 25,000 dinars from my cash wallet']),
      );
      final draft = out.drafts.single;
      expect(draft.amountMinor, 25000);
      expect(draft.currency, 'IQD');
      expect(draft.accountId, 'acc_cash_iqd');
      expect(draft.fx?.pair, 'USD/IQD');
      expect(draft.fx?.pairRate, '1520');
      // 25000 / 1520 = 16.447… USD → 1645 cents, half-even.
      expect(draft.fx?.baseAmountMinor, 1645);
    });

    test('two currencies and two accounts in one message', () async {
      // Regression from a live trace: with "cash wallet" named first, the
      // parser read "12.50" as 12,500 IQD and the lunch lost its amount.
      const text =
          'taxi 25,000 dinars from my cash wallet and lunch 12.50 on the '
          'joint visa';
      final out = await prepareEntries(
        PrepareEntriesInput(
          entries: [
            ProposedEntry(
              intent: 'expense',
              amount: '25000',
              currency: 'IQD',
              text: 'taxi 25,000 dinars from my cash wallet',
              accountHint: 'cash wallet',
            ),
            ProposedEntry(
              intent: 'expense',
              amount: '12.50',
              currency: 'USD',
              text: 'lunch 12.50 on the joint visa',
              accountHint: 'joint visa',
            ),
          ],
        ),
        dara,
        demoDeps(texts: [text]),
      );
      final [taxi, lunch] = out.drafts;
      expect(
        (taxi.amountMinor, taxi.currency, taxi.accountId),
        (25000, 'IQD', 'acc_cash_iqd'),
      );
      expect(
        (lunch.amountMinor, lunch.currency, lunch.accountId),
        (1250, 'USD', 'acc_visa'),
      );
      // Both currencies are settled by words or the named account.
      expect(taxi.guessed, isNull);
      expect(lunch.guessed, isNull);
    });

    test("the partner's private account is never matched", () async {
      final out = await prepareEntries(
        _input([
          ProposedEntry(
            intent: 'expense',
            amount: '20',
            text: 'paid 20 from Shilan savings',
            accountHint: 'Shilan savings',
          ),
        ]),
        dara,
        demoDeps(texts: ['paid 20 from Shilan savings']),
      );
      expect(out.drafts.single.accountId, isNull);
    });

    test('classifier answers follow the confidence policy', () async {
      final classifier = FakeEntryClassifier.always(
        DecideResponse(
          intent: ChoiceAnswer(
            choice: 'expense',
            probabilities: {'expense': 0.97, 'income': 0.03},
            confidence: 0.97,
          ),
          account: ChoiceAnswer(choice: 'acc_visa', confidence: 0.7),
          category: ChoiceAnswer(choice: 'groceries', confidence: 0.92),
          who: ChoiceAnswer(choice: 'joint', confidence: 0.4),
          isRecurring: YesNoAnswer(probability: 0.1),
        ),
      );
      final out = await prepareEntries(
        _input([
          ProposedEntry(
            intent: 'expense',
            amount: '45.20',
            text: 'Carrefour 45.20',
          ),
        ]),
        dara,
        demoDeps(texts: ['Carrefour 45.20'], classifier: classifier),
      );
      final d = out.drafts.single;
      expect(d.amountMinor, 4520);
      expect(d.categoryId, 'groceries'); // 0.92 ≥ conf_high: prefilled
      expect(d.accountId, 'acc_visa'); // 0.7: prefilled, Guessed
      expect(d.guessed, containsAll(['accountId', 'currency']));
      expect(d.guessed, isNot(contains('categoryId')));
      expect(d.who, isNull); // 0.4 < conf_low: not prefilled
      expect(d.confidence?.intent, 0.97);
      expect(d.missing, isNull);
      expect(out.ask, isNull);

      final call = classifier.calls.single;
      expect(call.text, 'Carrefour 45.20');
      expect(
        call.ask,
        containsAll([
          DecideQuestion.intent,
          DecideQuestion.account,
          DecideQuestion.category,
          DecideQuestion.who,
          DecideQuestion.isRecurring,
        ]),
      );
      expect(call.parsed?.amountMinor, 4520);
      expect(call.context, dara);
    });

    test('a doubtful intent is asked first', () async {
      final classifier = FakeEntryClassifier.always(
        DecideResponse(
          intent: ChoiceAnswer(
            choice: 'expense',
            probabilities: {'loan_given': 0.55, 'expense': 0.45},
            confidence: 0.55,
          ),
          person: ChoiceAnswer(choice: 'p_alex', confidence: 0.95),
          account: ChoiceAnswer(choice: 'acc_chk', confidence: 0.95),
        ),
      );
      final out = await prepareEntries(
        _input([
          ProposedEntry(
            intent: 'loan_given',
            amount: '300',
            text: 'Gave Alex 300',
            person: 'Alex',
          ),
        ]),
        dara,
        demoDeps(texts: ['Gave Alex 300'], classifier: classifier),
      );
      final d = out.drafts.single;
      expect(d.intent, 'loan_given');
      expect(d.personId, 'p_alex');
      expect(d.missing?.first, 'intent');
      expect(out.ask?.field, 'intent');
    });

    test('uncalibrated answers are capped', () async {
      final classifier = FakeEntryClassifier.always(
        DecideResponse(
          calibrated: false,
          category: ChoiceAnswer(choice: 'dining', confidence: 0.99),
        ),
      );
      final out = await prepareEntries(
        _input([
          ProposedEntry(intent: 'expense', amount: '12', text: 'lunch 12'),
        ]),
        dara,
        demoDeps(texts: ['lunch 12'], classifier: classifier),
      );
      expect(out.drafts.single.confidence?.category, 0.8);
      expect(out.drafts.single.guessed, contains('categoryId'));
    });

    test(
      'a same-day entry with the same amount is a duplicate candidate',
      () async {
        final classifier = FakeEntryClassifier.always(
          DecideResponse(duplicate: YesNoAnswer(probability: 0.9)),
        );
        // The demo household has 96.00 at Abu Afif on the 4th.
        final out = await prepareEntries(
          _input([
            ProposedEntry(
              intent: 'expense',
              amount: '96',
              text: 'lunch at Abu Afif 96 on the 4th',
              dateWords: 'on the 4th',
              accountHint: 'visa',
            ),
          ]),
          dara,
          demoDeps(
            texts: ['lunch at Abu Afif 96 on the 4th'],
            classifier: classifier,
          ),
        );
        final d = out.drafts.single;
        expect(d.occurredOn, '2026-11-04');
        expect(d.duplicate?.txnId, isNotNull);
        expect(d.duplicate?.probability, 0.9);
        expect(classifier.calls.single.ask, contains(DecideQuestion.duplicate));
        expect(classifier.calls.single.candidates.single.amountMinor, 9600);
      },
    );

    test(
      'missing fields from the model become questions, not errors',
      () async {
        // Regression from a live trace: an entry without `text` failed the
        // tool and so the whole turn.
        final out = await prepareEntries(
          PrepareEntriesInput.fromJson({
            'entries': [
              {'amount': '300', 'person': 'Alex'},
            ],
          }),
          dara,
          demoDeps(texts: ['Gave Alex 300 dollars']),
        );
        final d = out.drafts.single;
        expect(d.intent, 'expense');
        expect(d.amountMinor, 30000);
        expect(d.currency, 'USD');
        expect(
          (await prepareEntries(
            PrepareEntriesInput.fromJson({}),
            dara,
            demoDeps(),
          )).drafts,
          isEmpty,
        );
      },
    );

    test('is idempotent: the same input gives the same drafts', () async {
      final input = _input([
        ProposedEntry(intent: 'expense', amount: '12', text: 'coffee 12'),
      ]);
      final deps = demoDeps(texts: ['coffee 12']);
      final a = await prepareEntries(input, dara, deps);
      final b = await prepareEntries(input, dara, deps);
      expect(b.toJson(), a.toJson());
    });

    test('keeps at most 20 drafts', () async {
      final entries = [
        for (var i = 0; i < 25; i++)
          ProposedEntry(intent: 'expense', amount: '5', text: 'tea 5'),
      ];
      final out = await prepareEntries(
        _input(entries),
        dara,
        demoDeps(texts: ['tea 5']),
      );
      expect(out.drafts, hasLength(maxDraftsPerSurface));
      expect(out.notes, contains(contains('first 20')));
    });

    test(
      'every draft passes the phone checks except for what it lists',
      () async {
        final out = await prepareEntries(
          _input([
            ProposedEntry(
              intent: 'expense',
              amount: '45',
              text: 'groceries 45 from checking',
              accountHint: 'checking',
              categoryHint: 'groceries',
            ),
          ]),
          dara,
          demoDeps(texts: ['groceries 45 from checking']),
        );
        final check = checkDraft(
          out.drafts.single.toJson(),
          const HouseholdRefs(),
        );
        expect(check.isMalformed, isFalse);
        expect(check.missing, isEmpty);
      },
    );
  });

  test('parseWrittenAmount reads grouping and decimals only', () {
    expect(parseWrittenAmount('1,400').toString(), '1400');
    expect(parseWrittenAmount('12.50').toString(), '12.5');
    expect(parseWrittenAmount('3.2k'), isNull);
    expect(parseWrittenAmount(null), isNull);
  });
}
