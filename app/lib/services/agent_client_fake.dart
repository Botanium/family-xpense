import 'package:xpense_app/services/agent_client.dart';
import 'package:xpense_app/services/service_failure.dart';

/// An [AgentClient] that replays [script], for tests and for runs without a
/// backend.
///
/// With the default empty script every turn fails as unavailable, which is
/// what a phone without the cloud agent should show.
final class FakeAgentClient implements AgentClient {
  /// Creates a client that answers every turn with [script].
  new({this.script = const []});

  /// The events each turn emits before it ends. When the script does not
  /// end the turn itself, [AgentTurnDone] is appended, or [AgentTurnFailed]
  /// with [ServiceUnavailable] if the script is empty.
  List<AgentEvent> script;

  /// The turns received, in order.
  final List<AgentTurn> turns = [];

  @override
  Stream<AgentEvent> send(AgentTurn turn) async* {
    turns.add(turn);
    if (script.isEmpty) {
      yield const AgentTurnFailed(ServiceUnavailable());
      return;
    }
    yield* Stream.fromIterable(script);
    if (script.last is! AgentTurnDone && script.last is! AgentTurnFailed) {
      yield const AgentTurnDone();
    }
  }
}
