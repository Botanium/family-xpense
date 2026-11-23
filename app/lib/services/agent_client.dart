import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:xpense_app/services/service_failure.dart';

/// One user turn for the cloud agent (ARCHITECTURE 5.3).
///
/// A turn is one user message: the A2UI [actions] first, as data parts,
/// then the [text] (ARCHITECTURE 7, rule 9). Either may be empty, not both.
@immutable
final class AgentTurn {
  /// Creates a turn.
  const new({required this.text, this.actions = const []});

  /// What the user typed or said, after on-device transcription. Empty for
  /// a turn that only carries actions.
  final String text;

  /// Renderer-to-agent payloads (`{messages: [...]}`), such as a picked
  /// answer or the `xp.saved` notes of earlier saves, sent as A2UI data
  /// parts before the text.
  final List<Map<String, Object?>> actions;
}

/// One thing the agent streams back during a turn.
@immutable
sealed class AgentEvent {
  const new();
}

/// A batch of A2UI v1.0 messages, as decoded JSON.
///
/// They are handed to `XpenseSurfaceHost` unread; only `lib/a2ui/` knows
/// their shape, so features never depend on `a2ui_core`.
final class AgentSurfaceMessages extends AgentEvent {
  /// Wraps [messages].
  const new(this.messages);

  /// The A2UI messages, in order.
  final List<Map<String, Object?>> messages;
}

/// Plain text from the agent, such as a follow-up question. Each event
/// carries only the new text; append them.
final class AgentReply extends AgentEvent {
  /// Wraps [text].
  const new(this.text);

  /// The new text.
  final String text;
}

/// The turn ended normally. Always the last event of a successful turn.
final class AgentTurnDone extends AgentEvent {
  /// Creates the event, with the turn's [traceId] when the server sent
  /// one.
  const new({this.traceId});

  /// The Genkit trace of the turn, for support and the PR evidence. Never
  /// shown to the member.
  final String? traceId;
}

/// The turn ended with [failure]. Always the last event of a failed turn.
final class AgentTurnFailed extends AgentEvent {
  /// Wraps [failure].
  const new(this.failure);

  /// Why the turn failed: [ServiceOffline] (no answer), [ServiceRateLimited]
  /// (the household's daily limit), [ServiceUnavailable] (On-device mode),
  /// [ServiceCancelled] (the member stopped it), or [ServiceError].
  final ServiceFailure failure;
}

/// One conversation with the agent: one Genkit chat, whose session the
/// server keeps (`FirestoreSessionStore`), so every turn sees the earlier
/// ones.
abstract interface class AgentConversation {
  /// Sends [turn] and streams the agent's events. The stream always ends
  /// with [AgentTurnDone] or [AgentTurnFailed]; it never emits an error.
  /// One turn at a time: a send while a turn runs fails at once with
  /// [ServiceError] `agent.busy`.
  Stream<AgentEvent> send(AgentTurn turn);

  /// Stops the running turn, if any: its stream ends with
  /// [AgentTurnFailed] and [ServiceCancelled], and the server is asked to
  /// abort. Safe to call at any time.
  Future<void> cancel();

  /// Ends the conversation and releases its connection.
  Future<void> close();
}

/// The Genkit agent on Cloud Run, reached through `remoteAgent` from
/// `package:genkit/experimental_client.dart` (ARCHITECTURE 3.2). Only the
/// adapter file may import genkit.
abstract interface class AgentClient {
  /// Starts a conversation. The Ask screen opens one per thread.
  AgentConversation open();
}

/// The [AgentClient] for this run. Throws until the composition root sets
/// it.
final agentClientProvider = Provider<AgentClient>(
  (ref) =>
      throw UnimplementedError('agentClientProvider is set in bootstrap()'),
  name: 'agentClientProvider',
);
