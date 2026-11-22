// End-to-end checks of the real Firebase gateway against the Auth and
// Firestore emulators (project `demo-xpense`). App Check cannot be emulated,
// so it is replaced by the fake verifier. Run with tool/test_emulators.sh.
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
import 'package:xpense_agent/auth/auth_failure.dart';
import 'package:xpense_agent/config/server_env.dart';
import 'package:xpense_agent/telemetry/usage_counters.dart';
import 'package:xpense_agent/xpense_server.dart';

import '../support/fakes.dart';

const projectId = 'demo-xpense';

final String? authHost = Platform.environment['FIREBASE_AUTH_EMULATOR_HOST'];
final String? firestoreHost = Platform.environment['FIRESTORE_EMULATOR_HOST'];

final Object? skipReason = authHost == null || firestoreHost == null
    ? 'needs the Auth and Firestore emulators (tool/test_emulators.sh)'
    : null;

/// A user created in the Auth emulator.
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

Future<void> adminAuth(String action, Map<String, Object?> body) async {
  final response = await http.post(
    Uri.http(
      authHost!,
      '/identitytoolkit.googleapis.com/v1/projects/$projectId/accounts:$action',
    ),
    headers: {
      'content-type': 'application/json',
      'authorization': 'Bearer owner',
    },
    body: jsonEncode(body),
  );
  expect(response.statusCode, 200, reason: response.body);
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
  group('with the emulators', _emulatorTests, skip: skipReason);
}

