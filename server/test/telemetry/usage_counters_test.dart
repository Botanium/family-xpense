import 'package:clock/clock.dart';
import 'package:test/test.dart';
import 'package:xpense_agent/telemetry/usage_counters.dart';

import '../support/fakes.dart';

void main() {
  test('the day key is the UTC date', () {
    // 01:30 in Baghdad (UTC+3) on the 23rd is still the 22nd in UTC.
    expect(
      UsageCounters.dayKey(DateTime.utc(2026, 11, 22, 22, 30)),
      '2026-11-22',
    );
    expect(UsageCounters.dayKey(DateTime.utc(2027, 1, 2)), '2027-01-02');
    expect(
      UsageCounters.pathFor('h1', DateTime.utc(2026, 3, 9)),
      'households/h1/usage/2026-03-09',
    );
  });

  test('field names match DATA_MODEL 2.15', () {
    expect(UsageCounter.values.map((c) => c.field), [
      'agentTurns',
      'decisions',
      'audioSeconds',
      'images',
      'inputTokens',
      'outputTokens',
      'costMicrosUsd',
    ]);
    expect(UsageCounter.byField('images'), UsageCounter.images);
    expect(UsageCounter.byField('nope'), isNull);
  });

  group('with a store', () {
    late FakeDocumentStore docs;
    late DateTime now;
    late UsageCounters usage;

    setUp(() {
      docs = FakeDocumentStore();
      now = DateTime.utc(2026, 11, 22, 9);
      usage = UsageCounters(docs, clock: Clock(() => now));
    });

    test('today() reads zeros for a fresh day', () async {
      final today = await usage.today('h1');
      expect(today.values, everyElement(0));
      expect(today.keys, UsageCounter.values);
    });

    test("add() increments today's document and stamps it", () async {
      await usage.add('h1', {
        UsageCounter.agentTurns: 1,
        UsageCounter.inputTokens: 1200,
      });
      await usage.add('h1', {
        UsageCounter.agentTurns: 1,
        UsageCounter.images: 0,
      });
      final doc = docs.docs['households/h1/usage/2026-11-22']!;
      expect(doc['agentTurns'], 2);
      expect(doc['inputTokens'], 1200);
      expect(doc.containsKey('images'), isFalse, reason: 'zero is skipped');
      expect(doc['day'], '2026-11-22');
      expect(doc['updatedBy'], 'system');
      expect(doc['schemaVersion'], 1);
      final today = await usage.today('h1');
      expect(today[UsageCounter.agentTurns], 2);
    });

    test('a new UTC day starts a new document', () async {
      await usage.add('h1', {UsageCounter.decisions: 3});
      now = now.add(const Duration(days: 1));
      expect((await usage.today('h1'))[UsageCounter.decisions], 0);
    });

    test('nothing to add writes nothing', () async {
      await usage.add('h1', {UsageCounter.images: 0});
      expect(docs.docs, isEmpty);
    });

    test('negative amounts are refused', () async {
      await expectLater(
        usage.add('h1', {UsageCounter.images: -1}),
        throwsArgumentError,
      );
      expect(docs.docs, isEmpty);
    });

    test('non-integer stored values are read as integers', () async {
      docs.docs['households/h1/usage/2026-11-22'] = {
        'audioSeconds': 12.0,
        'images': 'x',
      };
      final today = await usage.today('h1');
      expect(today[UsageCounter.audioSeconds], 12);
      expect(today[UsageCounter.images], 0);
    });
  });

  group('overLimit', () {
    const limits = {UsageCounter.agentTurns: 150, UsageCounter.images: 40};

    test('a counter at its limit is over', () {
      expect(
        UsageCounters.overLimit(
          usage: {UsageCounter.agentTurns: 150, UsageCounter.images: 39},
          limits: limits,
          meters: {UsageCounter.agentTurns, UsageCounter.images},
        ),
        {UsageCounter.agentTurns},
      );
    });

    test('only metered counters are checked', () {
      expect(
        UsageCounters.overLimit(
          usage: {UsageCounter.agentTurns: 999},
          limits: limits,
          meters: {UsageCounter.images},
        ),
        isEmpty,
      );
    });

    test('a counter without a limit is never over', () {
      expect(
        UsageCounters.overLimit(
          usage: {UsageCounter.inputTokens: 1 << 40},
          limits: limits,
          meters: {UsageCounter.inputTokens},
        ),
        isEmpty,
      );
    });
  });
}
