import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:xpense_app/services/decisions_client.dart';
import 'package:xpense_app/services/service_failure.dart';
import 'package:xpense_shared/xpense_shared.dart';

final _request = DecideRequest(
  text: 'Lunch 15,000 dinars',
  lang: 'en',
  parsed: DecideParsed(amountMinor: 15000, currency: 'IQD'),
  ask: ['intent', 'category', 'to_account'],
);

String _error(int code, String status, String message) =>
    jsonEncode({'code': code, 'status': status, 'message': message});

void main() {
  late List<({Uri url, Map<String, String> headers, String body})> sent;
  late FutureOr<DecideHttpResponse> Function() reply;

  setUp(() {
    sent = [];
    reply = () => (
      status: 200,
      body: jsonEncode({
        'result': {
          'intent': {'choice': 'expense', 'confidence': 0.98},
          'to_account': {'choice': 'unspecified', 'confidence': 0.9},
          'calibrated': true,
        },
      }),
    );
  });

  HttpDecisionsClient client({
    String? idToken = 'id-1',
    String? appCheck = 'ac-1',
    Duration timeout = const Duration(seconds: 10),
  }) => HttpDecisionsClient(
    baseUrl: Uri.parse('https://agent.example'),
    idToken: () async => idToken,
    appCheckToken: () async => appCheck,
    timeout: timeout,
    transport: (url, headers, body) async {
      sent.add((url: url, headers: headers, body: body));
      return await reply();
    },
  );

  test('posts the request in the Genkit envelope with both tokens', () async {
    final result = await client().decide(_request);
    expect(result, isA<Ok<DecideResponse, ServiceFailure>>());
    final response = (result as Ok<DecideResponse, ServiceFailure>).value;
    expect(response.intent?.choice, 'expense');
    expect(response.toAccount?.choice, 'unspecified');
    expect(response.calibrated, isTrue);

    final call = sent.single;
    expect(call.url.toString(), 'https://agent.example/v1/decide');
    expect(call.headers['authorization'], 'Bearer id-1');
    expect(call.headers['x-firebase-appcheck'], 'ac-1');
    final body = jsonDecode(call.body) as Map<String, Object?>;
    expect(body.keys, ['data']);
    expect((body['data']! as Map)['ask'], ['intent', 'category', 'to_account']);
  });

  test('fallback answers keep calibrated: false', () async {
    reply = () => (
      status: 200,
      body: jsonEncode({
        'result': {
          'intent': {'choice': 'expense', 'confidence': 0.9},
          'calibrated': false,
        },
      }),
    );
    final result = await client().decide(_request);
    expect(
      (result as Ok<DecideResponse, ServiceFailure>).value.calibrated,
      isFalse,
    );
  });

  test('no ID token: no call, a typed error', () async {
    final result = await client(idToken: null).decide(_request);
    expect(
      result,
      const Err<DecideResponse, ServiceFailure>(
        ServiceError('decide.no_id_token'),
      ),
    );
    expect(sent, isEmpty);
  });

  final cases = <(String, int, String, ServiceFailure)>[
    (
      'unavailable result',
      200,
      '{"result":{"unavailable":true}}',
      const ServiceUnavailable(),
    ),
    (
      'over limit',
      429,
      _error(429, 'RESOURCE_EXHAUSTED', 'over_limit'),
      const ServiceRateLimited(),
    ),
    (
      'on-device member',
      403,
      _error(403, 'PERMISSION_DENIED', 'on_device_mode'),
      const ServiceUnavailable(),
    ),
    (
      'auth unavailable',
      503,
      _error(503, 'UNAVAILABLE', 'auth_unavailable'),
      const ServiceOffline(),
    ),
    ('server error', 500, 'oops', const ServiceOffline()),
    (
      'expired token',
      401,
      _error(401, 'UNAUTHENTICATED', 'invalid_id_token'),
      const ServiceError('decide.401.invalid_id_token'),
    ),
    (
      'bad request',
      400,
      _error(400, 'INVALID_ARGUMENT', 'unknown_question'),
      const ServiceError('decide.400.unknown_question'),
    ),
    ('no result', 200, '{}', const ServiceError('decide.bad_response')),
    ('not JSON', 200, '<html>', const ServiceError('decide.bad_response')),
    (
      'malformed answer',
      200,
      '{"result":{"intent":"expense"}}',
      const ServiceError('decide.bad_response'),
    ),
  ];
  for (final (name, status, body, failure) in cases) {
    test('$name → ${failure.code}', () async {
      reply = () => (status: status, body: body);
      expect(
        await client().decide(_request),
        Err<DecideResponse, ServiceFailure>(failure),
      );
    });
  }

  test('no connection → offline', () async {
    reply = () => throw const SocketException('down');
    expect(
      await client().decide(_request),
      const Err<DecideResponse, ServiceFailure>(ServiceOffline()),
    );
  });

  test('timeout → offline', () async {
    reply = () => Completer<DecideHttpResponse>().future;
    expect(
      await client(timeout: const Duration(milliseconds: 10)).decide(_request),
      const Err<DecideResponse, ServiceFailure>(ServiceOffline()),
    );
  });

  group('duplicateHintFrom', () {
    DuplicateHint? hint(
      double p, {
      bool calibrated = true,
      String? of = 't1',
    }) => duplicateHintFrom(
      DecideResponse(
        duplicate: YesNoAnswer(probability: p),
        duplicateOf: of,
        calibrated: calibrated,
      ),
      warnAt: 0.8,
      uncalibratedCap: 0.8,
    );

    test('warns at dup_warn with the candidate id', () {
      final h = hint(0.85);
      expect(h?.txnId, 't1');
      expect(h?.probability, 0.85);
      expect(hint(0.75), isNull);
    });

    test('no candidate or no answer: no warning', () {
      expect(hint(0.99, of: null), isNull);
      expect(
        duplicateHintFrom(
          DecideResponse(calibrated: true),
          warnAt: 0.8,
          uncalibratedCap: 0.8,
        ),
        isNull,
      );
    });

    test('uncalibrated answers are capped first', () {
      expect(hint(0.99, calibrated: false)?.probability, 0.8);
    });
  });
}
