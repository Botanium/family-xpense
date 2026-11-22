// The agent's Firestore pieces against the Firestore emulator: the
// household reader (visibleTo, ranges, soft deletes, rate fallback) and
// FirestoreSessionStore with the `{hid}_{uid}` prefix (D-11), driven by a
// real agent turn on a scripted model. Run with tool/test_emulators.sh.
@Tags(['emulator'])
library;

import 'dart:io';

import 'package:genkit/genkit.dart';
import 'package:genkit_a2ui/a2ui.dart';
import 'package:google_cloud_firestore/google_cloud_firestore.dart' as fs;
import 'package:http/http.dart' as http;
import 'package:test/test.dart';
import 'package:xpense_agent/admin/firebase_admin_gateway.dart';
import 'package:xpense_agent/catalog/xpense_catalog_loader.dart';
import 'package:xpense_agent/config/runtime_config.dart';
import 'package:xpense_agent/decide/classifier.dart';
import 'package:xpense_agent/runtime/agent.dart';
import 'package:xpense_agent/runtime/firestore_household_reader.dart';
import 'package:xpense_agent/tools/household_reader.dart';

import '../runtime/scripted_model.dart';
import '../tools/support.dart';

const projectId = 'demo-xpense';

final String? firestoreHost = Platform.environment['FIRESTORE_EMULATOR_HOST'];

void main() {
  group(
    'agent on the Firestore emulator',
    _tests,
    skip: firestoreHost == null
        ? 'needs the Firestore emulator (tool/test_emulators.sh)'
        : null,
  );
}