void _emulatorTests() {
  late FirebaseAdminGateway admin;
  late AdminGateway gateway;
  var appCount = 0;

  setUp(() async {
    await clearEmulators();
    admin = FirebaseAdminGateway.initialize(
      projectId: projectId,
      appCheckOverride: FakeAppCheckVerifier(),
      appName: 'emulator-test-${appCount++}',
    );
    gateway = admin.gateway;
  });

  tearDown(() => gateway.close());

  Future<void> seedHousehold(
    String uid,
    String hid, {
    String privacyMode = 'smart',
  }) async {
    final docs = gateway.documents;
    await docs.write('users/$uid', {'householdId': hid, 'locale': 'en'});
    await docs.write('households/$hid', {
      'memberIds': [uid],
      'timeZone': 'Asia/Baghdad',
      'baseCurrency': 'USD',
    });
    await docs.write('households/$hid/members/$uid', {
      'role': 'owner',
      'privacyMode': privacyMode,
    });
  }

  group('ID tokens (Auth emulator)', () {
    test('a fresh emulator token verifies to its uid', () async {
      final user = await signUp('a@example.test');
      final verified = await gateway.idTokens.verifyIdToken(user.idToken);
      expect(verified.uid, user.uid);
    });

    test('garbage is rejected', () async {
      await expectLater(
        gateway.idTokens.verifyIdToken('not-a-jwt'),
        throwsA(isA<TokenRejected>()),
      );
    });

    test('a disabled user is rejected', () async {
      final user = await signUp('b@example.test');
      await adminAuth('update', {'localId': user.uid, 'disableUser': true});
      await expectLater(
        gateway.idTokens.verifyIdToken(user.idToken),
        throwsA(isA<TokenRejected>()),
      );
    });

    test('a deleted user is rejected', () async {
      final user = await signUp('c@example.test');
      await adminAuth('delete', {'localId': user.uid});
      await expectLater(
        gateway.idTokens.verifyIdToken(user.idToken),
        throwsA(isA<TokenRejected>()),
      );
    });
  });

  group('documents (Firestore emulator)', () {
    test('write, read and a missing document', () async {
      final at = DateTime.utc(2026, 11, 22, 8, 30);
      await gateway.documents.write('config/runtime', {
        'limits': {'images': 3},
        'switches': {'liteOnly': true},
        'at': at,
        'ids': ['a', 'b'],
      });
      final doc = await gateway.documents.read('config/runtime');
      expect(doc, {
        'limits': {'images': 3},
        'switches': {'liteOnly': true},
        'at': at,
        'ids': ['a', 'b'],
      });
      expect(await gateway.documents.read('config/missing'), isNull);
    });

    test('merge keeps other fields', () async {
      await gateway.documents.write('users/u1', {'a': 1, 'b': 2});
      await gateway.documents.write('users/u1', {'b': 3}, merge: true);
      expect(await gateway.documents.read('users/u1'), {'a': 1, 'b': 3});
    });

    test('concurrent increments are atomic', () async {
      final usage = UsageCounters(gateway.documents);
      await Future.wait([
        for (var i = 0; i < 20; i++)
          usage.add('h1', {UsageCounter.agentTurns: 1, UsageCounter.images: 2}),
      ]);
      final today = await usage.today('h1');
      expect(today[UsageCounter.agentTurns], 20);
      expect(today[UsageCounter.images], 40);
    });
  });

  group('context provider end to end', () {
    late XpenseServer server;

    setUp(() {
      server = XpenseServer.create(
        role: XpenseRole.agent,
        ai: Genkit(isDevEnv: false, promptDir: null),
        gateway: gateway,
        projectId: projectId,
      );
    });

    Map<String, String> headers(String idToken) => {
      'authorization': 'Bearer $idToken',
      'x-firebase-appcheck': 'app-ok',
    };

    Future<void> expectRefused(Future<Object?> call, AuthFailure failure) =>
        expectLater(
          call,
          throwsA(
            isA<GenkitException>().having(
              (e) => e.message,
              'code',
              failure.code,
            ),
          ),
        );

    test('a member gets {uid, hid, locale, privacyMode, tz}', () async {
      final user = await signUp('owner@example.test');
      await seedHousehold(user.uid, 'h1');
      expect(await server.auth.resolve(headers(user.idToken)), {
        'uid': user.uid,
        'hid': 'h1',
        'locale': 'en',
        'privacyMode': 'smart',
        'tz': 'Asia/Baghdad',
      });
    });

    test('a signed-in user without a household is refused', () async {
      final user = await signUp('new@example.test');
      await expectRefused(
        server.auth.resolve(headers(user.idToken)),
        AuthFailure.noHousehold,
      );
    });

    test('an On-device member is refused', () async {
      final user = await signUp('private@example.test');
      await seedHousehold(user.uid, 'h2', privacyMode: 'on_device');
      await expectRefused(
        server.auth.resolve(headers(user.idToken)),
        AuthFailure.onDeviceMode,
      );
    });

    test('limits from config/runtime and counters in Firestore', () async {
      final user = await signUp('busy@example.test');
      await seedHousehold(user.uid, 'h3');
      await gateway.documents.write('config/runtime', {
        'limits': {'agentTurns': 2},
      });
      final meters = {UsageCounter.agentTurns};
      await server.usage.add('h3', {UsageCounter.agentTurns: 1});
      await server.auth.resolve(headers(user.idToken), meters: meters);
      await server.usage.add('h3', {UsageCounter.agentTurns: 1});
      await expectRefused(
        server.auth.resolve(headers(user.idToken), meters: meters),
        AuthFailure.overLimit,
      );
    });

    test('a disabled user is refused even with a cached member', () async {
      final user = await signUp('gone@example.test');
      await seedHousehold(user.uid, 'h4');
      await server.auth.resolve(headers(user.idToken));
      await adminAuth('update', {'localId': user.uid, 'disableUser': true});
      await expectRefused(
        server.auth.resolve(headers(user.idToken)),
        AuthFailure.invalidIdToken,
      );
    });

    test('POST /v1/ping over HTTP', () async {
      final user = await signUp('ping@example.test');
      await seedHousehold(user.uid, 'h5');
      Future<Response> ping(Map<String, String> headers) async =>
          await server.handler(
            Request(
              'POST',
              Uri.parse('http://localhost/v1/ping'),
              headers: {'content-type': 'application/json', ...headers},
              body: jsonEncode({'data': 'hello'}),
            ),
          );

      final ok = await ping(headers(user.idToken));
      expect(ok.statusCode, 200);
      final body = jsonDecode(await ok.readAsString()) as Map<String, Object?>;
      expect(body['result'], containsPair('uid', user.uid));
      expect(body['result'], containsPair('hid', 'h5'));

      final anonymous = await ping(const {});
      expect(anonymous.statusCode, 401);
    });
  });
}
