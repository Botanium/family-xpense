import 'dart:convert';

import 'package:clock/clock.dart';
import 'package:genkit/genkit.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';
import 'package:xpense_agent/config/server_env.dart';
import 'package:xpense_agent/xpense_server.dart';

import '../support/fakes.dart';

void main() {
  late Genkit ai;
  late FakeDocumentStore docs;

  setUp(() {
    ai = Genkit(isDevEnv: false, promptDir: null);
    docs = FakeDocumentStore()
      ..seedMember(uid: 'u1', hid: 'h1')
      ..seedMember(uid: 'u2', hid: 'h2', privacyMode: 'on_device');
  });

  tearDown(() => ai.shutdown());

  Handler serverFor(XpenseRole role) => XpenseServer.create(
    role: role,
    ai: ai,
    gateway: fakeGateway(documents: docs),
    clock: Clock.fixed(DateTime.utc(2026, 11, 22)),
  ).handler;

  Future<(int, Map<String, Object?>?, Response)> send(
    Handler handler,
    String method,
    String path, {
    Map<String, String> headers = const {},
    Object? body,
  }) async {
    final response = await handler(
      Request(
        method,
        Uri.parse('http://localhost$path'),
        headers: {'content-type': 'application/json', ...headers},
        body: body == null ? null : jsonEncode(body),
      ),
    );
    final text = await response.readAsString();
    final json = text.startsWith('{')
        ? jsonDecode(text) as Map<String, Object?>
        : null;
    return (response.statusCode, json, response);
  }

  group('agent role', () {
    late Handler handler;
    setUp(() => handler = serverFor(XpenseRole.agent));

    for (final path in ['/healthz', '/health']) {
      test('GET $path is 200 without auth', () async {
        final (status, json, response) = await send(handler, 'GET', path);
        expect(status, 200);
        expect(json, {'status': 'ok', 'role': 'agent'});
        expect(response.headers['cache-control'], 'no-store');
      });
    }

    test('POST /healthz is 405', () async {
      final (status, _, _) = await send(handler, 'POST', '/healthz');
      expect(status, 405);
    });

    test('POST /v1/ping without tokens is 401 missing_id_token', () async {
      final (status, json, _) = await send(
        handler,
        'POST',
        '/v1/ping',
        body: {'data': 'hi'},
      );
      expect(status, 401);
      expect(json, {
        'code': 401,
        'status': 'UNAUTHENTICATED',
        'message': 'missing_id_token',
      });
    });

    test('POST /v1/ping with an ID token but no App Check is 401', () async {
      final (status, json, _) = await send(
        handler,
        'POST',
        '/v1/ping',
        headers: {'authorization': 'Bearer token-u1'},
        body: {'data': 'hi'},
      );
      expect(status, 401);
      expect(json?['message'], 'missing_app_check');
    });

    test('POST /v1/ping with valid tokens returns the context', () async {
      final (status, json, _) = await send(
        handler,
        'POST',
        '/v1/ping',
        headers: headersFor('u1'),
        body: {'data': 'hi'},
      );
      expect(status, 200);
      expect(json, {
        'result': {
          'status': 'ok',
          'echo': 'hi',
          'uid': 'u1',
          'hid': 'h1',
          'locale': 'en',
          'privacyMode': 'smart',
          'tz': 'Asia/Baghdad',
        },
      });
    });

    test('ping without input', () async {
      final (status, json, _) = await send(
        handler,
        'POST',
        '/v1/ping',
        headers: headersFor('u1'),
        body: {'data': null},
      );
      expect(status, 200);
      expect((json!['result']! as Map)['echo'], isNull);
    });

    test('On-device member gets 403 on_device_mode', () async {
      final (status, json, _) = await send(
        handler,
        'POST',
        '/v1/ping',
        headers: headersFor('u2'),
        body: {'data': 'hi'},
      );
      expect(status, 403);
      expect(json?['message'], 'on_device_mode');
    });

    test('streaming requests are authorised the same way', () async {
      final (status, json, _) = await send(
        handler,
        'POST',
        '/v1/ping?stream=true',
        body: {'data': 'hi'},
      );
      expect(status, 401);
      expect(json?['message'], 'missing_id_token');
    });

    test('routes are only served under /v1', () async {
      for (final path in ['/ping', '/v2/ping', '/v1', '/v1/', '/v1ping']) {
        final (status, _, _) = await send(
          handler,
          'POST',
          path,
          headers: headersFor('u1'),
          body: {'data': 'hi'},
        );
        expect(status, 404, reason: path);
      }
    });

    test('jobs routes are not served by the agent role', () async {
      final (status, _, _) = await send(handler, 'POST', '/jobs/recurring');
      expect(status, 404);
    });

    test('GET on an action is 405', () async {
      final (status, _, _) = await send(handler, 'GET', '/v1/ping');
      expect(status, 405);
    });

    test('no CORS headers are sent', () async {
      final (_, _, response) = await send(
        handler,
        'OPTIONS',
        '/v1/ping',
        headers: {
          'origin': 'https://evil.example',
          'access-control-request-method': 'POST',
        },
      );
      expect(
        response.headers.keys,
        isNot(contains('access-control-allow-origin')),
      );
    });
  });

  group('jobs role', () {
    late Handler handler;
    setUp(() => handler = serverFor(XpenseRole.jobs));

    test('health is served', () async {
      final (status, json, _) = await send(handler, 'GET', '/healthz');
      expect(status, 200);
      expect(json, {'status': 'ok', 'role': 'jobs'});
    });

    test('public routes are not served by the jobs role', () async {
      final (status, _, _) = await send(
        handler,
        'POST',
        '/v1/ping',
        headers: headersFor('u1'),
        body: {'data': 'hi'},
      );
      expect(status, 404);
    });
  });
}
