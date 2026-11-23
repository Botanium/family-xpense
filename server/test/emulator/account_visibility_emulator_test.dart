// The account-visibility backfill against the Firestore emulator (project
// `demo-xpense`): real count aggregation, document-id paging, batches and
// transactions; and the join hook that widens joint accounts. Run with
// tool/test_emulators.sh.
@Tags(['emulator'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:genkit/genkit.dart';
import 'package:http/http.dart' as http;
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';
import 'package:xpense_agent/admin/admin_gateway.dart';
import 'package:xpense_agent/admin/firebase_admin_gateway.dart';
import 'package:xpense_agent/config/server_env.dart';
import 'package:xpense_agent/jobs/account_visibility.dart';
import 'package:xpense_agent/xpense_server.dart';

import '../support/fakes.dart';

const projectId = 'demo-xpense';

final String? authHost = Platform.environment['FIREBASE_AUTH_EMULATOR_HOST'];
final String? firestoreHost = Platform.environment['FIRESTORE_EMULATOR_HOST'];

final Object? skipReason = authHost == null || firestoreHost == null
    ? 'needs the Auth and Firestore emulators (tool/test_emulators.sh)'
    : null;

Future<void> clearEmulators() async {
  await http.delete(
    Uri.http(
      firestoreHost!,
      '/emulator/v1/projects/$projectId/databases/(default)/documents',
    ),
  );
  await http.delete(
    Uri.http(authHost!, '/emulator/v1/projects/$projectId/accounts'),
  );
}

Future<({String uid, String idToken})> signUp(String email) async {
  final response = await http.post(
    Uri.http(authHost!, '/identitytoolkit.googleapis.com/v1/accounts:signUp', {
      'key': 'fake-api-key',
    }),
    headers: {'content-type': 'application/json'},
    body: jsonEncode({
      'email': email,
      'password': 'emulator-only-password',
      'returnSecureToken': true,
    }),
  );
  final json = jsonDecode(response.body) as Map<String, Object?>;
  return (uid: json['localId']! as String, idToken: json['idToken']! as String);
}

void main() {
  group('account visibility with the emulators', _tests, skip: skipReason);
}

void _tests() {
  late AdminGateway gateway;
  late DocumentStore docs;
  late Genkit ai;
  var appCount = 0;

  setUp(() async {
    await clearEmulators();
    gateway = FirebaseAdminGateway.initialize(
      projectId: projectId,
      appCheckOverride: FakeAppCheckVerifier(),
      appName: 'visibility-emulator-${appCount++}',
    ).gateway;
    docs = gateway.documents;
    ai = Genkit(isDevEnv: false, promptDir: null);
  });

  tearDown(() async {
    await ai.shutdown();
    await gateway.close();
  });

  List<String> sorted(Object? list) =>
      (list! as List).cast<String>().toList()..sort();

  test('sharing, then unsharing, rewrites every page of history', () async {
    const hid = 'h1';
    await docs.write('households/$hid', {
      'memberIds': ['a', 'b'],
    });
    await docs.write('households/$hid/accounts/chk', {
      'scope': 'personal',
      'ownerUid': 'a',
      'sharedWithPartner': true,
      'visibleTo': ['a', 'b'],
      'visibilityAppliedTo': ['a'],
    });
    await docs.write('households/$hid/accounts/joint', {
      'scope': 'joint',
      'visibleTo': ['a', 'b'],
    });
    for (var i = 0; i < 7; i++) {
      await docs.write('households/$hid/transactions/t$i', {
        'accountId': 'chk',
        'visibleTo': ['a'],
        'rev': 0,
      });
    }
    await docs.write('households/$hid/transactions/x', {
      'accountId': 'chk',
      'toAccountId': 'joint',
      'visibleTo': ['a', 'b'],
      'rev': 0,
    });

    final job = AccountVisibilityJob(docs, pageSize: 3);
    final shared = await job.sync(hid, 'chk');
    expect(shared.outcome, VisibilityOutcome.synced);
    expect(shared.rewritten, 7);
    for (var i = 0; i < 7; i++) {
      final t = await docs.read('households/$hid/transactions/t$i');
      expect(sorted(t!['visibleTo']), ['a', 'b']);
    }
    final account = await docs.read('households/$hid/accounts/chk');
    expect(account!['visibilityAppliedTo'], ['a', 'b']);
    expect(account['visibilitySync'], isNull);

    // The owner turns it off.
    await docs.write('households/$hid/accounts/chk', {
      'sharedWithPartner': false,
      'visibleTo': ['a'],
    }, merge: true);
    final private = await job.sync(hid, 'chk');
    expect(private.rewritten, 7);
    final t0 = await docs.read('households/$hid/transactions/t0');
    expect(t0!['visibleTo'], ['a']);
    // Into a joint account: both still see it.
    final x = await docs.read('households/$hid/transactions/x');
    expect(sorted(x!['visibleTo']), ['a', 'b']);
  });

  test('joining widens joint accounts and their history', () async {
    final owner = await signUp('vis-owner@example.test');
    final partner = await signUp('vis-partner@example.test');
    const hid = 'h2';
    await docs.write('households/$hid', {
      'name': 'Our home',
      'baseCurrency': 'USD',
      'timeZone': 'Asia/Baghdad',
      'memberIds': [owner.uid],
      'moneySchema': 1,
    });
    await docs.write('households/$hid/members/${owner.uid}', {
      'displayName': 'Alex',
      'role': 'owner',
      'privacyMode': 'smart',
    });
    await docs.write('users/${owner.uid}', {'householdId': hid});
    await docs.write('households/$hid/accounts/visa', {
      'scope': 'joint',
      'visibleTo': [owner.uid],
    });
    await docs.write('households/$hid/accounts/wallet', {
      'scope': 'personal',
      'ownerUid': owner.uid,
      'sharedWithPartner': false,
      'visibleTo': [owner.uid],
    });
    await docs.write('households/$hid/transactions/opening', {
      'accountId': 'visa',
      'visibleTo': [owner.uid],
      'rev': 0,
    });

    final handler = XpenseServer.create(
      role: XpenseRole.agent,
      ai: ai,
      gateway: gateway,
      projectId: projectId,
    ).handler;
    Future<Map<String, Object?>> post(
      String path,
      String token,
      Object? data,
    ) =>
        Future.value(
          handler(
            Request(
              'POST',
              Uri.parse('http://localhost/v1$path'),
              headers: {
                'content-type': 'application/json',
                'authorization': 'Bearer $token',
                'x-firebase-appcheck': 'app-ok',
              },
              body: jsonEncode({'data': data}),
            ),
          ),
        ).then(
          (r) async =>
              jsonDecode(await r.readAsString()) as Map<String, Object?>,
        );

    final invite = await post('/household/invite', owner.idToken, null);
    final code = (invite['result']! as Map<String, Object?>)['code'];
    final joined = await post('/household/join', partner.idToken, {
      'code': code,
      'displayName': 'Sam',
    });
    expect(joined['result'], isNotNull, reason: '$joined');

    final visa = await docs.read('households/$hid/accounts/visa');
    expect(sorted(visa!['visibleTo']), sorted([owner.uid, partner.uid]));
    final opening = await docs.read('households/$hid/transactions/opening');
    expect(sorted(opening!['visibleTo']), sorted([owner.uid, partner.uid]));
    final wallet = await docs.read('households/$hid/accounts/wallet');
    expect(wallet!['visibleTo'], [owner.uid]);
  });
}
