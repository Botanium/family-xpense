// Invite and join end to end against the Auth and Firestore emulators
// (project `demo-xpense`): real ID tokens, the real Firebase gateway and
// real Firestore transactions. App Check cannot be emulated, so the fake
// verifier stands in. Run with tool/test_emulators.sh.
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
import 'package:xpense_agent/household/invite_code.dart';
import 'package:xpense_agent/household/rate_limiter.dart';
import 'package:xpense_agent/xpense_server.dart';

import '../support/fakes.dart';

const projectId = 'demo-xpense';

final String? authHost = Platform.environment['FIREBASE_AUTH_EMULATOR_HOST'];
final String? firestoreHost = Platform.environment['FIRESTORE_EMULATOR_HOST'];

final Object? skipReason = authHost == null || firestoreHost == null
    ? 'needs the Auth and Firestore emulators (tool/test_emulators.sh)'
    : null;

typedef EmulatorUser = ({String uid, String idToken});

Future<EmulatorUser> signUp(String email) async {
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
  expect(response.statusCode, 200, reason: response.body);
  final json = jsonDecode(response.body) as Map<String, Object?>;
  return (uid: json['localId']! as String, idToken: json['idToken']! as String);
}

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

void main() {
  group('household flows with the emulators', _tests, skip: skipReason);
}

