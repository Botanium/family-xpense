// WP-33 live check: the real /decide classifier against the Decisions API
// and the Flash-Lite fallback, on a fixture household (no Firestore).
//
//   cd server && dart run tool/decide_live_check.dart
//
// Reads the newest enabled version of GEMINI_API_KEY in expense-family-cc6ee
// with gcloud at start (and again after a key error). The key stays in
// memory: it is never printed, logged or written. Prints answers, tokens and
// latency only. About 15 calls, well under USD 0.01.
import 'dart:io';

import 'package:clock/clock.dart';
import 'package:genkit/genkit.dart';
import 'package:genkit_google_genai/genkit_google_genai.dart';
import 'package:http/http.dart' as http;
import 'package:xpense_agent/admin/admin_gateway.dart';
import 'package:xpense_agent/auth/xpense_context.dart';
import 'package:xpense_agent/config/runtime_config.dart';
import 'package:xpense_agent/decide/classifier.dart';
import 'package:xpense_agent/decide/decisions_api.dart';
import 'package:xpense_agent/decide/decisions_classifier.dart';
import 'package:xpense_agent/decide/fallback.dart';
import 'package:xpense_agent/decide/household_profile.dart';
import 'package:xpense_agent/decide/question_set.dart';
import 'package:xpense_agent/telemetry/usage_counters.dart';
import 'package:xpense_shared/xpense_shared.dart';

const _project = 'expense-family-cc6ee';
const _secret = 'GEMINI_API_KEY';

/// Reads `latest` resolved to a version number; the value never leaves
/// memory.
final class SecretManagerKey implements ApiKeySource {
  String? _key;
  String version = '?';
  int reads = 0;

  Future<String> _read() async {
    reads++;
    final describe = await Process.run('gcloud', [
      'secrets',
      'versions',
      'describe',
      'latest',
      '--secret=$_secret',
      '--project=$_project',
      '--format=value(name)',
    ]);
    if (describe.exitCode != 0) {
      throw StateError('gcloud describe failed: ${describe.stderr}');
    }
    version = (describe.stdout as String).trim().split('/').last;
    final access = await Process.run('gcloud', [
      'secrets',
      'versions',
      'access',
      version,
      '--secret=$_secret',
      '--project=$_project',
    ]);
    if (access.exitCode != 0) {
      throw StateError('gcloud access of version $version failed');
    }
    final value = (access.stdout as String).trim();
    if (value.isEmpty) throw StateError('version $version is empty');
    return value;
  }

  @override
  Future<String> current() async => _key ??= await _read();

  @override
  Future<String?> refresh() async => _key = await _read();

  @override
  String toString() => 'SecretManagerKey(version $version)';
}

/// Starts with a wrong key so the first call proves the re-read path.
final class StaleThenFresh implements ApiKeySource {
  new(this._inner);

  final SecretManagerKey _inner;
  bool _stale = true;

  @override
  Future<String> current() async =>
      _stale ? 'AIzaStale-not-a-real-key' : await _inner.current();

  @override
  Future<String?> refresh() async {
    _stale = false;
    return await _inner.refresh();
  }
}

final class MemoryStore implements DocumentStore {
  final docs = <String, Map<String, Object?>>{};

  @override
  Future<Map<String, Object?>?> read(String path) async => docs[path];

  @override
  Future<void> increment(
    String path,
    Map<String, int> deltas, {
    Map<String, Object?> fields = const {},
  }) async {
    final doc = docs.putIfAbsent(path, () => {});
    for (final MapEntry(:key, :value) in deltas.entries) {
      doc[key] = ((doc[key] as int?) ?? 0) + value;
    }
  }

  @override
  Future<void> write(
    String path,
    Map<String, Object?> data, {
    bool merge = false,
  }) async => docs[path] = data;

  // The decide flow never needs a transaction (WP-12 added them for joins).
  @override
  Future<T> transaction<T>(Future<T> Function(DocumentTransaction tx) body) =>
      throw UnsupportedError('MemoryStore has no transactions');
}

