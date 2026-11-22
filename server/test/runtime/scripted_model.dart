// A scripted model for agent tests: the first call asks for
// `prepareEntries` with fixed entries; the call after the tool answered
// renders Express from the tool's drafts.
import 'dart:convert';

import 'package:genkit/genkit.dart';

/// What a scripted model writes after `prepareEntries` answered.
typedef Render = String Function(List<Object?> drafts);

/// A model script.
final class Script {
  new({required this.entries, required this.render});

  /// The entries passed to `prepareEntries`.
  final List<Map<String, Object?>> entries;

  /// The render after the tool answered.
  final Render render;

  /// Every request the model received.
  final requests = <ModelRequest>[];
}

/// Registers [script] as the model [name].
void defineScripted(Genkit ai, String name, Script script) {
  ai.defineModel(
    name: name,
    fn: (req, ctx) async {
      script.requests.add(req);
      final tool = req.messages.lastOrNull?.role == Role.tool
          ? req.messages.last.content.first.toolResponse
          : null;
      if (tool == null) {
        return ModelResponse(
          finishReason: FinishReason.stop,
          message: Message(
            role: Role.model,
            content: [
              ToolRequestPart(
                toolRequest: ToolRequest(
                  ref: 'r1',
                  name: 'prepareEntries',
                  input: {'entries': script.entries},
                ),
              ),
            ],
          ),
        );
      }
      final output = jsonDecode(jsonEncode(tool.output)) as Map;
      final text = script.render(output['drafts'] as List);
      if (ctx.streamingRequested) {
        ctx.sendChunk(
          ModelResponseChunk(
            role: Role.model,
            content: [TextPart(text: text)],
          ),
        );
      }
      return ModelResponse(
        finishReason: FinishReason.stop,
        message: Message(
          role: Role.model,
          content: [TextPart(text: text)],
        ),
      );
    },
  );
}

/// One EntryList surface holding [drafts].
String scriptedCapture(List<Object?> drafts) =>
    'I found two things in that:\n<a2ui>\nsurface("cap_test")\n'
    '\$/drafts = ${jsonEncode(drafts)}\n'
    'root = EntryList(\$/drafts, "review", "Two entries")\n</a2ui>';

/// The salary-and-rent entries.
const salaryRent = [
  {
    'intent': 'income',
    'amount': '3200',
    'text': 'Salary came in 3200',
    'categoryHint': 'salary',
    'accountHint': 'checking',
  },
  {
    'intent': 'expense',
    'amount': '1400',
    'text': 'I paid rent 1400',
    'categoryHint': 'rent',
    'accountHint': 'checking',
  },
];
