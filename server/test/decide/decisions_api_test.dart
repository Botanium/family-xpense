import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:test/test.dart';
import 'package:xpense_agent/decide/decisions_api.dart';

import 'support.dart';

/// Keys for tests: [refreshed] is returned once by `refresh`.
final class TestKeys implements ApiKeySource {
  new(this.key, {this.refreshed});

  String key;
  String? refreshed;
  int refreshes = 0;

  @override
  String current() => key;

  @override
  String? refresh() {
    refreshes++;
    final next = refreshed;
    if (next != null) key = next;
    return next;
  }
}

const Map<String, Object?> _body = {
  'model': 'gemini-decision-1',
  'input': 'Message: """Lunch 15,000"""',
  'questions': <String, Object?>{},
};

void main() {
  group('classifyResponse', () {
    test('200 with answers and usage', () {
      final o = classifyResponse(
        200,
        answeredBody({'intent': choice('expense', 0.98)}, inputTokens: 2007),
      );
      expect(o, isA<DecisionAnswered>());
      o as DecisionAnswered;
      expect(o.inputTokens, 2007);
      expect(o.answers.keys, ['intent']);
    });

    test('200 with prompt_feedback.block_reason is a block', () {
      final o = classifyResponse(
        200,
        jsonEncode({
          'answers': <String, Object?>{},
          'prompt_feedback': {'block_reason': 'SAFETY'},
        }),
      );
      expect(
        o,
        isA<DecisionBlocked>().having((b) => b.reason, 'reason', 'SAFETY'),
      );
    });

    for (final code in safetyCodes) {
      test('400 with string code "$code" is a block', () {
        final o = classifyResponse(400, decisionsError(code, 'blocked'));
        expect(
          o,
          isA<DecisionBlocked>().having((b) => b.reason, 'reason', code),
        );
      });
    }

    test('400 invalid_request is a request error, not a block', () {
      final o = classifyResponse(
        400,
        decisionsError(
          'invalid_request',
          "Unknown parameter 'generationConfig'",
        ),
      );
      expect(
        o,
        isA<DecisionRequestRejected>()
            .having((r) => r.code, 'code', 'invalid_request')
            .having((r) => r.message, 'message', contains('Unknown parameter')),
      );
    });

    test('404 not_found (unknown model) is a request error', () {
      final o = classifyResponse(404, decisionsError('not_found', 'model'));
      expect(o, isA<DecisionRequestRejected>());
    });

    test(
      "Google's 400 INVALID_ARGUMENT 'API key not valid' is a key error",
      () {
        final o = classifyResponse(
          400,
          googleError(
            400,
            'INVALID_ARGUMENT',
            'API key not valid. Please pass a valid API key.',
          ),
        );
        expect(o, isA<DecisionKeyRejected>());
      },
    );

    test("Google's 403 PERMISSION_DENIED is a key error", () {
      final o = classifyResponse(
        403,
        googleError(
          403,
          'PERMISSION_DENIED',
          'Permission denied on the service',
        ),
      );
      expect(
        o,
        isA<DecisionKeyRejected>().having(
          (k) => k.statusText,
          'statusText',
          'PERMISSION_DENIED',
        ),
      );
    });

    test(
      "Google's 400 INVALID_ARGUMENT about something else is unexpected",
      () {
        final o = classifyResponse(
          400,
          googleError(
            400,
            'INVALID_ARGUMENT',
            'Request contains an invalid argument.',
          ),
        );
        expect(o, isA<DecisionUnexpected>());
      },
    );

    test('429 RESOURCE_EXHAUSTED and 5xx are transient', () {
      expect(
        classifyResponse(429, googleError(429, 'RESOURCE_EXHAUSTED', 'quota')),
        isA<DecisionTransient>().having(
          (t) => t.detail,
          'detail',
          'RESOURCE_EXHAUSTED',
        ),
      );
      expect(classifyResponse(500, 'oops'), isA<DecisionTransient>());
      expect(
        classifyResponse(503, googleError(503, 'UNAVAILABLE', 'overloaded')),
        isA<DecisionTransient>(),
      );
      expect(
        classifyResponse(429, decisionsError('rate_limited', 'slow down')),
        isA<DecisionTransient>(),
      );
    });

    test('a 400 numeric safety-looking code is never a block', () {
      // Only a string code from the safety list blocks.
      final o = classifyResponse(
        400,
        jsonEncode({
          'error': {
            'code': 400,
            'status': 'INVALID_ARGUMENT',
            'message': 'safety',
          },
        }),
      );
      expect(o, isNot(isA<DecisionBlocked>()));
    });

    test('a 200 without answers or with a non-JSON body is unexpected', () {
      expect(classifyResponse(200, '{}'), isA<DecisionUnexpected>());
      expect(classifyResponse(200, '<html>'), isA<DecisionUnexpected>());
      expect(classifyResponse(418, ''), isA<DecisionUnexpected>());
    });
  });

  group('DecisionsApi.send', () {
    test('posts the body as is with the key in the header only', () async {
      final net = ScriptedHttp([
        httpResponse(200, answeredBody({'intent': choice('expense', 0.9)})),
      ]);
      final api = DecisionsApi(http: net.client, keys: TestKeys('k-1'));
      final o = await api.send(_body);
      expect(o, isA<DecisionAnswered>());
      final request = net.requests.single;
      expect(request.url, decisionsEndpoint);
      expect(request.headers['x-goog-api-key'], 'k-1');
      expect(request.headers['content-type'], startsWith('application/json'));
      expect(net.bodyOf(0), _body);
      expect(request.body, isNot(contains('k-1')));
      expect(request.url.query, isEmpty);
    });

    test('a key error re-reads the key once and retries', () async {
      final net = ScriptedHttp([
        httpResponse(
          400,
          googleError(400, 'INVALID_ARGUMENT', 'API key not valid.'),
        ),
        httpResponse(200, answeredBody({})),
      ]);
      final keys = TestKeys('old', refreshed: 'new');
      final o = await DecisionsApi(http: net.client, keys: keys).send(_body);
      expect(o, isA<DecisionAnswered>());
      expect(keys.refreshes, 1);
      expect(net.requests.map((r) => r.headers['x-goog-api-key']), [
        'old',
        'new',
      ]);
    });

    test('a key that cannot be re-read stays a key error', () async {
      final net = ScriptedHttp([
        httpResponse(403, googleError(403, 'PERMISSION_DENIED', 'denied')),
      ]);
      final keys = TestKeys('k');
      final o = await DecisionsApi(http: net.client, keys: keys).send(_body);
      expect(o, isA<DecisionKeyRejected>());
      expect(keys.refreshes, 1);
      expect(net.requests, hasLength(1));
    });

    test('a transport error is transient', () async {
      final net = ScriptedHttp([clientException()]);
      final o = await DecisionsApi(
        http: net.client,
        keys: TestKeys('k'),
      ).send(_body);
      expect(
        o,
        isA<DecisionTransient>().having((t) => t.detail, 'detail', 'transport'),
      );
    });

    test('a timeout is transient', () async {
      final api = DecisionsApi(
        http: HangingClient(),
        keys: TestKeys('k'),
        timeout: const Duration(milliseconds: 10),
      );
      final o = await api.send(_body);
      expect(
        o,
        isA<DecisionTransient>().having((t) => t.detail, 'detail', 'timeout'),
      );
    });

    test('FixedApiKey never shows the key', () {
      expect(FixedApiKey('secret').toString(), isNot(contains('secret')));
      expect(FixedApiKey('secret').refresh(), isNull);
    });
  });
}

http.Response httpResponse(int status, String body) =>
    http.Response(body, status, headers: {'content-type': 'application/json'});

Exception clientException() => http.ClientException('reset');

/// A client whose requests never complete.
final class HangingClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      Completer<http.StreamedResponse>().future;
}
