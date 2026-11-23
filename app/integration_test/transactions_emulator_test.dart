// The transaction write path offline (WP-20, BACKLOG S2.1, DATA_MODEL 3
// and 7) against the Firebase emulator suite, under the fake project
// `demo-xpense`. The real Firestore SDK and the real rules: saves, an edit
// and a delete made with the network off, then replayed on reconnect and
// checked against the ledger the way the nightly reconcile does. Not run
// by CI: it needs a simulator and the emulators. No server is needed.
//
//   cd firebase && firebase emulators:start --project demo-xpense \
//     --only auth,firestore
//   cd app && flutter test integration_test/transactions_emulator_test.dart \
//     -d <simulator> --dart-define=XPENSE_ENV=emulators
//
// Other ports: --dart-define=XPENSE_AUTH_EMULATOR=127.0.0.1:9299
// --dart-define=XPENSE_FIRESTORE_EMULATOR=127.0.0.1:8380.
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:xpense_app/bootstrap.dart';
import 'package:xpense_app/data/accounts_repository.dart';
import 'package:xpense_app/data/auth_repository.dart';
import 'package:xpense_app/data/household_repository.dart';
import 'package:xpense_app/data/transactions_repository.dart';
import 'package:xpense_shared/xpense_shared.dart';

const String _auth = String.fromEnvironment(
  'XPENSE_AUTH_EMULATOR',
  defaultValue: defaultAuthEmulator,
);
const String _firestore = String.fromEnvironment(
  'XPENSE_FIRESTORE_EMULATOR',
  defaultValue: defaultFirestoreEmulator,
);

