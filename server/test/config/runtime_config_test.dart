import 'package:clock/clock.dart';
import 'package:test/test.dart';
import 'package:xpense_agent/config/runtime_config.dart';
import 'package:xpense_agent/telemetry/usage_counters.dart';

import '../support/fakes.dart';

void main() {
  group('RuntimeConfig.fromDocument', () {
    test('no document: the documented defaults', () {
      final config = RuntimeConfig.fromDocument(null);
      expect(config.model('agent'), 'gemini-3.5-flash-lite');
      expect(config.model('escalation'), 'gemini-3.8-flash');
      expect(config.model('decide'), 'gemini-decision-1');
      expect(config.limits, {
        UsageCounter.agentTurns: 150,
        UsageCounter.decisions: 600,
        UsageCounter.audioSeconds: 600,
        UsageCounter.images: 40,
      });
      expect(config.isOn('agentEnabled'), isTrue);
      expect(config.isOn('liteOnly'), isFalse);
      expect(config.confidence['conf_high'], 0.85);
    });

    test('no model id is a -latest alias (D-04)', () {
      for (final id in RuntimeConfig.defaults.models.values) {
        expect(id, isNot(contains('latest')));
      }
    });

    test('fields override defaults one by one', () {
      final config = RuntimeConfig.fromDocument(const {
        'models': {'agent': 'gemini-4-hydrogen'},
        'limits': {'images': 5},
        'switches': {'liteOnly': true},
        'confidence': {'conf_low': 0.5},
      });
      expect(config.model('agent'), 'gemini-4-hydrogen');
      expect(config.model('decide'), 'gemini-decision-1');
      expect(config.limits[UsageCounter.images], 5);
      expect(config.limits[UsageCounter.agentTurns], 150);
      expect(config.isOn('liteOnly'), isTrue);
      expect(config.confidence['conf_low'], 0.5);
      expect(config.confidence['conf_high'], 0.85);
    });

    test('invalid values fall back to the default', () {
      final config = RuntimeConfig.fromDocument(const {
        'models': {'agent': '', 'decide': 7},
        'limits': {'images': -1, 'decisions': '600', 'unknownCounter': 3},
        'switches': {'liteOnly': 'yes'},
        'confidence': {'conf_high': 1.5, 'conf_low': 1},
        'unexpected': 'ignored',
      });
      expect(config.model('agent'), 'gemini-3.5-flash-lite');
      expect(config.model('decide'), 'gemini-decision-1');
      expect(config.limits[UsageCounter.images], 40);
      expect(config.limits[UsageCounter.decisions], 600);
      expect(config.isOn('liteOnly'), isFalse);
      expect(config.confidence['conf_high'], 0.85);
      expect(config.confidence['conf_low'], 1.0, reason: 'ints are accepted');
    });

    test('a section of the wrong type is ignored', () {
      final config = RuntimeConfig.fromDocument(const {'limits': 'none'});
      expect(config.limits, RuntimeConfig.defaults.limits);
    });

    test('an unknown model role is a programming error', () {
      expect(() => RuntimeConfig.defaults.model('nope'), throwsStateError);
    });
  });

  group('RuntimeConfigLoader', () {
    late FakeDocumentStore docs;
    late DateTime now;
    late RuntimeConfigLoader loader;

    setUp(() {
      docs = FakeDocumentStore();
      now = DateTime.utc(2026, 11, 22);
      loader = RuntimeConfigLoader(docs, clock: Clock(() => now));
    });

    test('reads config/runtime and caches it for 60 s', () async {
      docs.docs['config/runtime'] = {
        'limits': {'images': 1},
      };
      expect((await loader.current()).limits[UsageCounter.images], 1);
      docs.docs['config/runtime'] = {
        'limits': {'images': 2},
      };
      now = now.add(const Duration(seconds: 59));
      expect((await loader.current()).limits[UsageCounter.images], 1);
      now = now.add(const Duration(seconds: 2));
      expect((await loader.current()).limits[UsageCounter.images], 2);
      expect(docs.readsOf('config/runtime'), 2);
    });

    test('concurrent callers share one read', () async {
      await Future.wait([loader.current(), loader.current()]);
      expect(docs.readsOf('config/runtime'), 1);
    });

    test('a failed first read serves the defaults', () async {
      docs.failingPaths.add('config/runtime');
      expect(await loader.current(), same(RuntimeConfig.defaults));
    });

    test('a failed refresh keeps the last good config', () async {
      docs.docs['config/runtime'] = {
        'limits': {'images': 3},
      };
      await loader.current();
      docs.failingPaths.add('config/runtime');
      now = now.add(const Duration(minutes: 5));
      expect((await loader.current()).limits[UsageCounter.images], 3);
      // It retries soon rather than on every request.
      final reads = docs.readsOf('config/runtime');
      await loader.current();
      expect(docs.readsOf('config/runtime'), reads);
      docs.failingPaths.clear();
      now = now.add(const Duration(seconds: 6));
      await loader.current();
      expect(docs.readsOf('config/runtime'), reads + 1);
    });
  });
}
