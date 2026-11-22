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
import 'package:xpense_agent/tools/household_snapshot.dart';
import 'package:xpense_shared/xpense_shared.dart';

import '../tools/support.dart';
import 'scripted_model.dart';

Future<({XpenseAgentRuntime rt, Genkit ai, List<String> turns})> _runtime({
  required Script lite,
  Script? flash,
  Map<String, Object?> config = const {},
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
    onTurn: (c, r) => turns.add('${c.hid}:${r.finishReason.value}'),
  );
  return (rt: rt, ai: ai, turns: turns);
}

List<Map<String, dynamic>> _creates(Map<String, dynamic> summary) => [
  for (final m in summary['a2ui'] as List)
    if ((m as Map)['createSurface'] case final Map<String, dynamic> c) c,
];

void main() {
  test('a two-entry capture produces one EntryList surface', () async {
    final lite = Script(entries: salaryRent, render: scriptedCapture);
    final (:rt, ai: _, :turns) = await _runtime(lite: lite);
    expect(rt.strict, isTrue);

    final summary = await rt.runTurn(
      'Salary came in 3200 and I paid rent 1400',
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
    expect(turns, ['hh_demo:stop']);

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

  test('outputGuard drops a draft whose amount the model changed', () async {
    final lite = Script(
      entries: salaryRent,
      render: (drafts) => scriptedCapture([
        drafts[0],
        {...(drafts[1]! as Map), 'amountMinor': 1400000},
      ]),
    );
    final (:rt, ai: _, turns: _) = await _runtime(lite: lite);
    final summary = await rt.runTurn(
      'Salary came in 3200 and I paid rent 1400',
      context: demoContext,
    );
    final drafts =
        (_creates(summary).single['dataModel'] as Map)['drafts'] as List;
    expect(drafts.single, containsPair('id', 'd1'));
  });

  test('a failed turn is re-run once on the escalation model', () async {
    final lite = Script(
      entries: salaryRent,
      render: (_) => '<a2ui>\nsurface("cap_bad")\nroot = Chart("x")\n</a2ui>',
    );
    final flash = Script(entries: salaryRent, render: scriptedCapture);
    final (:rt, ai: _, :turns) = await _runtime(lite: lite, flash: flash);
    final summary = await rt.runTurn(
      'Salary came in 3200 and I paid rent 1400',
      context: demoContext,
    );
    expect(_creates(summary).single['surfaceId'], 'cap_test');
    expect(lite.requests, hasLength(2));
    expect(flash.requests, hasLength(2));
    expect(turns, ['hh_demo:stop']);
  });

  test('liteOnly stops escalation', () async {
    final lite = Script(
      entries: salaryRent,
      render: (_) => '<a2ui>\nsurface("cap_bad")\nroot = Chart("x")\n</a2ui>',
    );
    final flash = Script(entries: salaryRent, render: scriptedCapture);
    final (:rt, ai: _, :turns) = await _runtime(
      lite: lite,
      flash: flash,
      config: {
        'switches': {'liteOnly': true},
      },
    );
    await rt
        .runTurn(
          'Salary came in 3200 and I paid rent 1400',
          context: demoContext,
        )
        .then((_) {}, onError: (_) {});
    expect(flash.requests, isEmpty);
    expect(turns, ['hh_demo:failed']);
  });

  test('a later turn resumes the session by snapshot id', () async {
    final lite = Script(entries: salaryRent, render: scriptedCapture);
    final (:rt, ai: _, turns: _) = await _runtime(lite: lite);
    final first = await rt.runTurn(
      'Salary came in 3200 and I paid rent 1400',
      context: demoContext,
    );
    await rt.runTurn(
      'Actually rent was 1400 too',
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
    expect(texts.last, 'Actually rent was 1400 too');
  });

  test('a turn without the verified context is refused', () async {
    final lite = Script(entries: salaryRent, render: scriptedCapture);
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
          content: [TextPart(text: 'rent 1400')],
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
      expect(texts.first, 'rent 1400');
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
