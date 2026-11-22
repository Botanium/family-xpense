// WP-S1 spike (throwaway). Headless evidence for Q1, Q3, Q4, Q5 (client
// side) and the catalog parity idea. The agent messages are the ones the
// spike server compiled with genkit_a2ui 0.6.0 / a2ui_core 0.7.0, saved in
// ../evidence/q2_compiled_messages.json by bin/compile_express.dart.
// ignore_for_file: deprecated_member_use
import 'dart:convert';
import 'dart:io';

import 'package:a2ui_core/a2ui_core.dart';
import 'package:a2ui_flutter/a2ui_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:json_schema_builder/json_schema_builder.dart' show Schema;
import 'package:wp_s1_client/a2ui_helpers.dart';
import 'package:wp_s1_client/local_builder.dart';
import 'package:wp_s1_client/spike_catalog.dart';

Map<String, dynamic> _compiled() =>
    jsonDecode(File('../evidence/q2_compiled_messages.json').readAsStringSync())
        as Map<String, dynamic>;

List<Map<String, dynamic>> _messages(String name) =>
    ((_compiled()[name] as Map)['messages'] as List)
        .cast<Map<String, dynamic>>();

MessageProcessor<ComponentImplementation> _processor({
  List<ActionMessage>? actions,
  List<String>? errors,
}) => MessageProcessor<ComponentImplementation>(
  catalogs: [spikeCatalog],
  unifiedOutbound: true,
  outboundListener: (m) {
    if (m is ActionMessage) actions?.add(m);
  },
  onError: (e) => errors?.add(e.message),
);

Widget _host(MessageProcessor<ComponentImplementation> p, List<String> ids) =>
    MaterialApp(
      home: Scaffold(
        body: ListView(
          children: [
            for (final id in ids)
              if (p.model.getSurface(id) case final s?)
                A2uiSurface(key: ObjectKey(s), surface: s),
          ],
        ),
      ),
    );

