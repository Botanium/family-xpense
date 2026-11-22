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
