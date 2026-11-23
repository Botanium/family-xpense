// Accounts, privacy and sharing end to end (WP-13, BACKLOG S1.6, S1.7,
// S1.8) against the Firebase emulator suite and a local server, under the
// fake project `demo-xpense`. Not run by CI: it needs a simulator, the
// emulators and two server processes (the agent and the jobs role).
//
//   cd firebase && firebase emulators:start --project demo-xpense \
//     --only auth,firestore
//   cd server && FIREBASE_AUTH_EMULATOR_HOST=127.0.0.1:9099 \
//     FIRESTORE_EMULATOR_HOST=127.0.0.1:8280 XPENSE_APP_CHECK=emulator \
//     dart run bin/server.dart                      # agent, port 8080
//   cd server && FIREBASE_AUTH_EMULATOR_HOST=127.0.0.1:9099 \
//     FIRESTORE_EMULATOR_HOST=127.0.0.1:8280 XPENSE_APP_CHECK=emulator \
//     XPENSE_ROLE=jobs PORT=8081 dart run bin/server.dart
//   cd app && flutter test integration_test/accounts_emulator_test.dart \
//     -d <phone> --dart-define=XPENSE_ENV=emulators
//
// The owner signs up and adds accounts on the phone. The partner is played
// over HTTP: an Auth emulator sign-up, the server's join route, and
// Firestore REST reads under the partner's token, which the emulator checks
// against the rules. Eventarc does not exist locally, so the test posts the
// account-visibility event to the jobs service itself.
import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:xpense_app/app.dart';
import 'package:xpense_app/bootstrap.dart';
import 'package:xpense_app/core/routing/routing.dart';
import 'package:xpense_app/core/ui/ui.dart';
import 'package:xpense_app/data/accounts_repository.dart';
import 'package:xpense_app/data/accounts_repository_firebase.dart';
import 'package:xpense_app/data/household_repository.dart';

import 'household_emulator_test.dart' show signUp, startSignedOut;
import 'onboarding_emulator_test.dart' show pumpUntil, tapText, typeInto;

const String _auth = String.fromEnvironment(
  'XPENSE_AUTH_EMULATOR',
  defaultValue: defaultAuthEmulator,
);
const String _firestore = String.fromEnvironment(
  'XPENSE_FIRESTORE_EMULATOR',
  defaultValue: defaultFirestoreEmulator,
);
const String _server = String.fromEnvironment(
  'XPENSE_SERVER_URL',
  defaultValue: defaultLocalServer,
);
const String _jobs = String.fromEnvironment(
  'XPENSE_JOBS_URL',
  defaultValue: 'http://127.0.0.1:8081/',
);

final RegExp _shownCode = RegExp(r'^[0-9A-Z]{5}-[0-9A-Z]{5}$');

Future<(int, Object?)> _send(
  String method,
  Uri url, {
  Map<String, String> headers = const {},
  Object? body,
}) async {
  final client = HttpClient();
  try {
    final request = await client.openUrl(method, url);
    headers.forEach(request.headers.set);
    if (body != null) {
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode(body));
    }
    final response = await request.close();
    final text = await response.transform(utf8.decoder).join();
    return (response.statusCode, text.isEmpty ? null : jsonDecode(text));
  } finally {
    client.close(force: true);
  }
}

/// The partner: an Auth emulator account.
Future<({String uid, String token})> _partnerSignUp() async {
  final (status, body) = await _send(
    'POST',
    Uri.parse(
      'http://$_auth/identitytoolkit.googleapis.com/v1/accounts:signUp'
      '?key=fake-api-key',
    ),
    body: {
      'email': 'partner-${DateTime.now().millisecondsSinceEpoch}@example.com',
      'password': 'secret12',
      'returnSecureToken': true,
    },
  );
  expect(status, 200, reason: '$body');
  final json = body! as Map<String, Object?>;
  return (uid: json['localId']! as String, token: json['idToken']! as String);
}

String _docs(String hid) =>
    'http://$_firestore/v1/projects/$emulatorProjectId/databases/(default)'
    '/documents/households/$hid';

/// GET one document as [token]; the status says whether the rules allowed.
Future<int> _get(String token, String url) async =>
    (await _send('GET', Uri.parse(url), headers: _bearer(token))).$1;

