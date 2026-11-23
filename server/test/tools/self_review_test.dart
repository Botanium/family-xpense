// Findings of the WP-32 self-review (code-review skill, high) over
// lib/tools and lib/safety; each test fails on the code before the fix.
import 'package:test/test.dart';
import 'package:xpense_agent/decide/classifier.dart';
import 'package:xpense_agent/runtime/demo_household.dart';
import 'package:xpense_agent/safety/draft_guard.dart';
import 'package:xpense_agent/tools/household_reader.dart';
import 'package:xpense_agent/tools/in_memory_reader.dart';
import 'package:xpense_agent/tools/ledger_tools.dart';
import 'package:xpense_agent/tools/prepare_entries.dart';
import 'package:xpense_agent/tools/schemas.dart';
import 'package:xpense_agent/tools/tool_deps.dart';
import 'package:xpense_agent/tools/turn_evidence.dart';
import 'package:xpense_shared/xpense_shared.dart';

import 'support.dart';

/// The demo household with its accounts replaced by [accounts].
InMemoryHouseholdReader withAccounts(List<Visible<HouseholdAccount>> accounts) {
  final h = demoHousehold('2026-11-22');
  return InMemoryHouseholdReader({
    demoHid: InMemoryHousehold(
      profile: h.profile,
      members: h.members,
      categories: h.categories,
      people: h.people,
      budgets: h.budgets,
      transactions: h.transactions,
      fxRates: h.fxRates,
      accounts: accounts,
    ),
  });
}

const List<String> both = [demoUid, demoPartnerUid];

/// The demo household with its people replaced by [people].
InMemoryHouseholdReader withPeople(List<({String id, String name})> people) {
  final h = demoHousehold('2026-11-22');
  return InMemoryHouseholdReader({
    demoHid: InMemoryHousehold(
      profile: h.profile,
      members: h.members,
      accounts: h.accounts,
      categories: h.categories,
      people: [
        for (final p in people)
          (item: HouseholdPerson(id: p.id, name: p.name), visibleTo: both),
      ],
    ),
  });
}

Future<PrepareEntriesOutput> prepare(
  ProposedEntry entry,
  String text, {
  EntryClassifier? classifier,
  InMemoryHouseholdReader? reader,
}) => prepareEntries(
  PrepareEntriesInput(entries: [entry]),
  dara,
  demoDeps(texts: [text], classifier: classifier, reader: reader),
);

