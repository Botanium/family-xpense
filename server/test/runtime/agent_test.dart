// The agent end to end with scripted models: the real prompt files,
// middleware chain, a2ui (strict), tools and session store; only the model
// is fake. Live-model runs are in the WP-32 PR (traces).

import 'package:genkit/genkit.dart';
import 'package:genkit_a2ui/a2ui.dart';
import 'package:test/test.dart';
import 'package:xpense_agent/auth/xpense_context.dart';
import 'package:xpense_agent/catalog/xpense_catalog_loader.dart';
import 'package:xpense_agent/config/runtime_config.dart';
import 'package:xpense_agent/decide/classifier.dart';
import 'package:xpense_agent/runtime/agent.dart';
import 'package:xpense_agent/runtime/demo_household.dart';
import 'package:xpense_agent/runtime/household_context.dart';
import 'package:xpense_agent/telemetry/usage_counters.dart';
import 'package:xpense_agent/tools/household_snapshot.dart';
import 'package:xpense_shared/xpense_shared.dart';

import '../tools/support.dart';
import 'scripted_model.dart';

Future<({XpenseAgentRuntime rt, Genkit ai, List<String> turns})> _runtime({
  required Script lite,
  Script? flash,
  Map<String, Object?> config = const {},
  UsageReader? usage,
}) async {
  final ai = Genkit(plugins: [A2uiPlugin()], promptDir: 'prompts');
  defineScripted(ai, 'test/lite', lite);
  defineScripted(ai, 'test/flash', flash ?? lite);
  final turns = <String>[];
  final rt = XpenseAgentRuntime.create(
    ai: ai,
    catalogJson: await readCatalogJson(),
    reader: demoReader('2026-11-22'),
    classifier: FakeEntryClassifier(),
    config: () async => RuntimeConfig.fromDocument(<String, Object?>{
      'models': const {'agent': 'lite', 'escalation': 'flash'},
      ...config,
    }),
    sessions: const MemorySessions(),
    modelName: (id) => 'test/$id',
    clock: fixedClock,
    usage: usage,
    onTurn: (c, r) => turns.add(
      '${c.hid}:${r.finishReason?.value}:${r.modelCalls}'
      '${r.escalated ? ':escalated' : ''}'
      '${r.images > 0 ? ':images=${r.images}' : ''}'
      '${r.audioSeconds > 0 ? ':audio=${r.audioSeconds}' : ''}',
    ),
  );
  return (rt: rt, ai: ai, turns: turns);
}

/// The drafts in a createSurface's data model.
List<Map<String, dynamic>> _draftsOf(Map<String, dynamic> create) => [
  for (final d in (create['dataModel'] as Map)['drafts'] as List)
    (d as Map).cast<String, dynamic>(),
];

List<Map<String, dynamic>> _creates(Map<String, dynamic> summary) => [
  for (final m in summary['a2ui'] as List)
    if ((m as Map)['createSurface'] case final Map<String, dynamic> c) c,
];

