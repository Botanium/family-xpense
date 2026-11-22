// WP-S1 spike (throwaway). The copy-in helpers from the developing-genkit-dart
// a2ui reference, plus a variant that carries an action and text in ONE user
// message (Q5).
import 'package:a2ui_core/a2ui_core.dart'
    show ActionMessage, RendererToAgentMessagePayload;
import 'package:genkit/client.dart';

const a2uiMimeType = 'application/a2ui+json';

/// The A2UI messages carried by a chunk's or message's parts. No envelope-key
/// rewriting: the point of Q1 is whether a2ui_core 0.8 reads what the 0.7-era
/// server writes as it is.
Iterable<Map<String, dynamic>> a2uiMessagesFrom(List<Part>? parts) sync* {
  for (final part in parts ?? const <Part>[]) {
    if (part.metadata?['mimeType'] != a2uiMimeType) continue;
    final data = part.data;
    if ((data?['messages'] ?? data?['envelopes']) case final List messages) {
      yield* messages.whereType<Map>().map((m) => m.cast<String, dynamic>());
    }
  }
}

/// A surface action as the next agent input, optionally with text the user
/// typed in the same turn.
Message a2uiActionToMessage(ActionMessage action, {String? text}) => Message(
  role: Role.user,
  content: [
    DataPart(
      data: RendererToAgentMessagePayload.of(action).toJson(),
      metadata: {'mimeType': a2uiMimeType},
    ),
    if (text != null && text.isNotEmpty) TextPart(text: text),
  ],
);