final class FixtureSource implements HouseholdSource {
  @override
  Future<HouseholdProfile> profile({
    required String hid,
    required String uid,
  }) async => HouseholdProfile(
    baseCurrency: 'USD',
    members: const [
      ProfileMember(uid: 'uDara', name: 'Dara'),
      ProfileMember(uid: 'uShilan', name: 'Shilan'),
    ],
    accounts: const [
      ProfileAccount(
        id: 'k3Qw8ZpL1rT6yVb2nM0a',
        name: 'Cash wallet',
        currency: 'IQD',
        kind: 'cash',
        joint: false,
        ownerUid: 'uDara',
      ),
      ProfileAccount(
        id: 'p9Xe4HcJ7uS2fD5gK1oB',
        name: 'Cash dollars',
        currency: 'USD',
        kind: 'cash',
        joint: false,
        ownerUid: 'uDara',
      ),
      ProfileAccount(
        id: 'm2Rt6YwN8qZ3vB7xL4cC',
        name: 'Checking account',
        currency: 'USD',
        kind: 'bank',
        joint: false,
        ownerUid: 'uDara',
      ),
      ProfileAccount(
        id: 'j7Vb3Nq9Wc2Xz5Lk8Pd1',
        name: 'Joint Visa card',
        currency: 'USD',
        kind: 'credit',
        joint: true,
      ),
      ProfileAccount(
        id: 's4Hn6Tq2Rm8Wz1Kc3Ye5',
        name: 'Savings',
        currency: 'USD',
        kind: 'savings',
        joint: true,
      ),
    ],
    people: const [
      ProfilePerson(id: 'pAlex01', name: 'Alex', aliases: ['Al']),
      ProfilePerson(id: 'pMom01', name: 'Mom', aliases: ['my mother']),
      ProfilePerson(id: 'pHawre01', name: 'Hawre', aliases: ['my brother']),
    ],
    categories: [
      for (final c in defaultCategories)
        ProfileCategory(
          id: c.slug,
          slug: c.slug,
          name: c.nameIn('en'),
          kind: c.kind,
          parentId: c.parentSlug,
        ),
    ],
  );

  @override
  Future<List<RecentEntry>> entriesWithAmount({
    required String hid,
    required String uid,
    required int amountMinor,
    required String fromDay,
    required String toDay,
  }) async => [
    if (amountMinor == 50000)
      const RecentEntry(
        id: 'tGen1',
        amountMinor: 50000,
        currency: 'IQD',
        occurredOn: '2026-11-21',
        accountId: 'k3Qw8ZpL1rT6yVb2nM0a',
        title: 'Generator, November',
      ),
    if (amountMinor == 2000)
      const RecentEntry(
        id: 'tBread1',
        amountMinor: 2000,
        currency: 'IQD',
        occurredOn: '2026-11-21',
        accountId: 'k3Qw8ZpL1rT6yVb2nM0a',
        title: 'Bread',
      ),
  ];
}

typedef Case = ({
  String text,
  Set<DecideQuestion> ask,
  DecideParsed parsed,
  Map<String, String> expect,
});

const _ctx = XpenseContext(
  uid: 'uDara',
  hid: 'hLive',
  locale: 'en',
  privacyMode: PrivacyMode.smart,
  tz: 'Asia/Baghdad',
);