/// The transactions on [accountId] the partner may list.
Future<int> _partnerEntries(
  String hid,
  String partner,
  String token,
  String accountId,
) async {
  final (status, body) = await _send(
    'POST',
    Uri.parse('${_docs(hid)}:runQuery'),
    headers: _bearer(token),
    body: {
      'structuredQuery': {
        'from': [
          {'collectionId': 'transactions'},
        ],
        'where': {
          'compositeFilter': {
            'op': 'AND',
            'filters': [
              {
                'fieldFilter': {
                  'field': {'fieldPath': 'visibleTo'},
                  'op': 'ARRAY_CONTAINS',
                  'value': {'stringValue': partner},
                },
              },
              {
                'fieldFilter': {
                  'field': {'fieldPath': 'accountId'},
                  'op': 'EQUAL',
                  'value': {'stringValue': accountId},
                },
              },
            ],
          },
        },
      },
    },
  );
  expect(status, 200, reason: '$body');
  return (body! as List)
      .where((r) => (r as Map).containsKey('document'))
      .length;
}

Map<String, String> _bearer(String token) => {'authorization': 'Bearer $token'};

/// Pumps until [done], without settling: a spinner never settles.
Future<void> _waitFor(
  WidgetTester tester,
  bool Function() done,
  String what,
) async {
  for (var i = 0; i < 150 && !done(); i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  expect(done(), isTrue, reason: 'waited 15 s for $what');
}

Finder _amount() => find.descendant(
  of: find.byType(AmountField),
  matching: find.byType(EditableText),
);

Future<void> _addAccount(
  WidgetTester tester, {
  required String kind,
  required String name,
  required String amount,
  bool joint = false,
  bool dinars = false,
  String? rate,
}) async {
  await tapText(tester, kind);
  await tapText(tester, joint ? 'Joint' : 'Just me');
  await typeInto(tester, 'Name', name);
  // The toggle keeps its currency between adds.
  final other = find.bySemanticsLabel(
    dinars ? 'Currency, USD' : 'Currency, IQD',
  );
  if (other.evaluate().isNotEmpty) {
    await tester.tap(other);
    await tester.pumpAndSettle();
  }
  if (amount.isNotEmpty) await tester.enterText(_amount(), amount);
  await tester.pumpAndSettle();
  if (rate != null) {
    await typeInto(tester, "Today's dollar rate, in dinars", rate);
  }
  await tapText(tester, 'Add account');
  await pumpUntil(
    tester,
    () => find.text(name).evaluate().isNotEmpty,
    'the added $name',
  );
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'add accounts, keep one private, share it, backfill its history',
    (tester) async {
      final container = await startSignedOut(tester);
      Uri location() => container.read(routerProvider).state.uri;

      // Screens 1 to 3.
      await tapText(tester, 'Get started');
      await signUp(tester, 'owner');
      await pumpUntil(
        tester,
        () => location().path == AppRoutes.householdSetup,
        'household setup',
      );
      await typeInto(tester, 'Household name', 'Our home');
      await typeInto(tester, 'Your name', 'Alex');
      await tapText(tester, 'Continue');
      final code = find.byWidgetPredicate(
        (w) => w is Text && _shownCode.hasMatch(w.data ?? ''),
      );
      await pumpUntil(tester, () => code.evaluate().isNotEmpty, 'invite code');
      final invite = tester.widget<Text>(code).data!.replaceAll('-', '');
      await tapText(tester, 'Continue');

      // Screen 4: three accounts, with opening balances.
      expect(location().path, AppRoutes.addAccounts);
      await _addAccount(
        tester,
        kind: 'Bank',
        name: 'My checking',
        amount: '3940',
      );
      await _addAccount(
        tester,
        kind: 'Card',
        name: 'Joint Visa',
        amount: '612',
        joint: true,
      );
      // An empty dinar account before the household has any rate: no
      // opening entry, so no rate is needed (Codex review, PR #33).
      await _addAccount(
        tester,
        kind: 'Savings',
        name: 'Dinar savings',
        amount: '',
        dinars: true,
      );
      await _addAccount(
        tester,
        kind: 'Cash',
        name: 'Cash wallet',
        amount: '250000',
        dinars: true,
        rate: '1,705',
      );
      // Household setup's Continue is still in the tree, offstage.
      await tester.tap(find.text('Continue').hitTestable());
      await tester.pumpAndSettle();
      expect(location().path, AppRoutes.tryIt);

      // Screen 10: alone in the household, everything is visible.
      container.read(routerProvider).go(AppRoutes.accounts);
      await pumpUntil(
        tester,
        () => find.text('USD 3,474.63').evaluate().isNotEmpty,
        'the total: 3,940.00 − 612.00 + 250,000 IQD at 1,705',
      );
      expect(find.text('Household balance'), findsOneWidget);

      final hid =
          (container.read(householdRepositoryProvider).current as InHousehold)
              .household
              .id;
      final accounts = await container
          .read(accountsRepositoryProvider)
          .watchAccounts()
          .firstWhere((list) => list.length == 4);
      String idOf(String name) => accounts.firstWhere((a) => a.name == name).id;
      final checking = idOf('My checking');
      final visa = idOf('Joint Visa');
      expect(
        accounts.firstWhere((a) => a.id == visa).balanceMinor,
        -61200,
        reason: 'the opening adjustment incremented the balance',
      );

      // Deleted entries never use up the detail screen's page (Codex
      // review, PR #33): four entries, the two newest soft-deleted, read
      // through an adapter that shows two.
      final savings = idOf('Dinar savings');
      final owner = FirebaseAuth.instance.currentUser!.uid;
      await _ownerEntries(hid, owner, savings, deletedNewest: 2);
      final small = FirebaseAccountsRepository(
        auth: FirebaseAuth.instance,
        firestore: FirebaseFirestore.instance,
        households: container.read(householdRepositoryProvider),
        entriesLimit: 2,
      );
      addTearDown(small.dispose);
      final page = await small
          .watchEntries(savings)
          .firstWhere((entries) => entries.isNotEmpty)
          .timeout(const Duration(seconds: 15));
      expect(page.map((e) => e.title), ['Entry 2', 'Entry 1']);

      // The partner joins over the server; joint accounts widen to them.
      final partner = await _partnerSignUp();
      final (joinStatus, joinBody) = await _send(
        'POST',
        Uri.parse(_server).resolve('v1/household/join'),
        headers: {..._bearer(partner.token), 'x-firebase-appcheck': 'emulator'},
        body: {
          'data': {'code': invite, 'displayName': 'Sam'},
        },
      );
      expect(joinStatus, 200, reason: '$joinBody');
      await pumpUntil(
        tester,
        () => find.text('Sam').evaluate().isNotEmpty,
        'the Sam filter once the partner is a member',
      );

      // S1.7: the partner reads the joint card and its opening entry, and
      // nothing of the private account.
      final accountsUrl = '${_docs(hid)}/accounts';
      expect(await _get(partner.token, '$accountsUrl/$visa'), 200);
      expect(await _partnerEntries(hid, partner.uid, partner.token, visa), 1);
      expect(await _get(partner.token, '$accountsUrl/$checking'), 403);
      expect(
        await _partnerEntries(hid, partner.uid, partner.token, checking),
        0,
      );

      // S1.8: share the checking account; "Sharing…" until the job ran.
      await tester.tap(find.text('My checking').hitTestable());
      await tester.pumpAndSettle();
      expect(find.text('Share with Sam'), findsOneWidget);
      await tester.tap(find.byType(XpSwitch));
      await _waitFor(
        tester,
        () => find.textContaining('Sharing past entries').evaluate().isNotEmpty,
        'the sharing line',
      );
      final (jobStatus, jobBody) = await _send(
        'POST',
        Uri.parse(_jobs).resolve('events/account-visibility'),
        headers: {'ce-document': 'households/$hid/accounts/$checking'},
      );
      expect(jobStatus, 200, reason: '$jobBody');
      expect((jobBody! as Map)['rewritten'], 1);
      await pumpUntil(
        tester,
        () => find.textContaining('Sharing past entries').evaluate().isEmpty,
        'the sharing line to go once the history is shared',
      );
      expect(await _get(partner.token, '$accountsUrl/$checking'), 200);
      expect(
        await _partnerEntries(hid, partner.uid, partner.token, checking),
        1,
      );

      // The review's attack: while it is shared, the partner tries to mark
      // the history as already private, so a later revoke would be
      // skipped. The rules refuse it; the same write to the name passes,
      // so the stamps are right and only the field is refused.
      final account = 'households/$hid/accounts/$checking';
      expect(
        await _partnerCommit(partner, account, 'visibilityAppliedTo', {
          'arrayValue': {
            'values': [
              {'stringValue': partner.uid},
            ],
          },
        }),
        403,
      );
      expect(
        // A lease far in the future would make every delivery "busy".
        await _partnerCommit(partner, account, 'visibilitySync', {
          'mapValue': {
            'fields': {
              'runId': {'stringValue': 'forged'},
              'leaseUntil': {'timestampValue': '9999-01-01T00:00:00Z'},
            },
          },
        }),
        403,
      );
      expect(
        await _partnerCommit(partner, account, 'name', {
          'stringValue': 'My checking',
        }),
        200,
      );

      // Revoke: the owner turns sharing off; the partner loses the account
      // at once and its history once the job has run.
      await tester.tap(find.byType(XpSwitch));
      await _waitFor(
        tester,
        () => find
            .textContaining('Making past entries private')
            .evaluate()
            .isNotEmpty,
        'the unsharing line',
      );
      expect(await _get(partner.token, '$accountsUrl/$checking'), 403);
      final (revokeStatus, revokeBody) = await _send(
        'POST',
        Uri.parse(_jobs).resolve('events/account-visibility'),
        headers: {'ce-document': account},
      );
      expect(revokeStatus, 200, reason: '$revokeBody');
      expect((revokeBody! as Map)['rewritten'], 1);
      await _waitFor(
        tester,
        () => find
            .textContaining('Making past entries private')
            .evaluate()
            .isEmpty,
        'the unsharing line to go',
      );
      expect(
        await _partnerEntries(hid, partner.uid, partner.token, checking),
        0,
      );
    },
  );
}