void main() {
  group('hints the member did not write are guesses', () {
    test('an account hint not in the words', () async {
      // "Groceries 45" names no account; the model hinted "checking".
      final out = await prepare(
        ProposedEntry(
          intent: 'expense',
          amount: '45',
          text: 'Groceries 45',
          accountHint: 'checking',
        ),
        'Groceries 45',
      );
      final d = out.drafts.single;
      // Classifier unavailable: the hint stands in, marked Guessed.
      expect(d.accountId, 'acc_chk');
      expect(d.guessed, contains('accountId'));
      expect(d.confidence?.account, isNull);
    });

    test(
      'the classifier overrides an account the member did not name',
      () async {
        final out = await prepare(
          ProposedEntry(
            intent: 'expense',
            amount: '45',
            text: 'Groceries 45',
            accountHint: 'checking',
          ),
          'Groceries 45',
          classifier: FakeEntryClassifier.always(
            DecideResponse(
              account: ChoiceAnswer(choice: 'acc_visa', confidence: 0.92),
            ),
          ),
        );
        expect(out.drafts.single.accountId, 'acc_visa');
      },
    );

    test('an account the member named is settled', () async {
      final out = await prepare(
        ProposedEntry(
          intent: 'expense',
          amount: '45',
          text: 'groceries 45 from checking',
          accountHint: 'checking',
        ),
        'groceries 45 from checking',
      );
      expect(out.drafts.single.accountId, 'acc_chk');
      expect(out.drafts.single.confidence?.account, 1);
      expect(out.drafts.single.guessed, isNot(contains('accountId')));
    });

    test('who needs a cue in the words', () async {
      final none = await prepare(
        ProposedEntry(
          intent: 'income',
          amount: '3200',
          text: 'Salary 3200',
          who: 'me',
        ),
        'Salary 3200',
      );
      expect(none.drafts.single.who, isNull);
      final joint = await prepare(
        ProposedEntry(
          intent: 'expense',
          amount: '45',
          text: 'we paid 45 for groceries',
          who: 'joint',
        ),
        'we paid 45 for groceries',
      );
      expect(joint.drafts.single.who, 'joint');
      final partner = await prepare(
        ProposedEntry(
          intent: 'expense',
          amount: '20',
          text: 'Shilan bought fuel 20',
          who: 'partner',
        ),
        'Shilan bought fuel 20',
      );
      expect(partner.drafts.single.who, 'partner');
    });
  });

  group('fields derived from words the member did not write', () {
    test('currency from an unwritten account hint is a guess', () async {
      // PR #30 review: "Groceries 45" with an inferred cash-wallet hint was
      // settled as 45 IQD.
      final out = await prepare(
        ProposedEntry(
          intent: 'expense',
          amount: '45',
          text: 'Groceries 45',
          accountHint: 'cash wallet',
        ),
        'Groceries 45',
      );
      final d = out.drafts.single;
      expect(d.guessed, containsAll(['currency', 'accountId']));
      expect(d.confidence?.account, isNull);
    });

    test(
      'a guessed currency follows the account the classifier picks',
      () async {
        final out = await prepare(
          ProposedEntry(
            intent: 'expense',
            amount: '45',
            text: 'Groceries 45',
            accountHint: 'cash wallet',
          ),
          'Groceries 45',
          classifier: FakeEntryClassifier.always(
            DecideResponse(
              account: ChoiceAnswer(choice: 'acc_visa', confidence: 0.92),
            ),
          ),
        );
        final d = out.drafts.single;
        expect(d.accountId, 'acc_visa');
        expect(d.currency, 'USD');
        expect(d.amountMinor, 4500);
        expect(d.guessed, contains('currency'));
      },
    );

    test('a written currency is not moved by the classifier', () async {
      final out = await prepare(
        ProposedEntry(
          intent: 'expense',
          amount: '25000',
          text: 'taxi 25000 dinars',
        ),
        'taxi 25000 dinars',
        classifier: FakeEntryClassifier.always(
          DecideResponse(
            account: ChoiceAnswer(choice: 'acc_visa', confidence: 0.95),
          ),
        ),
      );
      final d = out.drafts.single;
      expect(d.currency, 'IQD');
      expect(d.amountMinor, 25000);
      expect(d.accountId, isNull);
    });

    test('date words the member did not write are ignored', () async {
      final out = await prepare(
        ProposedEntry(
          intent: 'expense',
          amount: '12',
          text: 'lunch 12',
          dateWords: 'yesterday',
        ),
        'lunch 12',
      );
      expect(out.drafts.single.occurredOn, '2026-11-22');
    });

    test("a paraphrased text does not count as the member's words", () async {
      // The member wrote "paid 45"; the model's "text" adds "from checking".
      final out = await prepare(
        ProposedEntry(
          intent: 'expense',
          amount: '45',
          text: 'paid 45 from checking',
          accountHint: 'checking',
        ),
        'paid 45',
      );
      final d = out.drafts.single;
      expect(d.confidence?.account, isNull);
      expect(d.guessed, contains('accountId'));
    });
  });

  group('account options and a guessed currency (PR #30 review)', () {
    // The classifier leans to the IQD cash wallet but below conf_low, so
    // the account is asked.
    final lean = FakeEntryClassifier.always(
      DecideResponse(
        account: ChoiceAnswer(
          choice: 'acc_cash_iqd',
          probabilities: {'acc_cash_iqd': 0.5, 'acc_chk': 0.3, 'acc_visa': 0.2},
          confidence: 0.5,
        ),
      ),
    );

    test('a guessed currency does not filter the choices', () async {
      // "groceries 45": the base currency (USD) is only a guess. The old
      // options dropped the IQD wallet the classifier ranked first.
      final out = await prepare(
        ProposedEntry(intent: 'expense', amount: '45', text: 'groceries 45'),
        'groceries 45',
        classifier: lean,
      );
      expect(out.ask?.field, 'accountId');
      expect(out.ask?.options?.first.value, 'acc_cash_iqd');
    });

    test('a written currency still does', () async {
      final out = await prepare(
        ProposedEntry(
          intent: 'expense',
          amount: '45',
          currency: 'USD',
          text: 'groceries 45 dollars',
        ),
        'groceries 45 dollars',
        classifier: lean,
      );
      expect(out.ask?.field, 'accountId');
      expect(
        out.ask?.options?.map((o) => o.value),
        isNot(contains('acc_cash_iqd')),
      );
    });
  });

  // PR #30 review: the duplicate search ran on the guessed USD 45; once
  // the currency follows the cash wallet, it is asked again for 45 IQD.
  test('duplicates are rechecked after a guessed currency follows the '
      'account', () async {
    final classifier = FakeEntryClassifier(
      respond: (call) => call.ask.contains(DecideQuestion.account)
          ? DecideResponse(
              account: ChoiceAnswer(choice: 'acc_cash_iqd', confidence: 0.95),
              duplicate: YesNoAnswer(probability: 0.95),
              duplicateOf: 't_usd_45',
            )
          : DecideResponse(
              duplicate: YesNoAnswer(probability: 0.95),
              duplicateOf: 't_iqd_45',
            ),
    );
    final out = await prepare(
      ProposedEntry(intent: 'expense', amount: '45', text: 'groceries 45'),
      'groceries 45',
      classifier: classifier,
    );
    final d = out.drafts.single;
    expect((d.amountMinor, d.currency), (45, 'IQD'));
    expect(d.duplicate?.txnId, 't_iqd_45');
    final recheck = classifier.calls.last;
    expect(recheck.ask, {DecideQuestion.duplicate});
    expect(
      (recheck.parsed?.amountMinor, recheck.parsed?.currency),
      (45, 'IQD'),
    );
  });

  // PR #30 review: the ChoicePrompt writes an option's value into the
  // draft as it is, so every option is an id the phone knows.
  group('follow-up options are ids (PR #30 review)', () {
    test('category options carry ids, not slugs', () async {
      // Category ids that are not their slugs.
      final h = demoHousehold('2026-11-22');
      final reader = InMemoryHouseholdReader({
        demoHid: InMemoryHousehold(
          profile: h.profile,
          members: h.members,
          accounts: h.accounts,
          people: h.people,
          categories: [
            for (final c in h.categories)
              HouseholdCategory(
                id: 'cat_${c.slug}',
                slug: c.slug,
                name: c.name,
                kind: c.kind,
                parentId: c.parentId == null ? null : 'cat_${c.parentId}',
              ),
          ],
        ),
      });
      final classifier = FakeEntryClassifier.always(
        DecideResponse(
          account: ChoiceAnswer(choice: 'acc_chk', confidence: 0.95),
          category: ChoiceAnswer(
            choice: 'groceries',
            probabilities: {'groceries': 0.4, 'electricity_generator': 0.3},
            confidence: 0.4,
          ),
        ),
      );
      final out = await prepare(
        ProposedEntry(intent: 'expense', amount: '20', text: 'spent 20'),
        'spent 20',
        classifier: classifier,
        reader: reader,
      );
      expect(out.ask?.field, 'categoryId');
      final options = out.ask!.options!;
      expect(options.take(2).map((o) => o.value), [
        'cat_groceries',
        'cat_electricity_generator',
      ]);
      expect(options.first.label, 'Groceries');
      final ids = {
        for (final c in reader.households[demoHid]!.categories) c.id,
      };
      expect(options.map((o) => o.value), everyElement(isIn(ids)));
    });

    test('a person question offers person ids', () async {
      final out = await prepare(
        ProposedEntry(intent: 'loan_given', amount: '50', text: 'lent 50'),
        'lent 50',
        classifier: FakeEntryClassifier.always(
          DecideResponse(
            intent: ChoiceAnswer(choice: 'loan_given', confidence: 0.99),
            account: ChoiceAnswer(choice: 'acc_chk', confidence: 0.95),
            who: ChoiceAnswer(choice: 'joint', confidence: 0.95),
          ),
        ),
        reader: withPeople([
          (id: 'p_alex', name: 'Alex'),
          (id: 'p_rawa', name: 'Rawa'),
        ]),
      );
      expect(out.ask?.field, 'personName');
      expect(out.ask?.options?.map((o) => (o.label, o.value)), [
        ('Alex', 'p_alex'),
        ('Rawa', 'p_rawa'),
      ]);
    });
  });

  group('written ISO dates (PR #30 review)', () {
    test('an ISO date in the date words or the text is kept', () async {
      final viaWords = await prepare(
        ProposedEntry(
          intent: 'expense',
          amount: '10',
          text: r'Groceries $10 on 2026-11-01',
          dateWords: '2026-11-01',
        ),
        r'Groceries $10 on 2026-11-01',
      );
      expect(viaWords.drafts.single.occurredOn, '2026-11-01');
      final viaText = await prepare(
        ProposedEntry(
          intent: 'expense',
          amount: '10',
          text: r'Groceries $10 on 2026-11-01',
        ),
        r'Groceries $10 on 2026-11-01',
      );
      expect(viaText.drafts.single.occurredOn, '2026-11-01');
    });

    test('written date words nothing can read leave the date asked', () async {
      final out = await prepare(
        ProposedEntry(
          intent: 'expense',
          amount: '10',
          text: 'cake 10 the day after the wedding',
          dateWords: 'the day after the wedding',
        ),
        'cake 10 the day after the wedding',
      );
      expect(out.drafts.single.occurredOn, isNull);
      expect(out.drafts.single.missing, contains('occurredOn'));
    });

    test('an impossible ISO date is not taken', () async {
      final out = await prepare(
        ProposedEntry(
          intent: 'expense',
          amount: '10',
          text: 'tea 10 on 2026-02-31',
          dateWords: '2026-02-31',
        ),
        'tea 10 on 2026-02-31',
      );
      expect(out.drafts.single.occurredOn, isNull);
    });
  });

  group('media evidence (PR #30 review)', () {
    test('recordShown reads transcripts and receipts, bound or literal', () {
      final e = TurnEvidence(mediaTurn: true)
        ..recordShown([
          {
            'metadata': {'mimeType': 'application/a2ui+json'},
            'data': {
              'messages': [
                {
                  'createSurface': {
                    'surfaceId': 's',
                    'components': [
                      {'id': 'a', 'component': 'Transcript', 'text': 'Tea 5'},
                      {
                        'id': 'b',
                        'component': 'Transcript',
                        'text': {'@path': '/heard'},
                      },
                      {
                        'id': 'c',
                        'component': 'ReceiptSummary',
                        'receipt': {'@path': '/receipt'},
                      },
                    ],
                    'dataModel': {
                      'heard': 'and bread 2',
                      'receipt': {
                        'currency': 'USD',
                        'totalMinor': 4520,
                        'lines': [
                          {'text': 'milk', 'amountMinor': 1220},
                        ],
                      },
                    },
                  },
                },
              ],
            },
          },
          {'text': 'not a surface 99'},
        ]);
      expect(e.shownTexts, [
        'Tea 5',
        'and bread 2',
        '45.20 dollars and 12.20 dollars',
      ]);
    });

    test('a shown figure backs an amount; others need confirming', () async {
      final evidence = TurnEvidence(mediaTurn: true)
        ..shownTexts.add('Paid the generator 50 dollars');
      Future<PrepareEntriesOutput> run(String amount) => prepareEntries(
        PrepareEntriesInput(
          entries: [
            ProposedEntry(intent: 'expense', amount: amount, currency: 'USD'),
          ],
        ),
        dara,
        ToolDeps(
          reader: demoReader('2026-11-22'),
          classifier: FakeEntryClassifier(),
          thresholds: () async => const {},
          turnText: () => const [],
          clock: fixedClock,
          evidence: () => evidence,
        ),
      );
      final shown = (await run('50')).drafts.single;
      expect(shown.amountMinor, 5000);
      expect(shown.missing ?? const [], isNot(contains('amountMinor')));
      final unshown = await run('70');
      expect(unshown.drafts.single.amountMinor, 7000);
      expect(unshown.drafts.single.guessed, contains('amountMinor'));
      expect(unshown.drafts.single.missing, contains('amountMinor'));
      expect(unshown.notes, contains(contains('confirm')));
    });

    test('a typed turn still drops amounts the member never wrote', () async {
      final out = await prepare(
        ProposedEntry(intent: 'expense', amount: '70', text: 'tea'),
        'tea',
      );
      expect(out.drafts.single.amountMinor, isNull);
    });
  });

  test("a transfer's destination confidence keeps its own key", () async {
    final out = await prepare(
      ProposedEntry(
        intent: 'transfer',
        amount: '100',
        currency: 'USD',
        text: 'moved 100 dollars from checking',
        accountHint: 'checking',
      ),
      'moved 100 dollars from checking',
      classifier: FakeEntryClassifier.always(
        DecideResponse(
          toAccount: ChoiceAnswer(choice: 'acc_visa', confidence: 0.6),
        ),
      ),
    );
    final d = out.drafts.single;
    expect(d.toAccountId, 'acc_visa');
    expect(d.confidence?.account, 1); // the source, named by the member
  });

  test('an unknown account currency asks instead of crashing', () async {
    final out = await prepare(
      ProposedEntry(
        intent: 'expense',
        amount: '12',
        text: 'coffee 12 from the euro card',
        accountHint: 'euro card',
      ),
      'coffee 12 from the euro card',
      reader: withAccounts(const [
        (
          item: HouseholdAccount(
            id: 'acc_eur',
            name: 'Euro card',
            currency: 'EUR',
            scope: 'joint',
          ),
          visibleTo: both,
        ),
      ]),
    );
    expect(out.drafts.single.amountMinor, isNull);
    expect(out.notes, contains(contains('unknown currency')));
  });

  test("the account question leads with the classifier's choice", () async {
    final accounts = [
      for (var i = 1; i <= 5; i++)
        (
          item: HouseholdAccount(
            id: 'a$i',
            name: 'Account $i',
            currency: 'USD',
            scope: 'joint',
            order: i,
          ),
          visibleTo: both,
        ),
    ];
    final out = await prepare(
      ProposedEntry(intent: 'expense', amount: '45', text: 'groceries 45'),
      'groceries 45',
      reader: withAccounts(accounts),
      classifier: FakeEntryClassifier.always(
        DecideResponse(
          account: ChoiceAnswer(
            choice: 'a4',
            probabilities: {'a4': 0.4, 'a5': 0.3, 'a1': 0.2, 'a2': 0.1},
            confidence: 0.4,
          ),
        ),
      ),
    );
    expect(out.ask?.field, 'accountId');
    expect(out.ask?.options?.map((o) => o.value), ['a4', 'a5', 'a1', 'a2']);
  });

  group('archived accounts', () {
    InMemoryHouseholdReader archivedWallet() {
      final h = demoHousehold('2026-11-22');
      return withAccounts([
        for (final a in h.accounts)
          if (a.item.id == 'acc_cash_iqd')
            (
              item: HouseholdAccount(
                id: a.item.id,
                name: a.item.name,
                currency: a.item.currency,
                scope: a.item.scope,
                ownerUid: a.item.ownerUid,
                archived: true,
              ),
              visibleTo: a.visibleTo,
            )
          else
            a,
      ]);
    }

    test('past entries keep their account label', () async {
      final deps = demoDeps(reader: archivedWallet());
      final r = await queryLedger(LedgerQuery(groupBy: 'account'), dara, deps);
      expect(
        r.rows.firstWhere((x) => x.key == 'acc_cash_iqd').label,
        'Cash wallet',
      );
      final found = await findEntries(
        FindEntriesQuery(text: 'bakery'),
        dara,
        deps,
      );
      expect(found.items.single.subtitle, contains('Cash wallet'));
    });

    test('balances and new entries leave it out', () async {
      final deps = demoDeps(reader: archivedWallet());
      final b = await getBalances(BalancesQuery(), dara, deps);
      expect(
        b.accounts.map((a) => a.accountId),
        isNot(contains('acc_cash_iqd')),
      );
      final out = await prepare(
        ProposedEntry(
          intent: 'expense',
          amount: '25000',
          currency: 'IQD',
          text: 'taxi 25000 dinars from my cash wallet',
          accountHint: 'cash wallet',
        ),
        'taxi 25000 dinars from my cash wallet',
        reader: archivedWallet(),
      );
      expect(out.drafts.single.accountId, isNull);
    });
  });

  group('queryLedger', () {
    test('unknown categories are reported, not totalled as 0', () async {
      final r = await queryLedger(
        LedgerQuery(categories: ['rent']),
        dara,
        demoDeps(),
      );
      expect(r.totalMinor, isNull);
      expect(r.unknownCategories, ['rent']);
      final mixed = await queryLedger(
        LedgerQuery(categories: ['groceries', 'nope']),
        dara,
        demoDeps(),
      );
      expect(mixed.totalMinor, 21270);
      expect(mixed.unknownCategories, ['nope']);
    });

    test('a shortened range says so', () async {
      final r = await queryLedger(
        LedgerQuery(from: '2020-01-01'),
        dara,
        demoDeps(),
      );
      expect(r.rangeShortened, isTrue);
      final normal = await queryLedger(LedgerQuery(), dara, demoDeps());
      expect(normal.rangeShortened, isNull);
    });

    test('entries with no who are not the partner', () async {
      final h = demoHousehold('2026-11-22');
      final reader = InMemoryHouseholdReader({
        demoHid: InMemoryHousehold(
          profile: h.profile,
          members: h.members,
          categories: h.categories,
          accounts: h.accounts,
          transactions: const [
            (
              item: LedgerTxn(
                id: 't',
                type: 'expense',
                amountMinor: 500,
                currency: 'USD',
                baseAmountMinor: 500,
                accountId: 'acc_chk',
                occurredOn: '2026-11-10',
                title: 'Imported',
              ),
              visibleTo: both,
            ),
          ],
        ),
      });
      final r = await queryLedger(
        LedgerQuery(groupBy: 'who'),
        dara,
        demoDeps(reader: reader),
      );
      expect(r.rows.single.key, 'unknown');
      expect(r.rows.single.label, 'Not set');
    });
  });

  test("a prepared draft may not carry another entry's amount", () {
    final facts = GuardFacts.fromMessages([
      {
        'role': 'user',
        'content': [
          {'text': 'Salary came in 3200 and groceries were 1400'},
        ],
      },
      {
        'role': 'tool',
        'content': [
          {
            'toolResponse': {
              'name': 'prepareEntries',
              'output': {
                'drafts': [
                  {
                    'id': 'd1',
                    'intent': 'income',
                    'amountMinor': 320000,
                    'currency': 'USD',
                  },
                  {
                    'id': 'd2',
                    'intent': 'expense',
                    'amountMinor': 140000,
                    'currency': 'USD',
                  },
                ],
              },
            },
          },
        ],
      },
    ]);
    // 3200 is in the message, but d2 is the 1400 entry.
    expect(
      facts.reject({
        'id': 'd2',
        'intent': 'expense',
        'amountMinor': 320000,
        'currency': 'USD',
      }),
      'unbacked_amount',
    );
    expect(
      facts.reject({
        'id': 'd2',
        'intent': 'expense',
        'amountMinor': 140000,
        'currency': 'USD',
      }),
      isNull,
    );
  });
}