final List<Case> cases = [
  (
    text: 'Paid 42.80 at Costco for groceries on the joint card',
    ask: {
      .intent,
      .category,
      .account,
      .who,
      .multiEntry,
      .needsFollowup,
      .isRecurring,
    },
    parsed: DecideParsed(amountMinor: 4280, currency: 'USD'),
    expect: {
      'intent': 'expense',
      'category': 'groceries',
      'account': 'j7Vb3Nq9Wc2Xz5Lk8Pd1',
    },
  ),
  (
    text: 'Paid 42.80 at Costco for groceries on the joint card yesterday',
    ask: {
      .intent,
      .category,
      .account,
      .toAccount,
      .who,
      .person,
      .multiEntry,
      .repayable,
      .needsFollowup,
      .isRecurring,
    },
    parsed: DecideParsed(
      amountMinor: 4280,
      currency: 'USD',
      date: '2026-11-21',
    ),
    expect: {'intent': 'expense', 'category': 'groceries'},
  ),
  (
    text: 'Spent ten thousand dinars on lunch with the kids',
    ask: {.intent, .category, .account, .who, .multiEntry, .needsFollowup},
    parsed: DecideParsed(amountMinor: 10000, currency: 'IQD'),
    expect: {'intent': 'expense', 'category': 'dining'},
  ),
  (
    text: 'Moved 500 dollars from checking to savings',
    ask: {.intent, .account, .toAccount, .needsFollowup},
    parsed: DecideParsed(amountMinor: 50000, currency: 'USD'),
    expect: {
      'intent': 'transfer|savings_move',
      'account': 'm2Rt6YwN8qZ3vB7xL4cC',
      'to_account': 's4Hn6Tq2Rm8Wz1Kc3Ye5',
    },
  ),
  (
    text: 'Withdrew 200 dollars cash from checking',
    ask: {.intent, .account, .toAccount, .needsFollowup},
    parsed: DecideParsed(amountMinor: 20000, currency: 'USD'),
    expect: {
      'intent': 'transfer',
      'account': 'm2Rt6YwN8qZ3vB7xL4cC',
      'to_account': 'p9Xe4HcJ7uS2fD5gK1oB',
    },
  ),
  (
    text: "Gave Alex 300 dollars, he'll pay me back next week",
    ask: {.intent, .person, .repayable, .account},
    parsed: DecideParsed(amountMinor: 30000, currency: 'USD'),
    expect: {'intent': 'loan_given', 'person': 'pAlex01'},
  ),
  (
    text: 'Sent my mother 100,000 dinars this month',
    ask: {.intent, .category, .person, .repayable},
    parsed: DecideParsed(amountMinor: 100000, currency: 'IQD'),
    expect: {'category': 'family_support', 'person': 'pMom01'},
  ),
  (
    text: 'Bought bread 2,000 dinars',
    ask: {.intent, .category, .person, .duplicate},
    parsed: DecideParsed(amountMinor: 2000, currency: 'IQD'),
    expect: {'category': 'bakery_tea', 'person': 'none'},
  ),
  (
    text: 'Topped up my phone 10,000 dinars',
    ask: {.intent, .category, .isRecurring},
    parsed: DecideParsed(amountMinor: 10000, currency: 'IQD'),
    expect: {'category': 'phone_mobile_credit'},
  ),
  (
    text: 'Netflix 15.99 on my checking account',
    ask: {.intent, .category, .account, .isRecurring},
    parsed: DecideParsed(amountMinor: 1599, currency: 'USD'),
    expect: {
      'category': 'online_subscriptions',
      'account': 'm2Rt6YwN8qZ3vB7xL4cC',
    },
  ),
  (
    text: 'Paid the generator guy 50,000 dinars for this month',
    ask: {.intent, .category, .isRecurring, .duplicate},
    parsed: DecideParsed(amountMinor: 50000, currency: 'IQD'),
    expect: {'category': 'electricity_generator'},
  ),
];