void _tests() {
  late FirebaseAdminGateway admin;
  late fs.Firestore db;

  setUpAll(() async {
    await http.delete(
      Uri.http(
        firestoreHost!,
        '/emulator/v1/projects/$projectId/databases/(default)/documents',
      ),
    );
    admin = FirebaseAdminGateway.initialize(
      projectId: projectId,
      appName: 'agent-firestore-test',
    );
    db = admin.firestore;
    const h = 'households/hh1';
    await db.doc(h).set({
      'baseCurrency': 'USD',
      'timeZone': 'Asia/Baghdad',
      'memberIds': ['u1', 'u2'],
    });
    await db.doc('$h/members/u1').set({'displayName': 'Dara'});
    await db.doc('$h/members/u2').set({'displayName': 'Shilan'});
    await db.doc('$h/accounts/acc_chk').set({
      'name': 'Checking',
      'currency': 'USD',
      'scope': 'joint',
      'visibleTo': ['u1', 'u2'],
      'balanceMinor': 1000,
    });
    await db.doc('$h/accounts/acc_private').set({
      'name': 'Private',
      'currency': 'USD',
      'scope': 'personal',
      'ownerUid': 'u2',
      'visibleTo': ['u2'],
    });
    await db.doc('$h/categories/water').set({
      'slug': 'water',
      'names': {'en': 'Water'},
      'kind': 'expense',
    });
    await db.doc('$h/categories/salary').set({
      'slug': 'salary',
      'names': {'en': 'Salary'},
      'kind': 'income',
    });
    Map<String, Object?> txn(String on, int amount, List<String> visibleTo) => {
      'type': 'expense',
      'amountMinor': amount,
      'currency': 'USD',
      'baseAmountMinor': amount,
      'accountId': 'acc_chk',
      'occurredOn': on,
      'title': 'x',
      'visibleTo': visibleTo,
    };
    await db
        .doc('$h/transactions/t1')
        .set(txn('2026-11-02', 100, ['u1', 'u2']));
    await db.doc('$h/transactions/t2').set(txn('2026-11-03', 200, ['u2']));
    await db.doc('$h/transactions/t3').set({
      ...txn('2026-11-04', 300, ['u1', 'u2']),
      'deletedAt': DateTime.utc(2026, 11, 5),
    });
    await db.doc('$h/transactions/t4').set(txn('2026-10-30', 400, ['u1']));
    await db.doc('$h/fxRates/2026-11-01').set({
      'usdIqd': '1520',
      'kind': 'market',
    });
    await db.doc('$h/fxRates/2026-11-10').set({
      'usdIqd': '1530',
      'kind': 'official',
    });
  });

  tearDownAll(() => admin.gateway.close());

  test('the reader filters by visibleTo, range and soft delete', () async {
    final reader = FirestoreHouseholdReader(db);
    expect((await reader.profile('hh1'))?.baseCurrency, 'USD');
    expect(await reader.profile('nope'), isNull);
    expect((await reader.accounts('hh1', uid: 'u1')).map((a) => a.id), [
      'acc_chk',
    ]);
    expect(await reader.accounts('hh1', uid: 'u2'), hasLength(2));
    expect(
      (await reader.categories('hh1')).map((c) => c.name),
      containsAll(['Water', 'Salary']),
    );
    final txns = await reader.transactions(
      'hh1',
      uid: 'u1',
      fromOn: '2026-11-01',
      toOn: '2026-11-30',
    );
    expect(txns.items.map((t) => t.id), ['t1']);
    expect(txns.complete, isTrue);
    final rate = await reader.fxRateOn('hh1', '2026-11-08');
    expect(rate?.usdIqd, '1520');
    expect(rate?.date, '2026-11-01');
    expect((await reader.fxRateOn('hh1', '2026-11-10'))?.kind, 'official');
    expect(await reader.fxRateOn('hh1', '2026-10-01'), isNull);
  });

  test(
    'range reads page through everything, and say when they are cut',
    () async {
      const h = 'households/hh2';
      await db.doc(h).set({'baseCurrency': 'USD'});
      for (var i = 1; i <= 7; i++) {
        await db.doc('$h/transactions/p$i').set({
          'type': 'expense',
          'amountMinor': i * 100,
          'currency': 'USD',
          'accountId': 'a',
          // Two per day, so the cursor must order by document id as well.
          'occurredOn': '2026-11-0${(i + 1) ~/ 2}',
          'title': 'x',
          'visibleTo': ['u1'],
        });
      }
      final paged = FirestoreHouseholdReader(db, pageSize: 2);
      final all = await paged.transactions(
        'hh2',
        uid: 'u1',
        fromOn: '2026-11-01',
        toOn: '2026-11-30',
      );
      expect(all.complete, isTrue);
      expect(all.items.map((t) => t.id).toSet(), {
        for (var i = 1; i <= 7; i++) 'p$i',
      });
      expect(all.items, hasLength(7));
      expect(all.items.first.occurredOn, '2026-11-04');

      final capped = FirestoreHouseholdReader(
        db,
        pageSize: 2,
        maxTransactions: 5,
      );
      final cut = await capped.transactions(
        'hh2',
        uid: 'u1',
        fromOn: '2026-11-01',
        toOn: '2026-11-30',
      );
      expect(cut.complete, isFalse);
      expect(cut.items, hasLength(5));

      final exact = FirestoreHouseholdReader(
        db,
        pageSize: 2,
        maxTransactions: 7,
      );
      expect(
        (await exact.transactions(
          'hh2',
          uid: 'u1',
          fromOn: '2026-11-01',
          toOn: '2026-11-30',
        )).complete,
        isTrue,
      );
    },
  );

  test('hidden accounts and budget scope come from Firestore', () async {
    final reader = FirestoreHouseholdReader(db);
    // hh1 has a private account of u2 (seeded above).
    expect(await reader.hasHiddenAccounts('hh1', uid: 'u1'), isTrue);
    expect(await reader.hasHiddenAccounts('hh1', uid: 'u2'), isFalse);
    await db.doc('households/hh1/budgets/b1').set({
      'categoryId': 'total',
      'limitMinor': 5000,
      'scope': 'u1',
      'visibleTo': ['u1'],
    });
    await db.doc('households/hh1/budgets/b2').set({
      'categoryId': 'total',
      'limitMinor': 9000,
      'visibleTo': ['u1', 'u2'],
    });
    final budgets = {
      for (final b in await reader.budgets('hh1', uid: 'u1')) b.id: b,
    };
    expect(budgets['b1']!.scope, 'u1');
    expect(budgets['b1']!.isPersonal, isTrue);
    expect(budgets['b2']!.scope, householdBudgetScope);
  });

  test('sessions are stored under agentSessions/{hid}_{uid}', () async {
    final ai = Genkit(plugins: [A2uiPlugin()], promptDir: 'prompts');
    final script = Script(entries: salaryGroceries, render: scriptedCapture);
    defineScripted(ai, 'test/lite', script);
    final rt = XpenseAgentRuntime.create(
      ai: ai,
      catalogJson: await readCatalogJson(),
      reader: FirestoreHouseholdReader(db),
      classifier: FakeEntryClassifier(),
      config: () async => RuntimeConfig.fromDocument(const {
        'models': {'agent': 'lite', 'escalation': 'lite'},
      }),
      sessions: FirestoreSessions(db),
      modelName: (id) => 'test/$id',
      clock: fixedClock,
    );
    const context = {
      'uid': 'u1',
      'hid': 'hh1',
      'locale': 'en',
      'privacyMode': 'smart',
      'tz': 'Asia/Baghdad',
    };
    final res = await rt.runTurn(
      'Salary came in 3200 and groceries were 1400',
      context: context,
    );
    final snapshotId = res['snapshotId'] as String;
    final stored = await db.collection('agentSessions/hh1_u1/snapshots').get();
    expect(stored.docs.map((d) => d.id), contains(snapshotId));

    // The same snapshot id from another household's member loads nothing.
    final other = {...context, 'hid': 'hh2', 'uid': 'u9'};
    await expectLater(
      rt.runTurn('hi', context: other, snapshotId: snapshotId),
      throwsA(anything),
    );
    // Resuming as the owner works.
    final again = await rt.runTurn(
      'and coffee 4',
      context: context,
      snapshotId: snapshotId,
    );
    expect(again['snapshotId'], isNot(snapshotId));
  });
}
