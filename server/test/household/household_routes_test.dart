// The household routes over HTTP, through the real handler, context
// provider and flows, on the fake gateway.
import 'dart:convert';

import 'package:clock/clock.dart';
import 'package:genkit/genkit.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';
import 'package:xpense_agent/config/server_env.dart';
import 'package:xpense_agent/household/invite_code.dart';
import 'package:xpense_agent/xpense_server.dart';

import '../support/fakes.dart';

void main() {
  late Genkit ai;
  late FakeDocumentStore docs;
  late Handler handler;

  setUp(() {
    ai = Genkit(isDevEnv: false, promptDir: null);
    docs = FakeDocumentStore()
      ..seedMember(uid: 'owner', hid: 'h1')
      ..seedMember(uid: 'private', hid: 'h2', privacyMode: 'on_device');
    docs.docs['households/h1']!['name'] = 'Our home';
    handler = XpenseServer.create(
      role: XpenseRole.agent,
      ai: ai,
      gateway: fakeGateway(documents: docs),
      clock: Clock.fixed(DateTime.utc(2026, 11, 22, 9)),
    ).handler;
  });

  tearDown(() => ai.shutdown());

  Future<(int, Map<String, Object?>)> post(
    String path, {
    String? uid,
    Object? data,
  }) async {
    final response = await handler(
      Request(
        'POST',
        Uri.parse('http://localhost/v1$path'),
        headers: {
          'content-type': 'application/json',
          if (uid != null) ...headersFor(uid),
        },
        body: jsonEncode({'data': data}),
      ),
    );
    final body =
        jsonDecode(await response.readAsString()) as Map<String, Object?>;
    return (response.statusCode, body);
  }

  Future<String> invite(String uid) async {
    final (status, body) = await post('/household/invite', uid: uid);
    expect(status, 200, reason: '$body');
    return (body['result']! as Map<String, Object?>)['code']! as String;
  }

  group('POST /v1/household/invite', () {
    test('a member gets {code, link, expiresAt}', () async {
      final (status, body) = await post('/household/invite', uid: 'owner');
      expect(status, 200);
      final result = body['result']! as Map<String, Object?>;
      final code = result['code']! as String;
      expect(normalizeInviteCode(code), code);
      expect(result['link'], 'xpense://join?code=$code');
      expect(result['expiresAt'], '2026-11-29T09:00:00.000Z');
    });

    test('an On-device member may invite (no AI involved)', () async {
      final (status, _) = await post('/household/invite', uid: 'private');
      expect(status, 200);
    });

    test('needs both tokens and a household', () async {
      final (anonymous, body) = await post('/household/invite');
      expect(anonymous, 401);
      expect(body['message'], 'missing_id_token');

      final (stranger, strangerBody) = await post(
        '/household/invite',
        uid: 'stranger',
      );
      expect(stranger, 403);
      expect(strangerBody['message'], 'no_household');
    });
  });

  group('POST /v1/household/join', () {
    test('a signed-in user without a household joins', () async {
      final code = await invite('owner');
      final (status, body) = await post(
        '/household/join',
        uid: 'partner',
        data: {'code': code, 'displayName': 'Sam'},
      );
      expect(status, 200, reason: '$body');
      expect(body['result'], {
        'householdId': 'h1',
        'householdName': 'Our home',
      });

      // The new member is a member at once: the provider resolves them.
      final (pingStatus, ping) = await post('/ping', uid: 'partner');
      expect(pingStatus, 200);
      expect(ping['result'], containsPair('hid', 'h1'));
    });

    test('the third person is refused', () async {
      final code = await invite('owner');
      await post(
        '/household/join',
        uid: 'partner',
        data: {'code': code, 'displayName': 'Sam'},
      );
      final (status, body) = await post(
        '/household/join',
        uid: 'third',
        data: {'code': code, 'displayName': 'Kim'},
      );
      expect(status, 400);
      expect(body['message'], 'invite_used');

      // And the household cannot make another invite.
      final (inviteStatus, inviteBody) = await post(
        '/household/invite',
        uid: 'owner',
      );
      expect(inviteStatus, 400);
      expect(inviteBody['message'], 'household_full');
    });

    test('codes the household never issued are 404 invite_invalid', () async {
      final (status, body) = await post(
        '/household/join',
        uid: 'partner',
        data: {'code': 'ZZZZZ-ZZZZZ', 'displayName': 'Sam'},
      );
      expect(status, 404);
      expect(body, {
        'code': 404,
        'status': 'NOT_FOUND',
        'message': 'invite_invalid',
      });
    });

    test('a missing field is 400 invalid_input', () async {
      final (status, body) = await post(
        '/household/join',
        uid: 'partner',
        data: {'code': 'ZZZZZZZZZZ'},
      );
      expect(status, 400);
      expect(body['message'], 'invalid_input');
    });

    test('the eleventh attempt in an hour is 429 rate_limited', () async {
      for (var i = 0; i < 10; i++) {
        await post(
          '/household/join',
          uid: 'guesser',
          data: {'code': 'ZZZZZZZZZZ', 'displayName': 'X'},
        );
      }
      final (status, body) = await post(
        '/household/join',
        uid: 'guesser',
        data: {'code': 'ZZZZZZZZZZ', 'displayName': 'X'},
      );
      expect(status, 429);
      expect(body['message'], 'rate_limited');
    });

    test('needs both tokens', () async {
      final (status, body) = await post(
        '/household/join',
        data: {'code': 'ZZZZZZZZZZ', 'displayName': 'X'},
      );
      expect(status, 401);
      expect(body['message'], 'missing_id_token');
    });
  });
}
