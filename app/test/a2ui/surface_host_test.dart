// XpenseSurfaceHost (ARCHITECTURE 7, story S3.4): one processor and one
// ordered queue per conversation, local and agent surfaces in one thread,
// per-message error isolation, and action routing by name.
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:xpense_app/a2ui/testing/fake_xpense_actions.dart';
import 'package:xpense_shared/xpense_shared.dart';

import 'a2ui_harness.dart';

Map<String, Object?> _create(
  String surfaceId,
  List<Map<String, Object?>> components, [
  Map<String, Object?>? dataModel,
]) => {
  'version': '1.0',
  'createSurface': {
    'surfaceId': surfaceId,
    'catalogId': xpenseCatalogId,
    'components': components,
    'dataModel': ?dataModel,
  },
};

Map<String, Object?> _button(String id, String event, {String label = 'Go'}) =>
    _create(id, [
      {
        'id': 'root',
        'component': 'Button',
        'child': 'label',
        'variant': 'primary',
        'action': {
          'event': {
            'name': event,
            'context': {'topic': 'rate'},
          },
        },
      },
      {'id': 'label', 'component': 'Text', 'text': label},
    ]);

void main() {
  group('one thread', () {
    testWidgets('local and agent surfaces share one processor, in order', (
      tester,
    ) async {
      final agent = fixture('agent_two_entries');
      final local = fixture('local_capture_missing_account');
      final (:host, :actions, :sent) = hostWith([...agent, ...local]);
      expect(host.surfaceIds, ['cap_k3m9', 'loc_cap_k3m9']);
      await pumpThread(tester, host);
      expect(find.text('I found two things in that:'), findsOneWidget);
      expect(find.textContaining('Spent ten thousand dinars'), findsOneWidget);
      expect(host.failedMessages, 0);
    });

    testWidgets('a re-rendered agent surface keeps its place', (tester) async {
      final first = fixture('agent_analytics_answer');
      final (:host, :actions, :sent) = hostWith([
        ...first,
        ...fixture('local_saved_note'),
      ]);
      // genkit_a2ui sends deleteSurface then createSurface for a re-render.
      host.addMessages(first);
      expect(host.surfaceIds, ['ans_food_nov', 'loc_saved_two']);
      await pumpThread(tester, host);
      expect(find.text('Food in November'), findsOneWidget);
    });

    test('a deleteSurface for an unknown id is ignored', () {
      final (:host, :actions, :sent) = hostWith([
        {
          'version': '1.0',
          'deleteSurface': {'surfaceId': 'never_made'},
        },
      ]);
      expect(host.failedMessages, 0);
    });
  });

  group('one bad message never stops a turn', () {
    testWidgets('bad messages are skipped and counted; the rest renders', (
      tester,
    ) async {
      final (:host, :actions, :sent) = hostWith([
        _create('first', [
          {'id': 'root', 'component': 'Text', 'text': 'Before'},
        ]),
        {'garbage': true},
        {
          'version': '1.0',
          'createSurface': {
            'surfaceId': 'other_catalog',
            'catalogId': 'https://example.com/unknown.json',
            'components': const <Object?>[],
          },
        },
        {
          'version': '1.0',
          'updateComponents': {
            'surfaceId': 'not_created',
            'components': [
              {'id': 'root', 'component': 'Text', 'text': 'x'},
            ],
          },
        },
        _create('second', [
          {'id': 'root', 'component': 'Text', 'text': 'After'},
        ]),
      ]);
      expect(host.failedMessages, 3);
      expect(host.surfaceIds, ['first', 'second']);
      await pumpThread(tester, host);
      expect(find.text('Before'), findsOneWidget);
      expect(find.text('After'), findsOneWidget);
    });

    testWidgets('an unknown component is skipped; its siblings render', (
      tester,
    ) async {
      final (:host, :actions, :sent) = hostWith([
        _create('mixed', [
          {
            'id': 'root',
            'component': 'Column',
            'children': ['known', 'future'],
          },
          {'id': 'known', 'component': 'Text', 'text': 'Still here'},
          {'id': 'future', 'component': 'Hologram', 'text': 'from v2'},
        ]),
      ]);
      await pumpThread(tester, host);
      expect(find.text('Still here'), findsOneWidget);
      expect(find.text('from v2'), findsNothing);
      expect(host.failedMessages, 0);
      expect(
        host.issues.map((i) => i.code),
        contains('UNKNOWN_COMPONENT_TYPE'),
      );
    });
  });

  group('action routing', () {
    testWidgets('xp.local. actions call XpenseActions, never the agent', (
      tester,
    ) async {
      final (:host, :actions, :sent) = hostWith(fixture('local_nudge_bill'));
      await pumpThread(tester, host);
      await tester.tap(find.text('Add'));
      await tester.pump();
      expect(actions.calls.single.method, 'sendText');
      expect(
        actions.calls.single.argument,
        'Paid the internet bill, 45 dollars',
      );
      expect(sent, isEmpty);
    });

    testWidgets('other actions go to the agent with their payload', (
      tester,
    ) async {
      final (:host, :actions, :sent) = hostWith([
        _button('ask_rate', 'xp.more'),
      ]);
      await pumpThread(tester, host);
      await tester.tap(find.text('Go'));
      await tester.pump();
      expect(sent, hasLength(1));
      expect(sent.single.name, 'xp.more');
      expect(sent.single.context, {'topic': 'rate'});
      final message = (sent.single.payload['messages']! as List).single as Map;
      expect(message['version'], '1.0');
      expect((message['action']! as Map)['name'], 'xp.more');
      expect(actions.calls, isEmpty);
    });

    testWidgets('the dummy click is dropped', (tester) async {
      final (:host, :actions, :sent) = hostWith([_button('dummy', 'click')]);
      await pumpThread(tester, host);
      await tester.tap(find.text('Go'));
      await tester.pump();
      expect(sent, isEmpty);
      expect(host.issues.single.code, 'DROPPED_ACTION');
    });

    testWidgets('while a turn streams, agent actions are disabled and '
        'ignored; local ones still work', (tester) async {
      final (:host, :actions, :sent) = hostWith([
        _button('ask_rate', 'xp.more'),
        _button('local_btn', 'xp.local.retakeReceipt', label: 'Retake'),
      ]);
      host.turnInProgress = true;
      await pumpThread(tester, host);
      await tester.tap(find.text('Go'));
      await tester.tap(find.text('Retake'));
      await tester.pump();
      expect(sent, isEmpty);
      expect(actions.methods, ['retakeReceipt']);

      host.turnInProgress = false;
      await tester.pump();
      await tester.tap(find.text('Go'));
      await tester.pump();
      expect(sent, hasLength(1));
    });

    testWidgets('a ChoicePrompt pick without an action starts no turn', (
      tester,
    ) async {
      final (:host, :actions, :sent) = hostWith(
        fixture('local_capture_intent_question'),
      );
      await pumpThread(tester, host);
      await tester.tap(find.text('No, gift or payment'));
      await tester.pump();
      expect(sent, isEmpty);
      expect(actions.calls, isEmpty);
    });
  });

  testWidgets('after a save, xp.saved carries the draft and txn ids once', (
    tester,
  ) async {
    final (:host, :actions, :sent) = hostWith(fixture('agent_two_entries'));
    await pumpThread(tester, host);
    await tester.tap(find.text('Save both'));
    await tester.pumpAndSettle();
    final saved = host.takeSavedActions();
    expect(saved, hasLength(1));
    expect(saved.single.name, 'xp.saved');
    expect(saved.single.surfaceId, 'cap_k3m9');
    expect(saved.single.context, {
      'draftIds': ['d1', 'd2'],
      'txnIds': ['t_1_0', 't_1_1'],
    });
    expect(host.takeSavedActions(), isEmpty);
  });

  testWidgets('an undone save is not reported to the agent', (tester) async {
    final (:host, :actions, :sent) = hostWith(fixture('agent_two_entries'));
    await pumpThread(tester, host);
    await tester.tap(find.text('Save both'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(host.takeSavedActions(), isEmpty);
  });

  testWidgets('a failed undo still reports the save to the agent', (
    tester,
  ) async {
    final (:host, :actions, :sent) = hostWith(
      fixture('agent_two_entries'),
      actions: FakeXpenseActions()..undoError = StateError('offline'),
    );
    await pumpThread(tester, host);
    await tester.tap(find.text('Save both'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isA<StateError>());
    expect(host.takeSavedActions(), hasLength(1));
  });

  testWidgets('an agent update after a local edit keeps the edit', (
    tester,
  ) async {
    final (:host, :actions, :sent) = hostWith(fixture('agent_two_entries'));
    await pumpThread(tester, host);
    // Local edit: Rent's "who" from joint to you.
    await tester.tap(find.text('JOINT'));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('pick_who_me')));
    await tester.pump();
    host.addMessages([
      {
        'version': '1.0',
        'updateDataModel': {
          'surfaceId': 'cap_k3m9',
          'path': '/drafts/1/title',
          'value': 'Rent, November',
        },
      },
    ]);
    await tester.pump();
    expect(find.text('JOINT'), findsNothing);
    expect(find.text('YOU'), findsNWidgets(2));
  });
}
