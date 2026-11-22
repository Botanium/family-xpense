import 'dart:convert';

import 'package:clock/clock.dart';
import 'package:genkit/genkit.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';
import 'package:xpense_agent/config/server_env.dart';
import 'package:xpense_agent/decide/classifier.dart';
import 'package:xpense_agent/xpense_server.dart';
import 'package:xpense_shared/xpense_shared.dart';

import '../support/fakes.dart';

void main() {
  late Genkit ai;
  late FakeDocumentStore docs;
  late FakeEntryClassifier classifier;
  late Handler handler;

  setUp(() {
    ai = Genkit(isDevEnv: false, promptDir: null);
    docs = FakeDocumentStore()
      ..seedMember(uid: 'u1', hid: 'h1')
      ..seedMember(uid: 'u2', hid: 'h2', privacyMode: 'on_device');
    classifier = FakeEntryClassifier.always(
      DecideResponse(
        intent: ChoiceAnswer(choice: 'expense', confidence: 0.98),
        calibrated: true,
      ),
    );
    handler = XpenseServer.create(
      role: XpenseRole.agent,
      ai: ai,
      gateway: fakeGateway(documents: docs),
      clock: Clock.fixed(DateTime.utc(2026, 11, 22, 12)),
      classifier: (config, usage) => classifier,
    ).handler;
  });

  tearDown(() => ai.shutdown());

  Future<(int, Map<String, Object?>?)> post(
    Object body, {
    String uid = 'u1',
    Map<String, String>? headers,
  }) async {
    final response = await handler(
      Request(
        'POST',
        Uri.parse('http://localhost/v1/decide'),
        headers: {
          'content-type': 'application/json',
          ...(headers ?? headersFor(uid)),
        },
        body: jsonEncode({'data': body}),
      ),
    );
    final text = await response.readAsString();
    return (
      response.statusCode,
      text.startsWith('{') ? jsonDecode(text) as Map<String, Object?> : null,
    );
  }

  final request = {
    'text': 'Lunch 15,000 dinars',
    'lang': 'en',
    'parsed': {'amountMinor': 15000, 'currency': 'IQD'},
    'hints': [
      {'kind': 'account', 'id': 'acc1'},
    ],
    'ask': ['intent', 'category', 'to_account'],
  };

  test(
    'answers with the classifier response and the verified context',
    () async {
      final (status, json) = await post(request);
      expect(status, 200);
      expect(json?['result'], {
        'intent': {'choice': 'expense', 'confidence': 0.98},
        'calibrated': true,
      });
      final call = classifier.calls.single;
      expect(call.context.hid, 'h1');
      expect(call.context.uid, 'u1');
      expect(call.ask, {
        DecideQuestion.intent,
        DecideQuestion.category,
        DecideQuestion.toAccount,
      });
      expect(call.parsed?.amountMinor, 15000);
      expect(call.hints.single.id, 'acc1');
    },
  );

  test('without tokens: 401, classifier not called', () async {
    final (status, json) = await post(request, headers: const {});
    expect(status, 401);
    expect(json?['message'], 'missing_id_token');
    expect(classifier.calls, isEmpty);
  });

  test('an on-device member is refused', () async {
    final (status, json) = await post(request, uid: 'u2');
    expect(status, 403);
    expect(json?['message'], 'on_device_mode');
  });

  test('at the daily decisions limit: 429 over_limit', () async {
    docs.docs['households/h1/usage/2026-11-22'] = {'decisions': 600};
    final (status, json) = await post(request);
    expect(status, 429);
    expect(json?['message'], 'over_limit');
    expect(classifier.calls, isEmpty);
  });

  test('an unknown question key is 400', () async {
    final (status, json) = await post({
      ...request,
      'ask': ['intent', 'favourite_colour'],
    });
    expect(status, 400);
    expect(json?['message'], contains('unknown_question'));
    expect(classifier.calls, isEmpty);
  });

  test('empty or overlong text is 400', () async {
    for (final text in ['   ', 'x' * 2001]) {
      final (status, _) = await post({...request, 'text': text});
      expect(status, 400, reason: 'length ${text.length}');
    }
    expect(classifier.calls, isEmpty);
  });

  test('another language is unavailable, not sent', () async {
    final (status, json) = await post({...request, 'lang': 'ckb'});
    expect(status, 200);
    expect(json?['result'], {'unavailable': true});
    expect(classifier.calls, isEmpty);
  });

  test('without a classifier the route answers unavailable', () async {
    final other = Genkit(isDevEnv: false, promptDir: null);
    addTearDown(other.shutdown);
    handler = XpenseServer.create(
      role: XpenseRole.agent,
      ai: other,
      gateway: fakeGateway(documents: docs),
    ).handler;
    final (status, json) = await post(request);
    expect(status, 200);
    expect(json?['result'], {'unavailable': true});
  });
}
