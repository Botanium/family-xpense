import 'dart:async';

import 'package:xpense_app/services/agent_client.dart';
import 'package:xpense_app/services/service_failure.dart';

/// An [AgentClient] that replays a script, for tests and for runs without
/// a backend.
///
/// With the default empty script every turn fails as unavailable, which is
/// what a phone without the cloud agent should show.
final class FakeAgentClient implements AgentClient {
  /// Creates a client whose turns answer with [script].
  new({this.script = const []});

  /// The events each turn emits before it ends. When the script does not
  /// end the turn itself, [AgentTurnDone] is appended, or [AgentTurnFailed]
  /// with [ServiceUnavailable] if the script is empty.
  List<AgentEvent> script;

  /// When set, every turn waits for it before ending, so a test can see the
  /// busy state and cancel.
  Completer<void>? gate;

  /// Every turn received by every conversation, in order.
  final List<AgentTurn> turns = [];

  /// The conversations opened, in order.
  final List<FakeAgentConversation> conversations = [];

  @override
  AgentConversation open() {
    final c = FakeAgentConversation._(this);
    conversations.add(c);
    return c;
  }
}

/// A conversation of [FakeAgentClient].
final class FakeAgentConversation implements AgentConversation {
  new _(this._client);

  final FakeAgentClient _client;
  Completer<void>? _cancelled;

  /// Whether [cancel] was called.
  bool cancelCalled = false;

  /// Whether [close] was called.
  bool closed = false;

  @override
  Stream<AgentEvent> send(AgentTurn turn) async* {
    _client.turns.add(turn);
    final cancelled = _cancelled = Completer<void>();
    try {
      final script = _client.script;
      if (script.isEmpty) {
        yield const AgentTurnFailed(ServiceUnavailable());
        return;
      }
      final ends =
          script.last is AgentTurnDone || script.last is AgentTurnFailed;
      for (final event in ends ? script.take(script.length - 1) : script) {
        if (cancelled.isCompleted) break;
        yield event;
      }
      final gate = _client.gate;
      if (gate != null) {
        await Future.any([gate.future, cancelled.future]);
      }
      if (cancelled.isCompleted) {
        yield const AgentTurnFailed(ServiceCancelled());
        return;
      }
      yield ends ? script.last : const AgentTurnDone();
    } finally {
      _cancelled = null;
    }
  }

  @override
  Future<void> cancel() async {
    cancelCalled = true;
    final c = _cancelled;
    if (c != null && !c.isCompleted) c.complete();
  }

  @override
  Future<void> close() async => closed = true;
}
