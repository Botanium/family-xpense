// The same message gives the same card on every path (WP-34): the slip
// the local builder makes for a path D message, and the agent's surface
// carrying the same drafts (`fixtures/agent_single_entry.json`, in the
// shape `prepareEntries` and the a2ui middleware emit), match one golden.
//
// Record with `flutter test --update-goldens test/ask` on a Mac; never in
// CI.
import 'dart:convert';
import 'dart:io';

import 'package:clock/clock.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:xpense_app/a2ui/testing/fake_xpense_actions.dart';
import 'package:xpense_app/features/capture/router/confidence_policy.dart';
import 'package:xpense_app/features/capture/router/draft_builder.dart';
import 'package:xpense_app/services/feature_flags.dart';
import 'package:xpense_shared/xpense_shared.dart';

import '../a2ui/a2ui_harness.dart';
import '../ui/ui_harness.dart' show goldensSupported, loadSignalFonts;

const _text = 'spent 42.80 dollars at Costco';

final _answers = DecideResponse(
  intent: ChoiceAnswer(
    choice: 'expense',
    confidence: 0.97,
    probabilities: {'expense': 0.97},
  ),
  category: ChoiceAnswer(choice: 'groceries', confidence: 0.70),
  account: ChoiceAnswer(choice: 'acc_chk', confidence: 0.95),
  who: ChoiceAnswer(choice: 'me', confidence: 0.9),
);

EntryDraft _localDraft() {
  final clock = Clock.fixed(DateTime(2026, 11, 22, 14));
  return buildDraft(
    id: 'd1',
    raw: _text,
    parse: parseText(_text, parseContextFor(sampleHousehold, clock: clock)),
    household: sampleHousehold,
    policy: const ConfidencePolicy(CaptureThresholds.defaults),
    decide: _answers,
  );
}

List<Map<String, Object?>> _agentFixture() => (jsonDecode(
  File('test/ask/fixtures/agent_single_entry.json').readAsStringSync(),
) as List<Object?>).cast<Map<String, Object?>>();

Map<String, Object?> _shown(Map<String, Object?> draft) =>
    Map.of(draft)..remove('origin');

void main() {
  setUpAll(loadSignalFonts);

  test('the agent fixture carries the drafts the local path builds, apart '
      'from where they came from', () {
    final agent = _agentFixture()
        .map((m) => m['createSurface'])
        .whereType<Map<String, Object?>>()
        .single;
    final drafts = (agent['dataModel']! as Map)['drafts']! as List;
    expect(
      _shown((drafts.single as Map).cast<String, Object?>()),
      _shown(_localDraft().toJson()),
    );
  });

  for (final brightness in Brightness.values) {
    final golden = 'goldens/same_card_${brightness.name}.png';
    testWidgets(
      'local builder: one golden ($brightness)',
      skip: !goldensSupported,
      (tester) => withClock(Clock.fixed(DateTime(2026, 11, 22, 14)), () async {
        final local = captureSurface(
          surfaceId: '${localSurfacePrefix}cap_1',
          drafts: [_localDraft()],
        );
        final (:host, :actions, :sent) = hostWith(local);
        await pumpThread(tester, host, brightness: brightness);
        await expectLater(find.byKey(goldenKey), matchesGoldenFile(golden));
      }),
    );
    testWidgets(
      'agent fixture: the same golden ($brightness)',
      skip: !goldensSupported,
      (tester) => withClock(Clock.fixed(DateTime(2026, 11, 22, 14)), () async {
        final (:host, :actions, :sent) = hostWith(_agentFixture());
        await pumpThread(tester, host, brightness: brightness);
        await expectLater(find.byKey(goldenKey), matchesGoldenFile(golden));
      }),
    );
  }
}
