// WP-S1 spike (throwaway). A model that streams fixed Express text, chosen
// from the last user message, and records every request it receives (after
// all middleware) to ../evidence/requests/ so the injected text is visible.
import 'dart:convert';
import 'dart:io';

import 'package:genkit/genkit.dart';

int _requestCount = 0;

/// Express replies keyed by a word in the user's message.
String _replyFor(String userText) {
  if (userText.contains('fill the account')) {
    return 'Filed under cash.\n<a2ui>\nsurface("local_cap_1")\n'
        '\$/drafts/0/accountId = "acc_cash"\n</a2ui>';
  }
  if (userText.contains('[UI action')) {
    // Echo what the model saw, so the client shows it as prose.
    final seen = userText.replaceAll('\n', ' | ');
    return 'Got it. I saw: $seen\n'
        '<a2ui>\nsurface("cap_k3m9")\n\$/drafts/1/note = "answered by agent"\n</a2ui>';
  }
  if (userText.toLowerCase().contains('alex')) {
    return 'Quick check first.\n<a2ui>\n'
        'surface("cap_p7x2")\n'
        '\$/drafts = [{id: "d1", intent: "loan_given", amountMinor: 30000, currency: "USD",\n'
        '  personName: "Alex", accountId: "acc_chk", occurredOn: "2026-11-22", missing: ["intent"]}]\n'
        'root = Column([ask, list])\n'
        'ask = ChoicePrompt("Will Alex pay this back?",\n'
        '  [{label: "Yes, it\'s a loan", value: "loan_given", hint: "Alex owes us"},\n'
        '   {label: "No, gift or payment", value: "expense", hint: "Expense"}],\n'
        '  \$/drafts/0/intent, false, Event("xp.answer", {field: "intent", value: \$/drafts/0/intent}))\n'
        'list = EntryList(\$/drafts)\n'
        '</a2ui>';
  }
  return 'Here is what I found.\n<a2ui>\n'
      'surface("cap_k3m9")\n'
      '\$/drafts = [\n'
      '  {id: "d1", intent: "income", amountMinor: 320000, currency: "USD", categoryId: "salary",\n'
      '   accountId: "acc_chk", who: "me", occurredOn: "2026-11-22", title: "Salary",\n'
      '   confidence: {intent: 0.99, category: 0.97, account: 0.96}},\n'
      '  {id: "d2", intent: "expense", amountMinor: 140000, currency: "USD", categoryId: "rent",\n'
      '   accountId: "acc_chk", who: "joint", occurredOn: "2026-11-22", title: "Rent",\n'
      '   confidence: {intent: 0.98, category: 0.99, account: 0.97}, guessed: ["who"]}\n'
      ']\n'
      'root = EntryList(\$/drafts, "review", "I found two things in that:")\n'
      '</a2ui>';
}

/// Registers the scripted model and returns it.
Model defineScriptedModel(Genkit ai) => ai.defineModel(
  name: 'spike/scripted',
  fn: (req, ctx) async {
    final n = ++_requestCount;
    final dir = Directory('../evidence/requests')..createSync(recursive: true);
    final tag = Platform.script.pathSegments.last.replaceAll('.dart', '');
    File('${dir.path}/${tag}_request_$n.json').writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert(req.toJson()),
    );
    final lastUser = req.messages.lastWhere((m) => m.role == Role.user);
    final userText = lastUser.content.map((p) => p.text ?? '').join('\n');
    final reply = _replyFor(userText);
    // Stream in small pieces so the a2ui() stream parser is exercised across
    // chunk boundaries, as with a real model.
    if (ctx.streamingRequested) {
      for (var i = 0; i < reply.length; i += 40) {
        final end = i + 40 > reply.length ? reply.length : i + 40;
        ctx.sendChunk(
          ModelResponseChunk(
            index: 0,
            role: Role.model,
            content: [TextPart(text: reply.substring(i, end))],
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
    }
    return ModelResponse(
      finishReason: FinishReason.stop,
      message: Message(
        role: Role.model,
        content: [TextPart(text: reply)],
      ),
    );
  },
);
