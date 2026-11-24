// The fake accounts repository over the memory write path behaves as the
// Firestore one does over one household (cleanups, item 3): every save,
// edit, delete and restore moves the balances it shows, an opening balance
// is an adjustment entry, and its entry lists are what the Firestore
// adapter's mapper (`entryFromFirestore`) reads from the same documents.

import 'package:clock/clock.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xpense_app/bootstrap.dart';
import 'package:xpense_app/data/accounts_repository.dart';
import 'package:xpense_app/data/accounts_repository_fake.dart';
import 'package:xpense_app/data/accounts_repository_firebase.dart';
import 'package:xpense_app/data/write/ledger_transactions_repository.dart';
import 'package:xpense_app/data/write/memory_ledger_store.dart';
import 'package:xpense_shared/xpense_shared.dart';

const String viewer = FakeAccountsRepository.sampleViewer;
final DateTime now = DateTime(2026, 11, 23, 10, 30);

EntryDraft expense({int amount = 1250, String account = 'acc-checking'}) =>
    EntryDraft(
      id: 'd1',
      intent: 'expense',
      amountMinor: amount,
      currency: 'USD',
      accountId: account,
      categoryId: 'groceries',
      occurredOn: '2026-11-23',
      title: 'Costco',
    );

/// Every account's balance as the fake shows it.
Future<Map<String, int>> balances(FakeAccountsRepository accounts) async => {
  for (final a in await accounts.watchAccounts().first) a.id: a.balanceMinor,
};

/// What the Firestore adapter would list for [accountId] from the same
/// stored documents: live, visible to the viewer, leaving or reaching the
/// account, newest first.
List<AccountEntry> firestoreEntries(
  MemoryLedgerStore store,
  String accountId,
  Currency currency,
) => [
  for (final MapEntry(key: id, value: data) in store.transactions.entries)
    if (data['deletedAt'] == null &&
        (data['visibleTo']! as List).contains(viewer) &&
        (data['accountId'] == accountId || data['toAccountId'] == accountId))
      ?entryFromFirestore(
        id,
        {
          ...data,
          'occurredAt': Timestamp.fromDate(data['occurredAt']! as DateTime),
        },
        accountId,
        currency: currency,
      ),
]..sort((a, b) => b.occurredAt.compareTo(a.occurredAt));

void main() {
  late MemoryLedgerStore store;
  late FakeAccountsRepository accounts;
  late LedgerTransactionsRepository ledger;
  late Map<String, int> opening;

  setUp(() async {
    final clock = Clock.fixed(now);
    store = sampleLedgerStore(clock: clock);
    accounts = FakeAccountsRepository.sample(ledger: store, clock: clock)
      ..sharingDelay = Duration.zero;
    ledger = LedgerTransactionsRepository(store);
    opening = await balances(accounts);
  });

  tearDown(() => accounts.dispose());

  test('a save, an edit, a delete and a restore move the balance', () async {
    final saved = await ledger.saveEntries([expense()]);
    final id = saved.valueOrNull!.txnIds.single;
    expect(
      (await balances(accounts))['acc-checking'],
      opening['acc-checking']! - 1250,
    );

    await ledger.editEntry(id, expense(amount: 2000));
    expect(
      (await balances(accounts))['acc-checking'],
      opening['acc-checking']! - 2000,
    );

    // Moved to another account: the first gets it back.
    await ledger.editEntry(id, expense(amount: 2000, account: 'acc-visa'));
    final moved = await balances(accounts);
    expect(moved['acc-checking'], opening['acc-checking']);
    expect(moved['acc-visa'], opening['acc-visa']! - 2000);

    await ledger.deleteEntry(id);
    expect(await balances(accounts), opening);

    await ledger.restoreEntry(id);
    expect((await balances(accounts))['acc-visa'], opening['acc-visa']! - 2000);
  });

  test('a transfer moves both accounts', () async {
    await ledger.saveEntries([
      EntryDraft(
        id: 'd1',
        intent: 'transfer',
        amountMinor: 5000,
        currency: 'USD',
        accountId: 'acc-checking',
        toAccountId: 'acc-emergency',
        occurredOn: '2026-11-23',
      ),
    ]);
    final after = await balances(accounts);
    expect(after['acc-checking'], opening['acc-checking']! - 5000);
    expect(after['acc-emergency'], opening['acc-emergency']! + 5000);
  });

  test('a listener hears the save', () async {
    final seen = <int>[];
    final sub = accounts.watchAccounts().listen(
      (list) =>
          seen.add(list.firstWhere((a) => a.id == 'acc-checking').balanceMinor),
    );
    await pumpEventQueue();
    await ledger.saveEntries([expense()]);
    await pumpEventQueue();
    await sub.cancel();
    expect(seen, [opening['acc-checking'], opening['acc-checking']! - 1250]);
  });

  test(
    "entries match the Firestore adapter's mapping of the same documents",
    () async {
      final saved = await ledger.saveEntries([expense()]);
      final id = saved.valueOrNull!.txnIds.single;
      await ledger.saveEntries([
        EntryDraft(
          id: 'd2',
          intent: 'transfer',
          amountMinor: 7000,
          currency: 'USD',
          accountId: 'acc-visa',
          toAccountId: 'acc-checking',
          occurredOn: '2026-11-22',
        ),
      ]);
      final list = await accounts.watchEntries('acc-checking').first;
      expect(list, firestoreEntries(store, 'acc-checking', Currency.usd));
      expect(list.map((e) => e.id), contains(id));
      expect(list.firstWhere((e) => e.id == id).amountMinor, -1250);
      expect(
        list.firstWhere((e) => e.type == 'transfer' && e.amountMinor == 7000),
        isNotNull,
      );

      await ledger.deleteEntry(id);
      final after = await accounts.watchEntries('acc-checking').first;
      expect(after.map((e) => e.id), isNot(contains(id)));
      expect(after, firestoreEntries(store, 'acc-checking', Currency.usd));
    },
  );

  test('an opening balance is an adjustment through the write path', () async {
    final created = await accounts.create(
      const AccountDraft(
        name: 'Wallet',
        kind: AccountKind.cash,
        currency: Currency.usd,
        scope: AccountScope.personal,
        openingBalanceMinor: 4200,
      ),
    );
    final id = created.valueOrNull!;
    expect((await balances(accounts))[id], 4200);
    final entries = await accounts.watchEntries(id).first;
    expect(entries.single.type, 'adjustment');
    expect(entries.single.amountMinor, 4200);
    expect(entries, firestoreEntries(store, id, Currency.usd));
    // Deleting the opening entry takes the balance back to zero.
    await ledger.deleteEntry(entries.single.id);
    expect((await balances(accounts))[id], 0);
  });

  test(
    'without a ledger the fake keeps its own balances and entries',
    () async {
      final plain = FakeAccountsRepository.sample();
      final list = await plain.watchAccounts().first;
      expect(
        list.firstWhere((a) => a.id == 'acc-checking').balanceMinor,
        394000,
      );
      expect(await plain.watchEntries('acc-checking').first, hasLength(6));
      await plain.dispose();
    },
  );
}
