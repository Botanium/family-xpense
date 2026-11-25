// The owner's first phone test (2026-11-24): a one-member household with
// only USD accounts typed "10000 iqd dinner" and every slip asked "Which
// account?" with no answers. An account pays in either currency now (the
// save converts at the day's rate); one account is used without asking;
// none is said.
import 'package:test/test.dart';
import 'package:xpense_agent/runtime/demo_household.dart';
import 'package:xpense_agent/tools/household_reader.dart';
import 'package:xpense_agent/tools/in_memory_reader.dart';
import 'package:xpense_agent/tools/prepare_entries.dart';
import 'package:xpense_agent/tools/schemas.dart';

import 'support.dart';

const List<String> _owner = [demoUid];

Visible<HouseholdAccount> _usd(String id, String name, {int order = 0}) => (
  item: HouseholdAccount(
    id: id,
    name: name,
    currency: 'USD',
    scope: 'personal',
    ownerUid: demoUid,
    order: order,
  ),
  visibleTo: _owner,
);

/// A household of one member (no partner yet) with [accounts].
InMemoryHouseholdReader _soloReader(List<Visible<HouseholdAccount>> accounts) {
  final demo = demoHousehold('2026-11-22');
  return InMemoryHouseholdReader({
    demoHid: InMemoryHousehold(
      profile: const HouseholdProfile(
        hid: demoHid,
        baseCurrency: 'USD',
        memberIds: _owner,
      ),
      members: const [
        HouseholdMember(uid: demoUid, displayName: 'Dara', role: 'owner'),
      ],
      accounts: accounts,
      categories: demo.categories,
      fxRates: demo.fxRates,
    ),
  });
}

Future<PrepareEntriesOutput> _dinner(
  List<Visible<HouseholdAccount>> accounts,
) => prepareEntries(
  PrepareEntriesInput(
    entries: [
      ProposedEntry(
        intent: 'expense',
        amount: '10000',
        currency: 'IQD',
        text: '10000 iqd dinner',
        categoryHint: 'dining_out',
        title: 'Dinner',
      ),
    ],
  ),
  dara,
  demoDeps(texts: ['10000 iqd dinner'], reader: _soloReader(accounts)),
);

void main() {
  group('a one-member household', () {
    test('with only accounts in the other currency, offers them all', () async {
      final out = await _dinner([
        _usd('a_cash', 'Cash'),
        _usd('a_bank', 'Bank account', order: 1),
        _usd('a_savings', 'Savings', order: 2),
      ]);
      final d = out.drafts.single;
      // The member's dinars stay as written; the save converts them.
      expect((d.amountMinor, d.currency), (10000, 'IQD'));
      expect(d.accountId, isNull);
      expect(out.ask?.field, 'accountId');
      expect(out.ask?.options?.map((o) => o.value), [
        'a_cash',
        'a_bank',
        'a_savings',
      ]);
      // Nobody else to ask about.
      expect(d.who, 'me');
      expect(d.missing ?? const [], isNot(contains('who')));
    });

    test('with several accounts in both currencies, offers them all', () async {
      final out = await _dinner([
        _usd('a_bank', 'Bank account'),
        (
          item: const HouseholdAccount(
            id: 'a_wallet',
            name: 'Wallet',
            currency: 'IQD',
            scope: 'personal',
            ownerUid: demoUid,
            order: 1,
          ),
          visibleTo: _owner,
        ),
      ]);
      expect(out.ask?.options?.map((o) => o.value), ['a_bank', 'a_wallet']);
    });

    test('with one account, uses it and says so', () async {
      final out = await _dinner([_usd('a_cash', 'Cash')]);
      final d = out.drafts.single;
      expect(d.accountId, 'a_cash');
      expect(d.confidence?.account, 1);
      expect((d.amountMinor, d.currency), (10000, 'IQD'));
      expect(d.missing ?? const [], isNot(contains('accountId')));
      expect(out.ask, isNull);
      expect(
        out.notes,
        contains(allOf(contains('only account'), contains('converted'))),
      );
    });

    test('with no accounts, says one is needed', () async {
      final out = await _dinner(const []);
      final d = out.drafts.single;
      expect(d.accountId, isNull);
      expect(d.missing, contains('accountId'));
      // No answers to offer: the slip offers to add an account.
      expect(out.ask?.field, 'accountId');
      expect(out.ask?.options, isNull);
      expect(out.notes, contains(contains('no accounts yet')));
    });
  });

  test('a partner in the household leaves who to the words', () async {
    final out = await prepareEntries(
      PrepareEntriesInput(
        entries: [
          ProposedEntry(intent: 'expense', amount: '12', text: 'lunch 12'),
        ],
      ),
      dara,
      demoDeps(texts: ['lunch 12']),
    );
    expect(out.drafts.single.who, isNull);
  });
}
