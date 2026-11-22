import 'dart:math';

import 'package:clock/clock.dart';
import 'package:http/http.dart' as http;
import 'package:test/test.dart';
import 'package:xpense_agent/admin/admin_gateway.dart';
import 'package:xpense_agent/config/runtime_config.dart';
import 'package:xpense_agent/decide/classifier.dart';
import 'package:xpense_agent/decide/decide_cache.dart';
import 'package:xpense_agent/decide/decisions_api.dart';
import 'package:xpense_agent/decide/decisions_classifier.dart';
import 'package:xpense_agent/decide/fallback.dart';
import 'package:xpense_agent/decide/household_profile.dart';
import 'package:xpense_agent/decide/question_set.dart';
import 'package:xpense_agent/telemetry/usage_counters.dart';
import 'package:xpense_shared/xpense_shared.dart';

import '../support/fakes.dart';
import 'support.dart';

final class FakeFallback implements FallbackClassifier {
  new([this.result]);

  FallbackAnswers? result;
  final plans = <DecideRequestPlan>[];
  final models = <String>[];

  @override
  Future<FallbackAnswers?> answer(
    DecideRequestPlan plan, {
    required String model,
  }) async {
    plans.add(plan);
    models.add(model);
    return result;
  }
}

/// A store whose increments fail, to check usage is best effort.
final class FailingIncrements implements DocumentStore {
  final _inner = FakeDocumentStore();

  @override
  Future<Map<String, Object?>?> read(String path) => _inner.read(path);

  @override
  Future<void> increment(
    String path,
    Map<String, int> deltas, {
    Map<String, Object?> fields = const {},
  }) async => throw const GatewayUnavailable('increment');

  @override
  Future<void> write(
    String path,
    Map<String, Object?> data, {
    bool merge = false,
  }) => _inner.write(path, data, merge: merge);
}

http.Response ok(Map<String, Object?> answers, {int tokens = 2000}) =>
    http.Response(answeredBody(answers, inputTokens: tokens), 200);

http.Response err(int status, String body) => http.Response(body, status);

const _usagePath = 'households/h1/usage/2026-11-22';
final _now = DateTime.utc(2026, 11, 22, 12);