void main() {
  setUp(buildCounts.clear);

  testWidgets('Q1: 0.7-era agent messages render on a2ui_core 0.8 with the '
      'custom catalog', (tester) async {
    final errors = <String>[];
    final p = _processor(errors: errors);
    // deleteSurface for an unknown id, then createSurface with sendDataModel
    // false, bare keys, an array of objects in dataModel.
    p.processMessages(_messages('q2_drafts_array'));
    await tester.pumpWidget(_host(p, ['cap_k3m9']));
    expect(find.text('I found two things in that:'), findsOneWidget);
    expect(find.textContaining('Salary'), findsOneWidget);
    expect(find.textContaining('Rent'), findsOneWidget);
    expect(find.text('  GUESSED'), findsOneWidget);
    expect(errors, isEmpty);

    // A later partial update to one element of the array.
    p.processMessages(_messages('q2_update_element'));
    await tester.pump();
    expect(
      p.model.getSurface('cap_k3m9')!.dataModel.get('/drafts/1/who'),
      'me',
    );
    expect(find.text('who: me'), findsNWidgets(2));
  });

  testWidgets('Q1: a legacy bare "checks" key on a v1.0 Button is read '
      '(0.8 dual-read)', (tester) async {
    final errors = <String>[];
    final p = _processor(errors: errors);
    // As compiled by the 0.7 server: `checks` bare, function call `@call`.
    final msgs = _messages('q1_checks_bare');
    final create = msgs.last['createSurface'] as Map;
    expect((create['components'] as List).first, contains('checks'));
    p.processMessages(msgs);
    await tester.pumpWidget(_host(p, ['legacy_keys']));
    expect(find.text('Go'), findsOneWidget);
    expect(errors, isEmpty);
    // The check was read as a check (not an unknown prop): the empty name
    // fails `required`, so the basic Button is disabled.
    final button = tester.widget<ButtonStyleButton>(
      find.byWidgetPredicate((w) => w is ButtonStyleButton),
    );
    expect(button.onPressed, isNull);
    p.model.getSurface('legacy_keys')!.dataModel.set('/name', 'Ada');
    await tester.pump();
    expect(
      tester
          .widget<ButtonStyleButton>(
            find.byWidgetPredicate((w) => w is ButtonStyleButton),
          )
          .onPressed,
      isNotNull,
    );
  });

  testWidgets('Q3: ChoicePrompt writes the bound path and its sibling '
      'EntryList re-renders; EntryList writes back through its own binding', (
    tester,
  ) async {
    final actions = <ActionMessage>[];
    final p = _processor(actions: actions);
    p.processMessages(_messages('q2_choice_prompt'));
    await tester.pumpWidget(_host(p, ['cap_p7x2']));
    final model = p.model.getSurface('cap_p7x2')!.dataModel;
    expect(find.text('LOAN_GIVEN · —'), findsOneWidget);
    final listBuildsBefore = buildCounts['list']!;

    await tester.tap(find.byKey(const ValueKey('choice_expense')));
    await tester.pump();
    expect(model.get('/drafts/0/intent'), 'expense');
    expect(find.text('EXPENSE · —'), findsOneWidget);
    expect(buildCounts['list']!, greaterThan(listBuildsBefore));
    // No action on this ChoicePrompt, so nothing goes to the agent.
    expect(actions, isEmpty);

    // EntryList writes the whole array back through writable('drafts').
    await tester.tap(find.byKey(const ValueKey('toggleWho_0')));
    await tester.pump();
    expect(model.get('/drafts/0/who'), 'joint');
    expect(find.text('who: joint'), findsOneWidget);
  });

  testWidgets('Q3/Q5: a ChoicePrompt with an action emits it with the '
      'picked value echoed in its context', (tester) async {
    final actions = <ActionMessage>[];
    final p = _processor(actions: actions);
    p.processMessages(_messages('q5_choice_with_action'));
    await tester.pumpWidget(_host(p, ['cap_q1']));
    await tester.tap(find.byKey(const ValueKey('choice_acc_cash')));
    await tester.pumpAndSettle();
    expect(actions, hasLength(1));
    final a = actions.single.action;
    expect(a.name, 'xp.answer');
    expect(a.context, {'field': 'accountId', 'value': 'acc_cash'});

    // Client side of Q5: the action and typed text in one user message.
    final msg = a2uiActionToMessage(actions.single, text: 'and it was cash');
    final json = msg.toJson();
    debugPrint('Q5 outbound message: ${jsonEncode(json)}');
    expect((json['content'] as List), hasLength(2));
  });

  testWidgets('Q4: a local raw-map createSurface (components + dataModel) '
      'renders in the same processor beside an agent surface', (tester) async {
    final errors = <String>[];
    final p = _processor(errors: errors);
    p.processMessages(_messages('q2_drafts_array'));
    p.processMessages(localCaptureSurface());
    await tester.pumpWidget(_host(p, ['cap_k3m9', 'local_cap_1']));
    expect(find.text('I found two things in that:'), findsOneWidget);
    expect(find.text('Built on the phone'), findsOneWidget);
    expect(find.textContaining('Lunch with the kids'), findsOneWidget);
    expect(find.text('missing: accountId'), findsOneWidget);
    expect(errors, isEmpty);
    expect(p.model.getSurface('cap_k3m9'), isNotNull);
    expect(p.model.getSurface('local_cap_1'), isNotNull);
  });

  test('parity: the JSON catalog and the Dart implementations agree', () {
    final json = jsonDecode(
      File('../catalog/spike_catalog.json').readAsStringSync(),
    ) as Map<String, Object?>;
    final fromJson = Catalog.fromJson(json);
    expect(fromJson.id, spikeCatalog.id);
    expect(
      fromJson.components.keys.toSet(),
      spikeCatalog.components.keys.toSet(),
    );
    for (final name in ['EntryList', 'ChoicePrompt']) {
      Set<String> props(Schema s) =>
          ((s.value['properties'] as Map?)?.keys.cast<String>().toSet() ??
                <String>{})
            ..remove('component');
      expect(
        props(spikeCatalog.components[name]!.schema),
        props(fromJson.components[name]!.schema),
        reason: name,
      );
    }
  });
}