void _tests() {
  late FirebaseAdminGateway admin;
  late AdminGateway gateway;
  late Genkit ai;
  late Handler handler;
  var appCount = 0;

  setUp(() async {
    await clearEmulators();
    admin = FirebaseAdminGateway.initialize(
      projectId: projectId,
      appCheckOverride: FakeAppCheckVerifier(),
      appName: 'household-emulator-${appCount++}',
    );
    gateway = admin.gateway;
    ai = Genkit(isDevEnv: false, promptDir: null);
    handler = XpenseServer.create(
      role: XpenseRole.agent,
      ai: ai,
      gateway: gateway,
      projectId: projectId,
    ).handler;
  });

  tearDown(() async {
    await ai.shutdown();
    await gateway.close();
  });

  /// What the phone's founding batch leaves (the rules test covers the batch
  /// itself; the server sees only the result).
  Future<void> foundHousehold(String uid, String hid) async {
    final docs = gateway.documents;
    await docs.write('households/$hid', {
      'name': 'Our home',
      'baseCurrency': 'USD',
      'timeZone': 'Asia/Baghdad',
      'memberIds': [uid],
      'moneySchema': 1,
    });
    await docs.write('households/$hid/members/$uid', {
      'displayName': 'Alex',
      'initial': 'A',
      'role': 'owner',
      'privacyMode': 'smart',
    });
    await docs.write('users/$uid', {'householdId': hid, 'locale': 'en'});
  }

  Future<(int, Map<String, Object?>)> post(
    String path,
    EmulatorUser user, [
    Object? data,
  ]) async {
    final response = await handler(
      Request(
        'POST',
        Uri.parse('http://localhost/v1$path'),
        headers: {
          'content-type': 'application/json',
          'authorization': 'Bearer ${user.idToken}',
          'x-firebase-appcheck': 'app-ok',
        },
        body: jsonEncode({'data': data}),
      ),
    );
    return (
      response.statusCode,
      jsonDecode(await response.readAsString()) as Map<String, Object?>,
    );
  }

  Future<String> invite(EmulatorUser user) async {
    final (status, body) = await post('/household/invite', user);
    expect(status, 200, reason: '$body');
    return (body['result']! as Map<String, Object?>)['code']! as String;
  }

  Future<(int, Map<String, Object?>)> join(
    EmulatorUser user,
    String code, [
    String name = 'Sam',
  ]) => post('/household/join', user, {'code': code, 'displayName': name});

  test('the owner invites, the partner joins, a third is refused', () async {
    final owner = await signUp('owner@example.test');
    final partner = await signUp('partner@example.test');
    final third = await signUp('third@example.test');
    await foundHousehold(owner.uid, 'h1');

    final code = await invite(owner);
    final invitePath = 'invites/${inviteCodeHash(code)}';
    final stored = await gateway.documents.read(invitePath);
    expect(stored, containsPair('hid', 'h1'));
    expect(stored, containsPair('usedBy', null));
    expect(jsonEncode(stored.toString()), isNot(contains(code)));

    final (status, body) = await join(partner, code);
    expect(status, 200, reason: '$body');
    expect(body['result'], {'householdId': 'h1', 'householdName': 'Our home'});

    final household = await gateway.documents.read('households/h1');
    expect(household!['memberIds'], [owner.uid, partner.uid]);
    final member = await gateway.documents.read(
      'households/h1/members/${partner.uid}',
    );
    expect(member, containsPair('role', 'partner'));
    expect(member, containsPair('displayName', 'Sam'));
    expect(member!['joinedAt'], isA<DateTime>());
    expect(
      await gateway.documents.read('users/${partner.uid}'),
      containsPair('householdId', 'h1'),
    );
    expect(
      await gateway.documents.read(invitePath),
      containsPair('usedBy', partner.uid),
    );

    // The partner is now a member for every route.
    final (pingStatus, _) = await post('/ping', partner, 'hi');
    expect(pingStatus, 200);

    // Single use, and the household is full.
    final (thirdStatus, thirdBody) = await join(third, code, 'Kim');
    expect(thirdStatus, 400);
    expect(thirdBody['message'], 'invite_used');
    final (fullStatus, fullBody) = await post('/household/invite', owner);
    expect(fullStatus, 400);
    expect(fullBody['message'], 'household_full');
  });

  test('a member elsewhere who cleared their pointer is refused', () async {
    final owner = await signUp('pointer-owner@example.test');
    final other = await signUp('pointer-other@example.test');
    await foundHousehold(owner.uid, 'h6');
    await foundHousehold(other.uid, 'h7');
    // users/{uid} is the user's own to write (firestore.rules).
    await gateway.documents.write('users/${other.uid}', {'locale': 'en'});
    final code = await invite(owner);

    final (status, body) = await join(other, code);
    expect(status, 400, reason: '$body');
    expect(body['message'], 'already_in_household');
    final household = await gateway.documents.read('households/h6');
    expect(household!['memberIds'], [owner.uid]);
  });

  test('two people racing with one code: exactly one gets in', () async {
    final owner = await signUp('race-owner@example.test');
    final a = await signUp('a@example.test');
    final b = await signUp('b@example.test');
    await foundHousehold(owner.uid, 'h2');
    final code = await invite(owner);

    final results = await Future.wait([join(a, code, 'A'), join(b, code, 'B')]);
    final statuses = results.map((r) => r.$1).toList()..sort();
    expect(statuses, [200, 400], reason: '$results');
    final household = await gateway.documents.read('households/h2');
    expect(household!['memberIds'], hasLength(2));
  });

  test('a new invite revokes the unused one', () async {
    final owner = await signUp('revoke@example.test');
    final partner = await signUp('late@example.test');
    await foundHousehold(owner.uid, 'h3');
    final first = await invite(owner);
    final second = await invite(owner);

    expect(
      await gateway.documents.read('invites/${inviteCodeHash(first)}'),
      isNull,
    );
    final (status, body) = await join(partner, first);
    expect(status, 404);
    expect(body['message'], 'invite_invalid');
    final (ok, _) = await join(partner, second);
    expect(ok, 200);
  });

  test('join attempts are rate limited per user in Firestore', () async {
    final guesser = await signUp('guesser@example.test');
    for (var i = 0; i < 10; i++) {
      final (status, _) = await join(guesser, 'ZZZZZZZZZZ');
      expect(status, 404);
    }
    final (status, body) = await join(guesser, 'ZZZZZZZZZZ');
    expect(status, 429);
    expect(body['message'], 'rate_limited');
    final limits = await gateway.documents.read(
      RateLimiter.pathFor(guesser.uid),
    );
    expect(
      limits![LimitedAction.householdJoin.field],
      containsPair('count', 10),
    );
  });
}
