// Home's read path (WP-23, DATA_MODEL 6) against the Firebase emulator
// suite, under the fake project `demo-xpense`: the real Firestore SDK and
// the real rules. The month and Recent queries pass the rules (they carry
// the visibleTo filter), keep to their day range, and drop a deleted entry,
// including a delete still waiting for the server while offline. Not run
// by CI: it needs a simulator and the emulators. The emulator does not
// enforce composite indexes, so this proves the query shape and the rules,
// not the index; the index is in firebase/firestore.indexes.json.
//
//   cd firebase && firebase emulators:start --project demo-xpense \
//     --only auth,firestore
//   cd app && flutter test integration_test/home_reader_emulator_test.dart \
//     -d <simulator> --dart-define=XPENSE_ENV=emulators
//
// Other ports: --dart-define=XPENSE_AUTH_EMULATOR=127.0.0.1:9499
// --dart-define=XPENSE_FIRESTORE_EMULATOR=127.0.0.1:8580.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:xpense_app/bootstrap.dart';
import 'package:xpense_app/data/accounts_repository.dart';
import 'package:xpense_app/data/auth_repository.dart';
import 'package:xpense_app/data/household_repository.dart';
import 'package:xpense_app/data/read/home_reader.dart';
import 'package:xpense_app/data/transactions_repository.dart';
import 'package:xpense_shared/xpense_shared.dart';

Future<void> until(bool Function() done, String what) async {
  for (var i = 0; i < 150 && !done(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
  expect(done(), true, reason: 'timed out waiting for $what');
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('month and recent reads: range, rules and deletes', (
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

    final auth = container.read(authRepositoryProvider);
    await auth.signOut();
    final signedUp = await auth.createAccountWithEmail(
      email: 'wp23-${DateTime.now().millisecondsSinceEpoch}@example.com',
      password: 'secret12',
    );
    final uid = signedUp.valueOrNull!.uid;
    final households = container.read(householdRepositoryProvider);
    await households.create(
      name: 'Home test',
      displayName: 'Alex',
      baseCurrency: Currency.usd,
    );
    await until(() => households.current is InHousehold, 'the household');
    final accounts = container.read(accountsRepositoryProvider);
    await until(() => accounts.viewerUid == uid, 'the accounts adapter');
    final joint = (await accounts.create(
      const AccountDraft(
        name: 'Joint',
        kind: AccountKind.bank,
        currency: Currency.usd,
        scope: AccountScope.joint,
      ),
    )).valueOrNull!;

    EntryDraft draft(String id, String intent, int cents, String day) =>
        EntryDraft(
          id: id,
          intent: intent,
          amountMinor: cents,
          currency: 'USD',
          accountId: joint,
          categoryId: intent == 'expense' ? 'groceries' : 'salary',
          title: id,
          occurredOn: day,
          occurredTime: '12:00',
        );
    final repo = container.read(transactionsRepositoryProvider);
    final saved = await repo.saveEntries([
      draft('lunch', 'expense', 1250, '2026-11-03'),
      draft('salary', 'income', 300000, '2026-11-01'),
      draft('coffee', 'expense', 400, '2026-11-20'),
      draft('october', 'expense', 9900, '2026-10-31'),
      draft('december', 'expense', 9900, '2026-12-01'),
    ]);
    expect(saved.isOk, isTrue, reason: '$saved');
    final ids = saved.valueOrNull!.txnIds;
    await firestore.waitForPendingWrites();

    final reader = container.read(homeReaderProvider);
    List<LedgerTransaction>? month;
    List<LedgerTransaction>? recent;
    final subs = [
      reader
          .watchRange(fromDay: '2026-11-01', toDay: '2026-11-30')
          .listen((v) => month = v, onError: (Object e) => fail('month: $e')),
      reader
          .watchRecent(limit: 4)
          .listen((v) => recent = v, onError: (Object e) => fail('recent: $e')),
    ];
    addTearDown(() async {
      for (final s in subs) {
        await s.cancel();
      }
    });
    List<String> titles(List<LedgerTransaction>? list) => [
      for (final t in list ?? const <LedgerTransaction>[]) t.title,
    ];

    await until(() => (month?.length ?? 0) == 3, 'the month');
    expect(titles(month), [
      'salary',
      'lunch',
      'coffee',
    ], reason: 'oldest first');
    expect(month!.every((t) => t.visibleTo.contains(uid)), isTrue);
    expect(month!.firstWhere((t) => t.title == 'lunch').baseAmountMinor, 1250);
    await until(() => (recent?.length ?? 0) == 4, 'recent');

    // A delete on the server.
    expect((await repo.deleteEntry(ids[2])).isOk, isTrue);
    await until(() => !titles(month).contains('coffee'), 'coffee gone');
    await until(() => !titles(recent).contains('coffee'), 'coffee gone too');

    // A delete still waiting for the server: gone from the month at once.
    await firestore.disableNetwork();
    final offline = await repo.deleteEntry(ids[0]);
    expect(offline.valueOrNull, WriteAck.queued);
    await until(() => !titles(month).contains('lunch'), 'lunch gone offline');
    expect(titles(month), ['salary']);
    await firestore.enableNetwork();
    await firestore.waitForPendingWrites();
    expect(titles(month), ['salary']);
  });
}