Future<void> until(bool Function() done, String what) async {
  for (var i = 0; i < 150 && !done(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
  expect(done(), true, reason: 'timed out waiting for $what');
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('saves, edits and deletes offline, then reconciles', (
    tester,
  ) async {
    expect(
      AppEnvironment.compiled,
      AppEnvironment.emulators,
      reason: 'run with --dart-define=XPENSE_ENV=emulators',
    );
    final app = await bootstrap(environment: AppEnvironment.compiled);
    final container = ProviderContainer(overrides: app.overrides);
    addTearDown(container.dispose);
    final firestore = FirebaseFirestore.instance;

    // A new member and household, online.
    final auth = container.read(authRepositoryProvider);
    await auth.signOut();
    final email = 'wp20-${DateTime.now().millisecondsSinceEpoch}@example.com';
    const password = 'secret12';
    final signedUp = await auth.createAccountWithEmail(
      email: email,
      password: password,
    );
    final uid = signedUp.valueOrNull!.uid;
    final households = container.read(householdRepositoryProvider);
    final hid = (await households.create(
      name: 'Ledger test',
      displayName: 'Alex',
      baseCurrency: Currency.usd,
    )).valueOrNull!;
    await until(() => households.current is InHousehold, 'the household');
    final accounts = container.read(accountsRepositoryProvider);
    await until(() => accounts.viewerUid == uid, 'the accounts adapter');

    // Opening balances go through the write path too (replacing WP-13's
    // helper): 100.00 USD joint, 50,000 IQD personal with a typed rate.
    final joint = (await accounts.create(
      const AccountDraft(
        name: 'Joint',
        kind: AccountKind.bank,
        currency: Currency.usd,
        scope: AccountScope.joint,
        openingBalanceMinor: 10000,
      ),
    )).valueOrNull!;
    final cash = (await accounts.create(
      AccountDraft(
        name: 'Cash',
        kind: AccountKind.cash,
        currency: Currency.iqd,
        scope: AccountScope.personal,
        openingBalanceMinor: 50000,
        openingRate: FxRate.forPair(FxPair.usdIqd, '1705').valueOrNull,
      ),
    )).valueOrNull!;
    await firestore.waitForPendingWrites();

    final household = firestore.collection('households').doc(hid);
    final txns = household.collection('transactions');
    Future<int> balance(String id, Source source) async =>
        (await household
                    .collection('accounts')
                    .doc(id)
                    .get(GetOptions(source: source)))
                .data()!['balanceMinor']
            as int;
    expect(await balance(joint, Source.server), 10000);
    expect(await balance(cash, Source.server), 50000);

    // ---------------------------------------------------- offline writes
    await firestore.disableNetwork();
    final repo = container.read(transactionsRepositoryProvider);
    final saved = (await repo.saveEntries([
      EntryDraft(
        id: 'groceries',
        intent: 'expense',
        amountMinor: 1250,
        currency: 'USD',
        accountId: joint,
        categoryId: 'groceries',
        title: 'Lulu',
      ),
      EntryDraft(
        id: 'dinner',
        intent: 'expense',
        amountMinor: 25000,
        currency: 'IQD',
        accountId: cash,
        categoryId: 'dining',
      ),
      EntryDraft(
        id: 'to-cash',
        intent: 'transfer',
        amountMinor: 2000,
        accountId: joint,
        toAccountId: cash,
      ),
    ], source: EntrySource.chat)).valueOrNull;
    expect(saved, isNotNull, reason: 'the save is accepted offline');
    expect(saved!.ack, WriteAck.queued);
    final [groceries, dinner, toCash] = saved.txnIds;

    final edited = await repo.editEntry(
      groceries,
      EntryDraft(
        id: groceries,
        intent: 'expense',
        amountMinor: 3000,
        accountId: joint,
        categoryId: 'groceries',
        title: 'Lulu',
      ),
    );
    expect(edited.valueOrNull, WriteAck.queued);
    expect((await repo.deleteEntry(dinner)).valueOrNull, WriteAck.queued);

    // The phone shows it all at once from its cache.
    // Joint: 100.00 − 30.00 − 20.00; cash: 50,000 − 0 + 34,100.
    expect(await balance(joint, Source.cache), 5000);
    expect(await balance(cash, Source.cache), 84100);
    final cachedTransfer =
        (await txns.doc(toCash).get(const GetOptions(source: Source.cache)))
            .data()!;
    expect(cachedTransfer['toAmountMinor'], 34100);
    expect(cachedTransfer['visibleTo'], [uid]);
    expect(cachedTransfer.containsKey('deletedAt'), true);

    // ------------------------------------------------------- reconnect
    await firestore.enableNetwork();
    await firestore.waitForPendingWrites();
    expect(await balance(joint, Source.server), 5000);
    expect(await balance(cash, Source.server), 84100);

    Future<Map<String, Map<String, dynamic>>> serverLedger() async {
      final snapshot = await txns
          .where('visibleTo', arrayContains: uid)
          .get(const GetOptions(source: Source.server));
      return {for (final d in snapshot.docs) d.id: d.data()};
    }

    // The nightly reconcile's check, with the shared effect table.
    Future<void> expectReconciled() async {
      final ledger = await serverLedger();
      final totals = ledgerTotals([
        for (final data in ledger.values) ?LedgerLine.fromFields(data),
      ]);
      expect(await balance(joint, Source.server), totals.account(joint));
      expect(await balance(cash, Source.server), totals.account(cash));
    }

    await expectReconciled();
    final ledger = await serverLedger();
    expect(ledger, hasLength(5), reason: '2 opening + 3 saved');
    expect(ledger[groceries]!['rev'], 1);
    expect(ledger[groceries]!['amountMinor'], 3000);
    // The edit names the version it was built on; the delete after it
    // named the edit's (rules: prevRevId == stored revId).
    expect(ledger[groceries]!['prevRevId'], isA<String>());
    expect(ledger[dinner]!['prevRevId'], isA<String>());
    expect(ledger[dinner]!['deletedAt'], isA<Timestamp>());
    expect(ledger[dinner]!['fx'], {
      'pair': 'USD/IQD',
      'pairRate': '1705',
      'source': 'market',
      'asOf': ledger[dinner]!['occurredOn'],
    });
    expect(ledger[dinner]!['baseAmountMinor'], 1466);
    expect(ledger[toCash]!['source'], 'chat');
    for (final data in ledger.values) {
      expect(data.containsKey('visibilityAppliedTo'), false);
      expect(data.containsKey('visibilitySync'), false);
    }
    final revisions = await txns
        .doc(groceries)
        .collection('revisions')
        .get(const GetOptions(source: Source.server));
    expect(revisions.docs.single.data()['before'], {
      'amountMinor': 1250,
      'baseAmountMinor': 1250,
    });
    expect(revisions.docs.single.data()['reason'], 'edit');

    // Account history queries filter deletedAt == null (PR #33): every live
    // entry stores it explicitly, so they all match.
    final live = await txns
        .where('visibleTo', arrayContains: uid)
        .where('accountId', isEqualTo: joint)
        .where('deletedAt', isNull: true)
        .get(const GetOptions(source: Source.server));
    expect(live.docs.map((d) => d.id).toSet(), {
      for (final e in ledger.entries)
        if (e.value['accountId'] == joint) e.key,
    });
    expect(live.docs, hasLength(3), reason: 'opening, groceries, transfer');

    // ------------------------------------------------ online undo, restore
    expect((await repo.restoreEntry(dinner)).valueOrNull, WriteAck.synced);
    expect((await repo.undoSave(saved)).valueOrNull, WriteAck.synced);
    expect(await balance(joint, Source.server), 10000);
    expect(await balance(cash, Source.server), 50000);
    await expectReconciled();

    // ----------------------------------- a newer rate this phone has not seen
    // Another phone of the household (here: a second Firebase app signed in
    // as the same member) enters tomorrow's rate. This phone's cache still
    // only holds today's 1,705; an entry dated tomorrow must use the
    // server's newer 1,600 (Codex review, PR #35).
    final other = await Firebase.initializeApp(
      name: 'wp20-other-phone',
      demoProjectId: emulatorProjectId,
    );
    final otherAuth = FirebaseAuth.instanceFor(app: other);
    final authHost = _auth.split(':');
    await otherAuth.useAuthEmulator(authHost[0], int.parse(authHost[1]));
    final otherDb = FirebaseFirestore.instanceFor(app: other);
    final dbHost = _firestore.split(':');
    otherDb
      ..useFirestoreEmulator(dbHost[0], int.parse(dbHost[1]))
      ..settings = const Settings(persistenceEnabled: false);
    await otherAuth.signInWithEmailAndPassword(
      email: email,
      password: password,
    );
    final tomorrow = DateTime.now().add(const Duration(days: 1));
    String two(int v) => v.toString().padLeft(2, '0');
    final tomorrowDay =
        '${tomorrow.year}-${two(tomorrow.month)}-${two(tomorrow.day)}';
    await otherDb
        .collection('households')
        .doc(hid)
        .collection('fxRates')
        .doc(tomorrowDay)
        .set({
          'usdIqd': '1600',
          'kind': 'market',
          'enteredBy': uid,
          'enteredAt': FieldValue.serverTimestamp(),
        });
    final priced = (await repo.saveEntries([
      EntryDraft(
        id: 'tomorrow',
        intent: 'expense',
        amountMinor: 16000,
        accountId: cash,
        categoryId: 'dining',
        occurredOn: tomorrowDay,
      ),
    ])).valueOrNull!;
    final pricedDoc =
        (await txns
                .doc(priced.txnIds.single)
                .get(const GetOptions(source: Source.server)))
            .data()!;
    expect((pricedDoc['fx']! as Map)['pairRate'], '1600');
    expect((pricedDoc['fx']! as Map)['asOf'], tomorrowDay);
    expect(pricedDoc['baseAmountMinor'], 1000);
    await expectReconciled();
    await otherAuth.signOut();
    await other.delete();
    debugPrint('XPENSE_WP20_EMULATOR=ok');
  });
}
