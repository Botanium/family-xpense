import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:xpense_app/services/service_failure.dart';

/// One user turn for the cloud agent (ARCHITECTURE 5.3).
@immutable
final class AgentTurn {
  /// Creates a turn.
  const new({required this.text, required this.locale});

  /// What the user typed or said, after on-device transcription.
  final String text;

  /// The app locale, such as `en`.
  final String locale;
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

/// Plain text from the agent, such as a follow-up question.
final class AgentReply extends AgentEvent {
  /// Wraps [text].
  const new(this.text);

  /// The reply.
  final String text;
}

/// The turn ended normally. Always the last event of a successful turn.
final class AgentTurnDone extends AgentEvent {
  /// Creates the event.
  const new();
}

/// The turn ended with [failure]. Always the last event of a failed turn.
final class AgentTurnFailed extends AgentEvent {
  /// Wraps [failure].
  const new(this.failure);

  /// Why the turn failed.
  final ServiceFailure failure;
}

/// The Genkit agent on Cloud Run, reached through `remoteAgent` from
/// `package:genkit/experimental_client.dart` (ARCHITECTURE 3.2). Only the
/// adapter file may import genkit.
abstract interface class AgentClient {
  /// Sends [turn] and streams the agent's events. The stream always ends
  /// with [AgentTurnDone] or [AgentTurnFailed]; it never emits an error.
  Stream<AgentEvent> send(AgentTurn turn);
}

/// The [AgentClient] for this run. Throws until the composition root sets
/// it.
final agentClientProvider = Provider<AgentClient>(
  (ref) =>
      throw UnimplementedError('agentClientProvider is set in bootstrap()'),
  name: 'agentClientProvider',
);