/// One field write by the partner through Firestore REST, with the audit
/// stamps the rules require; returns the HTTP status.
Future<int> _partnerCommit(
  ({String uid, String token}) partner,
  String documentPath,
  String field,
  Map<String, Object?> value,
) async {
  const database = 'projects/$emulatorProjectId/databases/(default)';
  final (status, _) = await _send(
    'POST',
    Uri.parse('http://$_firestore/v1/$database/documents:commit'),
    headers: _bearer(partner.token),
    body: {
      'writes': [
        {
          'update': {
            'name': '$database/documents/$documentPath',
            'fields': {
              field: value,
              'updatedBy': {'stringValue': partner.uid},
            },
          },
          'updateMask': {
            'fieldPaths': [field, 'updatedBy'],
          },
          'updateTransforms': [
            {'fieldPath': 'updatedAt', 'setToServerValue': 'REQUEST_TIME'},
          ],
          'currentDocument': {'exists': true},
        },
      ],
    },
  );
  return status;
}

/// Writes four entries on [accountId] as the owner, through the rules, and
/// soft-deletes the [deletedNewest] newest of them (`rev` + 1, `deletedAt`).
Future<void> _ownerEntries(
  String hid,
  String owner,
  String accountId, {
  required int deletedNewest,
}) async {
  final transactions = FirebaseFirestore.instance.collection(
    'households/$hid/transactions',
  );
  final base = DateTime.utc(2026, 11, 1, 12);
  for (var i = 1; i <= 4; i++) {
    final ref = transactions.doc('$accountId-entry-$i');
    await ref.set({
      'type': 'expense',
      'amountMinor': 1000 * i,
      'currency': 'IQD',
      'accountId': accountId,
      'baseAmountMinor': i,
      'categoryId': null,
      'whoUid': owner,
      'whoScope': 'member',
      'occurredAt': Timestamp.fromDate(base.add(Duration(days: i))),
      'occurredOn': '2026-11-0${1 + i}',
      'title': 'Entry $i',
      'source': 'manual',
      'visibleTo': [owner],
      'deletedAt': null,
      'rev': 0,
      'createdAt': FieldValue.serverTimestamp(),
      'createdBy': owner,
      'updatedAt': FieldValue.serverTimestamp(),
      'updatedBy': owner,
      'schemaVersion': 1,
    });
    if (i > 4 - deletedNewest) {
      await ref.update({
        'deletedAt': FieldValue.serverTimestamp(),
        'rev': 1,
        'updatedAt': FieldValue.serverTimestamp(),
        'updatedBy': owner,
      });
    }
  }
}