Future<void> main() async {
  final key = SecretManagerKey();
  await key.current();
  stdout
    ..writeln('# WP-33 live check, ${DateTime.now().toUtc()}')
    ..writeln('Secret version used: ${key.version} (latest at start).');

  final store = MemoryStore();
  final client = http.Client();
  final ai = Genkit(plugins: [googleAI(apiKey: key._key)], isDevEnv: false);
  final usage = UsageCounters(store);
  DecisionsClassifier classifier(ApiKeySource keys) => DecisionsClassifier(
    api: DecisionsApi(http: client, keys: keys),
    households: FixtureSource(),
    config: RuntimeConfigLoader(store),
    usage: usage,
    fallback: GenkitFallbackClassifier(ai),
  );

  // 1. A stale key: rejected, re-read, answered.
  final rotating = SecretManagerKey();
  final staleFirst = classifier(StaleThenFresh(rotating));
  final r0 = await staleFirst.classify(
    context: _ctx,
    text: 'Taxi 5,000',
    ask: {.intent},
    parsed: DecideParsed(amountMinor: 5000, currency: 'IQD'),
  );
  stdout.writeln(
    '\n## Key re-read\nstale key → ${r0.intent?.choice} '
    '(calibrated ${r0.calibrated}); secret re-reads: ${rotating.reads}',
  );

  // 2. The cases through the full classifier.
  final c = classifier(key);
  var right = 0;
  var scored = 0;
  stdout
    ..writeln('\n## Decisions answers\n')
    ..writeln('| message | questions | answers | input tokens | ms |')
    ..writeln('|---|---|---|---|---|');
  for (final k in cases) {
    final tokensBefore = _tokens(store);
    final watch = Stopwatch()..start();
    final r = await c.classify(
      context: _ctx,
      text: k.text,
      ask: k.ask,
      parsed: k.parsed,
    );
    watch.stop();
    final json = r.toJson();
    final parts = <String>[];
    for (final q in DecideQuestion.values) {
      final a = json[q.key];
      if (a is! Map) continue;
      final shown =
          a['choice'] ??
          'P(yes) ${(a['probability'] as num).toStringAsFixed(2)}';
      final conf = (a['confidence'] as num?)?.toStringAsFixed(2) ?? '?';
      final want = k.expect[q.key];
      var mark = '';
      if (want != null) {
        scored++;
        final ok = want.split('|').contains(a['choice']);
        if (ok) right++;
        mark = ok ? ' ✓' : ' ✗ (want $want)';
      }
      parts.add('${q.key}: $shown ($conf)$mark');
    }
    if (r.duplicateOf case final id?) parts.add('duplicate_of: $id');
    if (r.unavailable ?? false) parts.add('UNAVAILABLE');
    if (r.calibrated == false) parts.add('UNCALIBRATED');
    stdout.writeln(
      '| ${k.text} | ${k.ask.length} | ${parts.join('; ')} | '
      '${_tokens(store) - tokensBefore} | ${watch.elapsedMilliseconds} |',
    );
  }
  stdout.writeln('\nScored answers right: $right/$scored');

  // 3. Cache: the first case again.
  final watch = Stopwatch()..start();
  final before = store.docs.values.fold<int>(
    0,
    (s, d) => s + ((d['decisions'] as int?) ?? 0),
  );
  await c.classify(
    context: _ctx,
    text: cases.first.text,
    ask: cases.first.ask,
    parsed: cases.first.parsed,
  );
  final after = store.docs.values.fold<int>(
    0,
    (s, d) => s + ((d['decisions'] as int?) ?? 0),
  );
  stdout.writeln(
    '\n## Cache\nrepeat of case 1: ${watch.elapsedMilliseconds} ms, '
    'decisions counted before/after: $before/$after',
  );

  // 4. An invalid request, live: an unknown top-level field.
  final api = DecisionsApi(http: client, keys: key);
  final bad = await api.send({
    'model': 'gemini-decision-1',
    'input': 'x',
    'questions': {
      'q': {'type': 'noul', 'instructions': 'Is this a test?'},
    },
    'generationConfig': <String, Object?>{},
  });
  stdout.writeln('\n## Error shapes\nunknown field → ${_describe(bad)}');
  final badModel = await api.send({
    'model': 'gemini-decision-0',
    'input': 'x',
    'questions': {
      'q': {'type': 'noul', 'instructions': 'Is this a test?'},
    },
  });
  stdout.writeln('unknown model → ${_describe(badModel)}');

  // 5. The fallback on its own, on case 2's plan.
  final profile = await FixtureSource().profile(hid: 'h', uid: 'uDara');
  for (final k in [cases[0], cases[1], cases[3]]) {
    final plan = buildPlan(
      profile: profile,
      speakerUid: 'uDara',
      today: (year: 2026, month: 11, day: 22),
      text: k.text,
      ask: k.ask,
      parsed: k.parsed,
    );
    final watch = Stopwatch()..start();
    final f = await GenkitFallbackClassifier(ai)
        .answer(plan, model: RuntimeConfig.defaults.model('decideFallback'));
    stdout.writeln(
      '\n## Fallback (${RuntimeConfig.defaults.model('decideFallback')})\n'
      '${k.text}: ${f?.answers} in ${f?.inputTokens} out ${f?.outputTokens}, '
      '${watch.elapsedMilliseconds} ms',
    );
  }

  final day = store.docs.entries.where((e) => e.key.contains('/usage/'));
  stdout.writeln('\n## Usage counters\n${[for (final e in day) e.value]}');
  client.close();
  await ai.shutdown();
  stdout.writeln('\n$key; ${const Clock().now().toUtc()}');
}

int _tokens(MemoryStore store) => store.docs.values.fold<int>(
  0,
  (sum, d) => sum + ((d['inputTokens'] as int?) ?? 0),
);

String _describe(DecisionOutcome o) => switch (o) {
  DecisionRequestRejected(:final status, :final code, :final message) =>
    'DecisionRequestRejected($status, $code: $message)',
  DecisionKeyRejected(:final status, :final statusText) =>
    'DecisionKeyRejected($status, $statusText)',
  DecisionBlocked(:final status, :final reason) =>
    'DecisionBlocked($status, $reason)',
  DecisionTransient(:final status, :final detail) =>
    'DecisionTransient($status, $detail)',
  DecisionUnexpected(:final status, :final detail) =>
    'DecisionUnexpected($status, $detail)',
  DecisionAnswered() => 'DecisionAnswered',
};
