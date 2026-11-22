// WP-S1 spike (throwaway). Compiles Express blocks offline against the spike
// catalog with genkit_a2ui 0.6.0 (a2ui_agent 0.3.0, a2ui_core 0.7.0) and
// writes the compiled A2UI messages to ../evidence/q2_compiled_messages.json,
// so the questions about Express can be answered from output.
//
//   dart run bin/compile_express.dart
import 'dart:convert';
import 'dart:io';

import 'package:genkit_a2ui/a2ui.dart';

const _blocks = <String, String>{
  // Q2: an array of objects assigned to $/drafts, then bound by EntryList.
  'q2_drafts_array': r'''
surface("cap_k3m9")
$/drafts = [
  {id: "d1", intent: "income", amountMinor: 320000, currency: "USD", categoryId: "salary",
   accountId: "acc_chk", who: "me", occurredOn: "2026-11-22", title: "Salary",
   confidence: {intent: 0.99, category: 0.97, account: 0.96}},
  {id: "d2", intent: "expense", amountMinor: 140000, currency: "USD", categoryId: "rent",
   accountId: "acc_chk", who: "joint", occurredOn: "2026-11-22", title: "Rent",
   confidence: {intent: 0.98, category: 0.99, account: 0.97}, guessed: ["who"]}
]
root = EntryList($/drafts, "review", "I found two things in that:")
''',
  // Q2/Q3: ChoicePrompt writing into an element of the array.
  'q2_choice_prompt': r'''
surface("cap_p7x2")
$/drafts = [{id: "d1", intent: "loan_given", amountMinor: 30000, currency: "USD",
  personName: "Alex", accountId: "acc_chk", occurredOn: "2026-11-22", missing: ["intent"]}]
root = Column([ask, list])
ask = ChoicePrompt("Quick check, so I file it right: will Alex pay this back?",
  [{label: "Yes, it's a loan", value: "loan_given", hint: "Alex owes us"},
   {label: "No, gift or payment", value: "expense", hint: "Expense"},
   {label: "I was paying Alex back", value: "repayment_made", hint: "Debt"}],
  $/drafts/0/intent)
list = EntryList($/drafts)
''',
  // Models often write JSON-style quoted keys, null and booleans.
  'q2_quoted_keys_null_bool': r'''
surface("cap_json")
$/drafts = [{"id": "d1", "intent": "expense", "amountMinor": 250, "currency": "IQD",
  "accountId": null, "missing": ["accountId"], "duplicate": false, "fx": {"pairRate": "1705"}}]
root = EntryList($/drafts)
''',
  // Q1: the server writes component `checks` bare (a2ui_core 0.7); the
  // 0.8 renderer must dual-read it.
  'q1_checks_bare': r'''
surface("legacy_keys")
$/name = ""
root = Button(label, "primary", Event("go", {name: $/name}), _, [?required($/name, "Name is required")])
label = Text("Go")
''',
  // A partial update of one element of the array (no root).
  'q2_update_element': r'''
surface("cap_k3m9")
$/drafts/1/who = "me"
''',
  // Q4 follow-up: the agent updating a surface the PHONE built. The server
  // has no record of it, so strict validation should reject the block.
  'q4_update_local_surface': r'''
surface("local_cap_1")
$/drafts/0/accountId = "acc_cash"
''',
  // ... while a full re-render of that id (with root) is accepted, and
  // replaces the phone's surface (deleteSurface + createSurface).
  'q4_rerender_local_surface': r'''
surface("local_cap_1")
$/drafts = [{id: "d1", intent: "expense", amountMinor: 10000, currency: "IQD", accountId: "acc_cash"}]
root = EntryList($/drafts)
''',
  // A ChoicePrompt with an action that echoes the picked value.
  'q5_choice_with_action': r'''
surface("cap_q1")
$/drafts = [{id: "d1", intent: "expense", amountMinor: 1200, currency: "USD"}]
root = ChoicePrompt("Which account?", [{label: "Checking", value: "acc_chk"},
  {label: "Cash", value: "acc_cash"}], $/drafts/0/accountId,
  false, Event("xp.answer", {field: "accountId", value: $/drafts/0/accountId}))
''',
  // An object (not array) assigned to a path, as for analytics answers.
  'q2_result_object': r'''
surface("ans_food_nov")
$/result = {total: 48650, rows: [{label: "Groceries", amountMinor: 38600, share: 0.79},
  {label: "Dining", amountMinor: 10050, share: 0.21}]}
root = Column([head, list])
head = Text("Food in November")
list = EntryList($/result/rows)
''',
};

Future<void> main() async {
  final catalogFile = File('../catalog/spike_catalog.json');
  final catalog = A2uiCatalog.fromJson(
    (jsonDecode(await catalogFile.readAsString()) as Map)
        .cast<String, dynamic>(),
  );
  final out = Directory('../evidence')..createSync(recursive: true);

  final results = <String, Object?>{};
  // History accumulates so the element update can target the live surface.
  final history = <A2uiEnvelope>[];
  for (final MapEntry(key: name, value: source) in _blocks.entries) {
    final parser = A2uiStreamParser(
      catalog: catalog,
      validate: A2uiValidateMode.strict,
      history: List.of(history),
    );
    try {
      final r1 = parser.push('<a2ui>\n$source</a2ui>');
      final r2 = parser.flush();
      final envelopes = [
        for (final s in [...r1.segments, ...r2.segments])
          if (s is EnvelopeSegment) ...s.envelopes,
      ];
      history.addAll(envelopes);
      results[name] = {'ok': true, 'source': source, 'messages': envelopes};
      stdout.writeln('$name: OK, ${envelopes.length} messages');
    } on Object catch (e) {
      results[name] = {'ok': false, 'source': source, 'error': '$e'};
      stdout.writeln('$name: FAILED: $e');
    }
  }
  File('${out.path}/q2_compiled_messages.json')
      .writeAsStringSync(const JsonEncoder.withIndent('  ').convert(results));
}