void main() {
  late FakeDocumentStore docs;
  late FakeHouseholdSource households;
  late FakeFallback fallback;
  late List<Duration> sleeps;
  late DecideCache cache;
  var clockNow = _now;

  setUp(() {
    docs = FakeDocumentStore();
    households = FakeHouseholdSource();
    fallback = FakeFallback();
    sleeps = [];
    clockNow = _now;
    cache = DecideCache(clock: Clock(() => clockNow));
  });

  (DecisionsClassifier, ScriptedHttp) build(
    List<Object> script, {
    DocumentStore? store,
  }) {
    final net = ScriptedHttp(script);
    final s = store ?? docs;
    final clock = Clock(() => clockNow);
    return (
      DecisionsClassifier(
        api: DecisionsApi(http: net.client, keys: FixedApiKey('k')),
        households: households,
        config: RuntimeConfigLoader(s, clock: clock),
        usage: UsageCounters(s, clock: clock),
        fallback: fallback,
        cache: cache,
        clock: clock,
        random: Random(1),
        sleep: (d) async => sleeps.add(d),
      ),
      net,
    );
  }

  Future<DecideResponse> classify(
    DecisionsClassifier c, {
    Set<DecideQuestion> ask = const {.intent, .category, .account, .multiEntry},
    String text = 'Lunch 15,000 dinars from my wallet',
    DecideParsed? parsed,
    List<ParseHint> hints = const [],
    List<DuplicateCandidate> candidates = const [],
  }) => c.classify(
    context: context,
    text: text,
    ask: ask,
    parsed: parsed ?? DecideParsed(amountMinor: 15000, currency: 'IQD'),
    hints: hints,
    candidates: candidates,
  );

  final happy = {
    'intent': choice('expense', 0.98),
    'category': choice('dining', 0.97),
    'account': choice(cashId, 0.91),
    'multi_entry': yesNo(0.02),
  };

  group('Decisions answers', () {
    test('one call; answers mapped and calibrated', () async {
      final (c, net) = build([ok(happy)]);
      final r = await classify(c);
      expect(net.requests, hasLength(1));
      expect(r.calibrated, isTrue);
      expect(r.unavailable, isNull);
      expect(r.intent?.choice, 'expense');
      expect(r.intent?.confidence, 0.98);
      expect(r.category?.choice, 'dining');
      expect(r.account?.choice, cashId);
      expect(r.multiEntry?.probability, 0.02);
      expect(r.multiEntry?.confidence, 0.98);
      expect(r.who, isNull, reason: 'not asked');
      expect(fallback.plans, isEmpty);
    });

    test('the request holds only the asked keys and API fields', () async {
      final (c, net) = build([ok(happy)]);
      await classify(c);
      final body = net.bodyOf(0);
      expect(body.keys, ['model', 'input', 'questions']);
      expect(body['model'], 'gemini-decision-1');
      expect((body['questions']! as Map).keys, [
        'intent',
        'category',
        'account',
        'multi_entry',
      ]);
      expect(body['input'], contains('Today: 2026-11-22 (Sunday)'));
    });

    test('the model id comes from config/runtime', () async {
      docs.docs['config/runtime'] = {
        'models': {'decide': 'gemini-decision-2'},
      };
      final (c, net) = build([ok(happy)]);
      await classify(c);
      expect(net.bodyOf(0)['model'], 'gemini-decision-2');
    });

    test('usage: one decision, input tokens and cost', () async {
      final (c, _) = build([ok(happy, tokens: 2007)]);
      await classify(c);
      expect(docs.docs[_usagePath], containsPair('decisions', 1));
      expect(docs.docs[_usagePath], containsPair('inputTokens', 2007));
      // USD 0.10 per 1M tokens: 2,007 tokens = 200.7 micro-USD, rounded up.
      expect(docs.docs[_usagePath], containsPair('costMicrosUsd', 201));
    });

    test('a usage write failure does not fail the answer', () async {
      final (c, _) = build([ok(happy)], store: FailingIncrements());
      final r = await classify(c);
      expect(r.intent?.choice, 'expense');
    });

    test('an answer outside the options sent is dropped', () async {
      final (c, _) = build([
        ok({
          'intent': choice('expense', 0.9),
          'category': choice('made_up', 0.9),
          'account': {'choice': cashId, 'confidence': 1.7},
          'multi_entry': {'noul': 'yes'},
        }),
      ]);
      final r = await classify(c);
      expect(r.intent?.choice, 'expense');
      expect(r.category, isNull);
      expect(r.account?.choice, cashId);
      expect(r.account?.confidence, isNull, reason: '1.7 is out of range');
      expect(r.multiEntry, isNull);
    });

    test('probabilities keep only the options sent', () async {
      final (c, _) = build([
        ok({
          'intent': {
            'choice': 'expense',
            'probabilities': {'expense': 0.9, 'other': 0.1, 'bogus': 0.5},
            'confidence': 0.9,
          },
        }),
      ]);
      final r = await classify(c, ask: {.intent});
      expect(r.intent?.probabilities, {'expense': 0.9, 'other': 0.1});
    });

    test('nothing asked: no call', () async {
      final (c, net) = build([]);
      final r = await classify(c, ask: {});
      expect(r.calibrated, isTrue);
      expect(net.requests, isEmpty);
    });
  });

  group('cache', () {
    test('the same message within 10 minutes is not sent again', () async {
      final (c, net) = build([ok(happy), ok(happy)]);
      await classify(c);
      clockNow = _now.add(const Duration(minutes: 9));
      final again = await classify(c);
      expect(net.requests, hasLength(1));
      expect(again.intent?.choice, 'expense');
      expect(docs.docs[_usagePath]?['decisions'], 1, reason: 'hits are free');
      clockNow = _now.add(const Duration(minutes: 10));
      await classify(c);
      expect(net.requests, hasLength(2));
    });

    test('a different message or speaker misses', () async {
      final (c, net) = build([ok(happy), ok(happy)]);
      await classify(c);
      await classify(c, text: 'Lunch 15,000 dinars from the wallet');
      expect(net.requests, hasLength(2));
    });

    test('fallback answers are not cached', () async {
      fallback.result = const FallbackAnswers(
        answers: {},
        inputTokens: 1,
        outputTokens: 1,
      );
      final (c, net) = build([
        err(400, decisionsError('invalid_request', 'x')),
        err(400, decisionsError('invalid_request', 'x')),
      ]);
      await classify(c);
      await classify(c);
      expect(net.requests, hasLength(2));
    });

    test('LRU evicts the least recently used', () {
      final small = DecideCache(capacity: 2, clock: Clock.fixed(_now));
      final r = DecideResponse(calibrated: true);
      small
        ..put('a', r)
        ..put('b', r);
      expect(small.get('a'), isNotNull);
      small.put('c', r);
      expect(small.get('b'), isNull);
      expect(small.get('a'), isNotNull);
      expect(small.length, 2);
    });
  });

  group('retry and fallback chain', () {
    test('429 then answer: one retry with jitter', () async {
      final (c, net) = build([
        err(429, googleError(429, 'RESOURCE_EXHAUSTED', 'quota')),
        ok(happy),
      ]);
      final r = await classify(c);
      expect(net.requests, hasLength(2));
      expect(sleeps.single.inMilliseconds, inInclusiveRange(100, 400));
      expect(r.calibrated, isTrue);
      expect(fallback.plans, isEmpty);
    });

    test(
      '5xx twice: no third call; the fallback answers uncalibrated',
      () async {
        fallback.result = const FallbackAnswers(
          answers: {
            'intent': {'choice': 'expense', 'confidence': 0.95},
            'category': {'choice': 'dining', 'confidence': 0.9},
            'account': {'choice': cashId, 'confidence': 0.8},
            'multi_entry': {'noul': 0.01},
          },
          inputTokens: 2400,
          outputTokens: 60,
        );
        final (c, net) = build([err(503, 'unavailable'), err(500, 'boom')]);
        final r = await classify(c);
        expect(net.requests, hasLength(2));
        expect(r.calibrated, isFalse);
        expect(r.unavailable, isNull);
        expect(r.intent?.choice, 'expense');
        expect(r.multiEntry?.probability, 0.01);
        expect(fallback.models.single, 'gemini-3.5-flash-lite');
        expect(docs.docs[_usagePath], containsPair('outputTokens', 60));
        // 2,400 × 0.30 + 60 × 2.50 = 870 micro-USD.
        expect(docs.docs[_usagePath], containsPair('costMicrosUsd', 870));
      },
    );

    test('a transport error is retried', () async {
      final (c, net) = build([http.ClientException('reset'), ok(happy)]);
      final r = await classify(c);
      expect(net.requests, hasLength(2));
      expect(r.calibrated, isTrue);
    });

    test('invalid_request: no retry, straight to the fallback', () async {
      fallback.result = const FallbackAnswers(
        answers: {
          'intent': {'choice': 'expense', 'confidence': 0.9},
        },
        inputTokens: 10,
        outputTokens: 5,
      );
      final (c, net) = build([
        err(400, decisionsError('invalid_request', "Unknown parameter 'x'")),
      ]);
      final r = await classify(c);
      expect(net.requests, hasLength(1));
      expect(sleeps, isEmpty);
      expect(r.calibrated, isFalse);
      expect(r.intent?.choice, 'expense');
      expect(fallback.plans, hasLength(1));
    });

    test('a refused key goes to the fallback', () async {
      fallback.result = const FallbackAnswers(
        answers: {},
        inputTokens: 1,
        outputTokens: 1,
      );
      final (c, net) = build([
        err(403, googleError(403, 'PERMISSION_DENIED', 'denied')),
      ]);
      final r = await classify(c);
      expect(net.requests, hasLength(1), reason: 'a fixed key is not re-read');
      expect(r.calibrated, isFalse);
    });

    test('no fallback answer: unavailable', () async {
      final (c, _) = build([err(503, ''), err(503, '')]);
      final r = await classify(c);
      expect(r.unavailable, isTrue);
      expect(r.intent, isNull);
      expect(fallback.plans, hasLength(1));
    });

    for (final (name, response) in [
      ('400 safety code', err(400, decisionsError('safety', 'blocked'))),
      (
        '400 prohibited_content',
        err(400, decisionsError('prohibited_content', 'x')),
      ),
      (
        '200 prompt_feedback',
        http.Response(
          '{"answers":{},"prompt_feedback":{"block_reason":"SAFETY"}}',
          200,
        ),
      ),
    ]) {
      test('$name: blocked, no retry, no fallback, unavailable', () async {
        final (c, net) = build([response]);
        final r = await classify(c);
        expect(net.requests, hasLength(1));
        expect(sleeps, isEmpty);
        expect(fallback.plans, isEmpty);
        expect(r.unavailable, isTrue);
        expect(r.calibrated, isNull);
      });
    }

    test('decideEnabled off: unavailable with no call', () async {
      docs.docs['config/runtime'] = {
        'switches': {'decideEnabled': false},
      };
      final (c, net) = build([]);
      final r = await classify(c);
      expect(r.unavailable, isTrue);
      expect(net.requests, isEmpty);
    });

    test('household unreadable: unavailable with no call', () async {
      households.failProfile = true;
      final (c, net) = build([]);
      final r = await classify(c);
      expect(r.unavailable, isTrue);
      expect(net.requests, isEmpty);
    });
  });

  group('duplicates', () {
    const entry = RecentEntry(
      id: 't-gen',
      amountMinor: 50000,
      currency: 'IQD',
      occurredOn: '2026-11-21',
      accountId: cashId,
      title: 'Generator',
    );

    Set<String> asked(ScriptedHttp net) =>
        (net.bodyOf(0)['questions']! as Map).keys.cast<String>().toSet();

    test(
      'a saved entry the day before is listed and duplicate asked',
      () async {
        households.entries = [entry];
        final (c, net) = build([
          ok({'duplicate': yesNo(0.9)}),
        ]);
        final r = await classify(
          c,
          ask: {.duplicate},
          text: 'Paid the generator guy 50,000 dinars for this month',
          parsed: DecideParsed(amountMinor: 50000, currency: 'IQD'),
        );
        expect(households.queries.single, (
          amountMinor: 50000,
          fromDay: '2026-11-21',
          toDay: '2026-11-23',
        ));
        expect(asked(net), {'duplicate'});
        expect(
          net.bodyOf(0)['input'],
          endsWith(
            'Recent entries:\n- IQD 50,000, 2026-11-21, Generator, Cash wallet',
          ),
        );
        expect(r.duplicate?.probability, 0.9);
      },
    );

    test('the window follows the parsed date', () async {
      final (c, _) = build([ok({})]);
      await classify(
        c,
        ask: {.intent, .duplicate},
        parsed: DecideParsed(
          amountMinor: 1,
          currency: 'IQD',
          date: '2026-11-01',
        ),
      );
      expect(households.queries.single.fromDay, '2026-10-31');
      expect(households.queries.single.toDay, '2026-11-02');
    });

    test('no candidates: duplicate is not asked', () async {
      final (c, net) = build([ok(happy)]);
      final r = await classify(c, ask: {.intent, .duplicate});
      expect(asked(net), {'intent'});
      expect(r.duplicate, isNull);
    });

    test('no candidates and nothing else: no call at all', () async {
      final (c, net) = build([]);
      await classify(c, ask: {.duplicate});
      expect(net.requests, isEmpty);
    });

    test(
      'different currency, other account, deleted or far: not listed',
      () async {
        households.entries = [
          const RecentEntry(
            id: 'usd',
            amountMinor: 50000,
            currency: 'USD',
            occurredOn: '2026-11-22',
            accountId: checkingId,
          ),
          const RecentEntry(
            id: 'other-account',
            amountMinor: 50000,
            currency: 'IQD',
            occurredOn: '2026-11-22',
            accountId: jointCardId,
          ),
          const RecentEntry(
            id: 'deleted',
            amountMinor: 50000,
            currency: 'IQD',
            occurredOn: '2026-11-22',
            accountId: cashId,
            deleted: true,
          ),
          const RecentEntry(
            id: 'old',
            amountMinor: 50000,
            currency: 'IQD',
            occurredOn: '2026-11-19',
            accountId: cashId,
          ),
        ];
        final (c, net) = build([ok({})]);
        await classify(
          c,
          ask: {.intent, .duplicate},
          parsed: DecideParsed(amountMinor: 50000, currency: 'IQD'),
          hints: [ParseHint(kind: 'account', id: cashId)],
        );
        expect(asked(net), {'intent'});
      },
    );

    test("the caller's candidates count when they pass the rule", () async {
      final (c, net) = build([ok({})]);
      await classify(
        c,
        ask: {.duplicate},
        candidates: [
          DuplicateCandidate(
            txnId: 'local-1',
            amountMinor: 15000,
            currency: 'IQD',
            occurredOn: '2026-11-22',
            title: 'Lunch',
          ),
          DuplicateCandidate(
            txnId: 'local-2',
            amountMinor: 99,
            currency: 'IQD',
            occurredOn: '2026-11-22',
            title: 'Not the same amount',
          ),
        ],
      );
      expect(
        net.bodyOf(0)['input'],
        contains('- IQD 15,000, 2026-11-22, Lunch'),
      );
      expect(net.bodyOf(0)['input'], isNot(contains('Not the same amount')));
    });

    test('a failed search still uses the caller candidates', () async {
      households.failEntries = true;
      final (c, net) = build([ok({})]);
      await classify(
        c,
        ask: {.duplicate},
        candidates: [
          DuplicateCandidate(
            txnId: 'local-1',
            amountMinor: 15000,
            currency: 'IQD',
            occurredOn: '2026-11-21',
          ),
        ],
      );
      expect(asked(net), {'duplicate'});
    });

    test('at most five, nearest first', () async {
      households.entries = [
        for (var i = 0; i < 8; i++)
          RecentEntry(
            id: 't$i',
            amountMinor: 15000,
            currency: 'IQD',
            occurredOn: i.isEven ? '2026-11-22' : '2026-11-21',
            accountId: cashId,
            title: 'e$i',
          ),
      ];
      final (c, net) = build([ok({})]);
      await classify(c, ask: {.duplicate});
      final lines = (net.bodyOf(0)['input']! as String)
          .split('\n')
          .where((l) => l.startsWith('- '))
          .toList();
      expect(lines, hasLength(5));
      expect(lines.take(4).every((l) => l.contains('2026-11-22')), isTrue);
    });
  });

  group('transfers and people', () {
    test('to_account and person are asked and mapped', () async {
      final (c, net) = build([
        ok({
          'intent': choice('transfer', 0.97),
          'account': choice(checkingId, 0.93),
          'to_account': choice(jointCardId, 0.9),
          'person': choice('none', 0.95),
        }),
      ]);
      final r = await classify(
        c,
        ask: {.intent, .account, .toAccount, .person},
        text: 'Moved 500 dollars from checking to the joint card',
      );
      final questions = net.bodyOf(0)['questions']! as Map;
      expect(
        (questions['account']! as Map)['instructions'],
        accountFromInstructions,
      );
      expect(r.toAccount?.choice, jointCardId);
      expect(r.person?.choice, 'none');
    });
  });
}