void main() {
  test('a two-entry capture produces one EntryList surface', () async {
    final lite = Script(entries: salaryGroceries, render: scriptedCapture);
    final (:rt, ai: _, :turns) = await _runtime(lite: lite);
    expect(rt.strict, isTrue);

    final summary = await rt.runTurn(
      'Salary came in 3200 and groceries were 1400',
      context: demoContext,
    );
    final create = _creates(summary).single;
    expect(create['surfaceId'], 'cap_test');
    expect(create['catalogId'], xpenseCatalogId);
    final components = create['components'] as List;
    expect(components.single, containsPair('component', 'EntryList'));
    final drafts = (create['dataModel'] as Map)['drafts'] as List;
    expect(
      [for (final d in drafts) (d as Map)['amountMinor']],
      [320000, 140000],
    );
    expect(
      [for (final d in drafts) (d as Map)['accountId']],
      ['acc_chk', 'acc_chk'],
    );
    expect(summary['text'], 'I found two things in that:');
    expect(turns, ['hh_demo:stop:2']);

    // Two model calls: the tool request, then the render.
    expect(lite.requests, hasLength(2));
    final system = lite.requests.first.messages.first;
    expect(system.role, Role.system);
    final text = system.content.map((p) => p.text ?? '').join();
    final household = text.indexOf('<<<household');
    final a2uiRules = text.indexOf('# Rendering UI with A2UI');
    expect(household, greaterThan(0));
    expect(a2uiRules, greaterThan(household));
    expect(
      text,
      contains('Optional actions (this overrides the Express contract)'),
    );
    expect(text, contains('acc_chk | Checking | USD | joint'));
    // The partner's private account is not in the prompt.
    expect(text, isNot(contains('Shilan savings')));
    // The trimmed catalog is what the model sees.
    expect(text, isNot(contains('DateTimeInput(')));
  });

  test(
    "outputGuard restores the tool's drafts and drops invented ones",
    () async {
      List<Object?>? toolDrafts;
      final lite = Script(
        entries: salaryGroceries,
        render: (drafts) {
          toolDrafts = drafts;
          final first = {...(drafts[0]! as Map)}..remove('accountId');
          return scriptedCapture([
            first, // a field dropped while copying
            {...(drafts[1]! as Map), 'amountMinor': 1400000}, // amount changed
            {'id': 'd9', 'intent': 'expense', 'amountMinor': 77700}, // invented
          ]);
        },
      );
      final (:rt, ai: _, turns: _) = await _runtime(lite: lite);
      final summary = await rt.runTurn(
        'Salary came in 3200 and groceries were 1400',
        context: demoContext,
      );
      final drafts =
          (_creates(summary).single['dataModel'] as Map)['drafts'] as List;
      expect(drafts, toolDrafts);
    },
  );

  test('fields the model drops while copying come back', () async {
    List<Object?>? toolDrafts;
    final lite = Script(
      entries: salaryGroceries,
      render: (drafts) {
        toolDrafts = drafts;
        return scriptedCapture([
          for (final d in drafts)
            {...(d! as Map)}
              ..remove('confidence')
              ..remove('origin'),
        ]);
      },
    );
    final (:rt, ai: _, turns: _) = await _runtime(lite: lite);
    final summary = await rt.runTurn(
      'Salary came in 3200 and groceries were 1400',
      context: demoContext,
    );
    final drafts =
        (_creates(summary).single['dataModel'] as Map)['drafts'] as List;
    expect(drafts, toolDrafts);
    expect((drafts.first as Map)['origin'], 'agent');
  });

  group('audio turns (PR #30 review)', () {
    // A voice note carries no typed text: the amounts must come from the
    // transcript the agent showed the member in the same turn.
    final audio = Message(
      role: Role.user,
      content: [
        MediaPart(
          media: Media(
            url: 'data:audio/wav;base64,AAAA',
            contentType: 'audio/wav',
          ),
        ),
      ],
    );
    const generator = [
      {
        'intent': 'expense',
        'amount': '50',
        'currency': 'USD',
        'text': 'paid the generator 50 dollars',
      },
    ];

    test('an amount in the shown transcript is backed', () async {
      final lite = Script(
        entries: generator,
        before:
            '<a2ui>\nsurface("tr_1")\n'
            'root = Transcript("Paid the generator 50 dollars")\n</a2ui>',
        render: scriptedCapture,
      );
      final (:rt, ai: _, turns: _) = await _runtime(lite: lite);
      final res = await rt.agent.chat().send(
        message: audio,
        context: demoContext,
      );
      final capture = _creates(turnSummary(res.message))
          .where((c) => c['surfaceId'] == 'cap_test')
          .single;
      final d = _draftsOf(capture).single;
      expect(d['amountMinor'], 5000);
      expect(d['guessed'] ?? const <Object?>[], isNot(contains('amountMinor')));
      expect(d['missing'] ?? const <Object?>[], isNot(contains('amountMinor')));
    });

    // PR #30 review: a typed correction after a voice note rebuilds the
    // drafts; the amount shown in the earlier turn still backs them.
    test('a typed correction keeps the amount shown earlier', () async {
      final lite = Script(
        entries: generator,
        before:
            '<a2ui>\nsurface("tr_1")\n'
            'root = Transcript("Paid the generator 50 dollars")\n</a2ui>',
        render: scriptedCapture,
      );
      final (:rt, ai: _, turns: _) = await _runtime(lite: lite);
      final first = await rt.agent.chat().send(
        message: audio,
        context: demoContext,
      );
      lite.before = null;
      final chat = await rt.agent.loadChat(
        snapshotId: first.snapshotId,
        context: demoContext,
      );
      final res = await chat.send(
        text: 'actually, that was yesterday',
        context: demoContext,
      );
      final d = _draftsOf(_creates(turnSummary(res.message)).single).single;
      expect(d['amountMinor'], 5000);
      expect(d['missing'] ?? const <Object?>[], isNot(contains('amountMinor')));
    });

    // PR #30 review: the typed correction is the latest member message,
    // so it is what a paraphrased entry falls back to.
    test('a typed correction after a voice note keeps its date', () async {
      final lite = Script(
        entries: generator,
        before:
            '<a2ui>\nsurface("tr_1")\n'
            'root = Transcript("Paid the generator 50 dollars")\n</a2ui>',
        render: scriptedCapture,
      );
      final (:rt, ai: _, turns: _) = await _runtime(lite: lite);
      final first = await rt.agent.chat().send(
        message: audio,
        context: demoContext,
      );
      lite
        ..before = null
        ..entries = const [
          {
            'intent': 'expense',
            'amount': '50',
            'currency': 'USD',
            // A paraphrase, not a span of any one message.
            'text': 'paid the generator 50 dollars yesterday',
            'dateWords': 'yesterday',
          },
        ];
      final chat = await rt.agent.loadChat(
        snapshotId: first.snapshotId,
        context: demoContext,
      );
      final res = await chat.send(
        text: 'actually, that was yesterday',
        context: demoContext,
      );
      final d = _draftsOf(_creates(turnSummary(res.message)).single).single;
      expect(d['occurredOn'], '2026-11-21');
      expect(d['amountMinor'], 5000);
    });

    test('an amount not shown to the member must be confirmed', () async {
      final lite = Script(entries: generator, render: scriptedCapture);
      final (:rt, ai: _, turns: _) = await _runtime(lite: lite);
      final res = await rt.agent.chat().send(
        message: audio,
        context: demoContext,
      );
      final d = _draftsOf(_creates(turnSummary(res.message)).single).single;
      expect(d['amountMinor'], 5000);
      expect(d['guessed'], contains('amountMinor'));
      expect(d['missing'], contains('amountMinor'));
    });
  });

  test('a failed turn is re-run once on the escalation model', () async {
    final lite = Script(
      entries: salaryGroceries,
      render: (_) => '<a2ui>\nsurface("cap_bad")\nroot = Chart("x")\n</a2ui>',
    );
    final flash = Script(entries: salaryGroceries, render: scriptedCapture);
    final (:rt, ai: _, :turns) = await _runtime(lite: lite, flash: flash);
    final summary = await rt.runTurn(
      'Salary came in 3200 and groceries were 1400',
      context: demoContext,
    );
    expect(_creates(summary).single['surfaceId'], 'cap_test');
    expect(lite.requests, hasLength(2));
    expect(flash.requests, hasLength(2));
    expect(turns, ['hh_demo:stop:4:escalated']);
  });

  test('liteOnly stops escalation', () async {
    final lite = Script(
      entries: salaryGroceries,
      render: (_) => '<a2ui>\nsurface("cap_bad")\nroot = Chart("x")\n</a2ui>',
    );
    final flash = Script(entries: salaryGroceries, render: scriptedCapture);
    final (:rt, ai: _, :turns) = await _runtime(
      lite: lite,
      flash: flash,
      config: {
        'switches': {'liteOnly': true},
      },
    );
    await rt
        .runTurn(
          'Salary came in 3200 and groceries were 1400',
          context: demoContext,
        )
        .then((_) {}, onError: (_) {});
    expect(flash.requests, isEmpty);
    expect(turns, ['hh_demo:failed:2']);
  });

  // PR #30 review: the agentEnabled switch stops turns before any model
  // call.
  test(
    'a turn is refused without a model call when the agent is off',
    () async {
      final lite = Script(entries: salaryGroceries, render: scriptedCapture);
      final (:rt, ai: _, :turns) = await _runtime(
        lite: lite,
        config: {
          'switches': {'agentEnabled': false},
        },
      );
      await expectLater(
        rt.runTurn('Salary came in 3200', context: demoContext),
        throwsA(
          isA<Exception>().having(
            (e) => '$e',
            'error',
            'AgentError(UNAVAILABLE): $agentPausedCode',
          ),
        ),
      );
      expect(lite.requests, isEmpty);
      expect(turns, isEmpty);
    },
  );

  // PR #30 review: the images and audioSeconds allowances are checked
  // before any model call and recorded with the turn.
  group('media allowances', () {
    final photo = Message(
      role: Role.user,
      content: [
        MediaPart(
          media: Media(
            url: 'data:image/jpeg;base64,AAAA',
            contentType: 'image/jpeg',
          ),
        ),
        TextPart(text: 'Salary came in 3200'),
      ],
    );
    Future<Map<UsageCounter, int>> Function(String) usedToday(
      Map<UsageCounter, int> used,
    ) =>
        (_) async => used;

    test('a photo at the images limit is refused before the model', () async {
      final lite = Script(entries: salaryGroceries, render: scriptedCapture);
      final (:rt, ai: _, :turns) = await _runtime(
        lite: lite,
        usage: usedToday({UsageCounter.images: 40}),
      );
      await expectLater(
        rt.agent.chat().send(message: photo, context: demoContext),
        throwsA(
          isA<Exception>().having(
            (e) => '$e',
            'error',
            'AgentError(RESOURCE_EXHAUSTED): over_limit',
          ),
        ),
      );
      expect(lite.requests, isEmpty);
      expect(turns, isEmpty);
    });

    test('a photo under the limit is counted with the turn', () async {
      final lite = Script(entries: salaryGroceries, render: scriptedCapture);
      final (:rt, ai: _, :turns) = await _runtime(
        lite: lite,
        usage: usedToday({UsageCounter.images: 39, UsageCounter.agentTurns: 5}),
      );
      await rt.agent.chat().send(message: photo, context: demoContext);
      expect(turns.single, endsWith(':images=1'));
    });

    test('a text turn ignores media allowances already spent', () async {
      final lite = Script(entries: salaryGroceries, render: scriptedCapture);
      final (:rt, ai: _, :turns) = await _runtime(
        lite: lite,
        usage: usedToday({
          UsageCounter.images: 40,
          UsageCounter.audioSeconds: 600,
        }),
      );
      await rt.runTurn('Salary came in 3200', context: demoContext);
      expect(turns.single, 'hh_demo:stop:2');
    });
  });

  test('a later turn resumes the session by snapshot id', () async {
    final lite = Script(entries: salaryGroceries, render: scriptedCapture);
    final (:rt, ai: _, turns: _) = await _runtime(lite: lite);
    final first = await rt.runTurn(
      'Salary came in 3200 and groceries were 1400',
      context: demoContext,
    );
    await rt.runTurn(
      'Actually groceries were 1400 too',
      context: demoContext,
      snapshotId: first['snapshotId'] as String,
    );
    final last = lite.requests.last.messages;
    expect([
      for (final m in last) m.role,
    ], containsAllInOrder([Role.system, Role.user, Role.model, Role.tool]));
    // History replays the surface as Express, and the new text follows.
    final texts = [
      for (final m in last)
        if (m.role == Role.user) m.content.map((p) => p.text).join(),
    ];
    expect(texts.last, 'Actually groceries were 1400 too');
  });

  test('a turn without the verified context is refused', () async {
    final lite = Script(entries: salaryGroceries, render: scriptedCapture);
    final (:rt, ai: _, turns: _) = await _runtime(lite: lite);
    await expectLater(
      rt.runTurn('hi', context: const {'uid': 'u1'}),
      throwsA(anything),
    );
    expect(lite.requests, isEmpty);
  });

  group('helpers', () {
    test('sessions are prefixed per household and member', () {
      expect(sessionPrefix(demoContext), 'hh_demo_u_dara');
      expect(() => sessionPrefix(null), throwsA(isA<GenkitException>()));
    });

    test('conversationTexts reads user text and action contexts', () {
      final texts = conversationTexts([
        Message(
          role: Role.user,
          content: [TextPart(text: 'groceries 1400')],
        ),
        Message(
          role: Role.model,
          content: [TextPart(text: 'ok 999')],
        ),
        Message(
          role: Role.user,
          content: [
            DataPart(
              data: {
                'messages': [
                  {
                    'action': {
                      'name': 'xp.answer',
                      'context': {'text': '1500'},
                    },
                  },
                ],
              },
              metadata: {'mimeType': 'application/a2ui+json'},
            ),
          ],
        ),
      ]);
      expect(texts, hasLength(2));
      expect(texts.first, 'groceries 1400');
      expect(texts.last, contains('1500'));
    });

    test('the household block names labels, never the context', () async {
      final snap = await HouseholdSnapshots(demoReader('2026-11-22'))
          .get(demoHid, demoUid);
      final block = householdBlock(
        snap,
        context: XpenseContext.of(demoContext),
        thresholds: const {},
        today: LocalDate.tryCreate(2026, 11, 22)!,
      );
      expect(block, startsWith('<<<household\ntoday: 2026-11-22 (Sunday)'));
      expect(block, contains('speaking: Dara ("me"); partner: Shilan'));
      expect(block, contains('- expense food: groceries, dining, bakery_tea'));
      expect(block, contains('intent confidence below 0.9 is asked'));
      expect(block, endsWith('household>>>'));
      expect(
        householdBlock(
          null,
          context: XpenseContext.of(demoContext),
          thresholds: const {},
          today: LocalDate.tryCreate(2026, 11, 22)!,
        ),
        contains('Do not record entries'),
      );
    });
  });
}
