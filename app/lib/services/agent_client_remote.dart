// The genkit adapter behind `AgentClient` (ARCHITECTURE 3.2 and 5.3). Only
// the composition root and tests name this file; it is the only app file
// that imports genkit.
//
// The agent client API is experimental in genkit 1.0; this file accepts
// that, and the rest of the app sees only `AgentClient`.
// ignore_for_file: experimental_member_use

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:genkit/client.dart';
import 'package:genkit/experimental_client.dart' as gk;
import 'package:http/http.dart' as http;

import 'package:xpense_app/services/agent_client.dart';
import 'package:xpense_app/services/service_failure.dart';

/// The MIME type of an A2UI data part (`genkit_a2ui`).
const String a2uiPartMimeType = 'application/a2ui+json';

/// Returns the current Firebase ID token, refreshed when [forceRefresh],
/// or null when nobody is signed in.
typedef IdTokenSource = Future<String?> Function({bool forceRefresh});

/// Returns the current App Check token, or null.
typedef AppCheckTokenSource = Future<String?> Function();

/// [AgentClient] over `remoteAgent` to `xpense-agent`'s `/v1/agent`.
///
/// Every request carries the Firebase ID token and the App Check token,
/// which the server's context provider verifies (server/README "Request
/// contract"). The household and member come from the token, never from
/// the phone.
final class RemoteAgentClient implements AgentClient {
  /// Creates the client. [baseUrl] is the service origin; `/v1/agent` is
  /// added. [timeout] bounds a whole turn.
  new({
    required this.baseUrl,
    required this._idToken,
    required this._appCheckToken,
    required this.timeout,
    http.Client Function()? httpClient,
  }) : _httpClient = httpClient ?? http.Client.new;

  /// The service origin, such as `https://xpense-agent-….run.app`.
  final Uri baseUrl;

  /// The longest a turn may take before it fails as [ServiceOffline]. The
  /// agent answers in a few seconds; this is the backstop for a stalled
  /// connection.
  final Duration timeout;

  final IdTokenSource _idToken;
  final AppCheckTokenSource _appCheckToken;
  final http.Client Function() _httpClient;

  /// The turn endpoint.
  Uri get endpoint => baseUrl.resolve('/v1/agent');

  @override
  AgentConversation open() => _RemoteConversation(this);
}

final class _RemoteConversation implements AgentConversation {
  new(this._client) : _http = _TraceRecordingClient(_client._httpClient()) {
    _api = gk.remoteAgent<Object?>(
      url: _client.endpoint.toString(),
      headers: _headers,
      httpClient: _http,
    );
    _chat = _api.chat();
  }

  final RemoteAgentClient _client;
  final _TraceRecordingClient _http;
  late final gk.AgentApi<Object?> _api;
  late final gk.AgentChat<Object?> _chat;
  bool _forceRefresh = false;
  bool _closed = false;
  _Running? _running;

  Future<Map<String, String>?> _headers() async {
    final idToken = await _client._idToken(forceRefresh: _forceRefresh);
    _forceRefresh = false;
    final appCheck = await _client._appCheckToken();
    return {
      if (idToken != null && idToken.isNotEmpty)
        'authorization': 'Bearer $idToken',
      if (appCheck != null && appCheck.isNotEmpty)
        'x-firebase-appcheck': appCheck,
    };
  }

  @override
  Stream<AgentEvent> send(AgentTurn turn) {
    if (_closed) {
      return Stream.value(const AgentTurnFailed(ServiceError('agent.closed')));
    }
    if (_running != null) {
      return Stream.value(const AgentTurnFailed(ServiceError('agent.busy')));
    }
    final controller = StreamController<AgentEvent>();
    final running = _running = _Running(controller);
    unawaited(
      _run(turn, running).whenComplete(() {
        if (identical(_running, running)) _running = null;
        if (!controller.isClosed) unawaited(controller.close());
      }),
    );
    return controller.stream;
  }

  Future<void> _run(AgentTurn turn, _Running running) async {
    final message = Message(
      role: Role.user,
      content: [
        for (final action in turn.actions)
          DataPart(
            data: Map<String, dynamic>.from(action),
            metadata: {'mimeType': a2uiPartMimeType},
          ),
        if (turn.text.isNotEmpty) TextPart(text: turn.text),
      ],
    );
    // One retry after a refused ID token (server/README: refresh and retry
    // once), only if nothing reached the member yet.
    for (var attempt = 0; ; attempt++) {
      final outcome = await _attempt(message, running);
      if (outcome case _Failed(:final failure, :final retryWithFreshToken)) {
        if (retryWithFreshToken && attempt == 0 && !running.emitted) {
          _forceRefresh = true;
          continue;
        }
        running.add(AgentTurnFailed(failure));
      } else {
        running.add(AgentTurnDone(traceId: _http.lastTraceId));
      }
      return;
    }
  }

  Future<_Outcome> _attempt(Message message, _Running running) async {
    final gkTurn = _chat.sendStream(message: message);
    running.abort = gkTurn.abort;
    try {
      await for (final chunk in gkTurn.stream.timeout(_client.timeout)) {
        if (running.cancelled) break;
        final text = chunk.text;
        if (text.isNotEmpty) running.add(AgentReply(text));
        final messages = a2uiMessagesFrom(chunk.raw.modelChunk?.content);
        if (messages.isNotEmpty) running.add(AgentSurfaceMessages(messages));
      }
      if (running.cancelled) return const _Failed(ServiceCancelled());
      await gkTurn.response.timeout(_client.timeout);
      return const _Done();
    } on TimeoutException {
      gkTurn.abort();
      return const _Failed(ServiceOffline());
    } on gk.AgentError<Object?> catch (e) {
      if (running.cancelled) return const _Failed(ServiceCancelled());
      debugPrint('AgentClient: ${e.status} ${e.message}');
      return _failureOf(status: e.status, message: e.message, cause: e.details);
    } on Exception catch (e) {
      // A transport failure before any server answer.
      if (running.cancelled) return const _Failed(ServiceCancelled());
      debugPrint('AgentClient: ${e.runtimeType}');
      return const _Failed(ServiceOffline());
    } finally {
      running.abort = null;
    }
  }

  @override
  Future<void> cancel() async {
    final running = _running;
    if (running == null || running.cancelled) return;
    running
      ..cancelled = true
      ..abort?.call();
    // Ask the server to stop the turn too; best effort.
    try {
      await _chat.abort();
    } on Exception catch (e) {
      debugPrint('AgentClient abort: ${e.runtimeType}');
    }
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    await cancel();
    _closed = true;
    await _api.close();
  }
}

/// The state of one turn in flight.
final class _Running {
  new(this._controller);

  final StreamController<AgentEvent> _controller;
  bool cancelled = false;
  bool emitted = false;
  void Function()? abort;

  void add(AgentEvent event) {
    if (_controller.isClosed) return;
    if (event is AgentReply || event is AgentSurfaceMessages) emitted = true;
    _controller.add(event);
  }
}

sealed class _Outcome {
  const new();
}

final class _Done extends _Outcome {
  const new();
}

final class _Failed extends _Outcome {
  const new(this.failure, {this.retryWithFreshToken = false});

  final ServiceFailure failure;
  final bool retryWithFreshToken;
}

/// Maps a failed turn to a [ServiceFailure] (server/README refusal codes).
///
/// [status] is the Genkit status name, [message] the server's code, and
/// [cause] what the client caught: a [GenkitException] when the server
/// answered, anything else when the request never got an answer.
_Failed _failureOf({
  required String status,
  required String message,
  Object? cause,
}) {
  if (cause != null && cause is! GenkitException && status == 'UNKNOWN') {
    return const _Failed(ServiceOffline());
  }
  return switch ((status, message)) {
    ('RESOURCE_EXHAUSTED', _) ||
    (_, 'over_limit') => const _Failed(ServiceRateLimited()),
    (_, 'on_device_mode') => const _Failed(ServiceUnavailable()),
    ('UNAUTHENTICATED', 'invalid_id_token') => const _Failed(
      ServiceError('agent.unauthenticated.invalid_id_token'),
      retryWithFreshToken: true,
    ),
    ('UNAVAILABLE' || 'DEADLINE_EXCEEDED', _) => const _Failed(
      ServiceOffline(),
    ),
    ('CANCELLED' || 'ABORTED', _) => const _Failed(ServiceCancelled()),
    _ => _Failed(ServiceError('agent.${status.toLowerCase()}.$message')),
  };
}

/// The [ServiceFailure] for a failed turn, for tests.
@visibleForTesting
ServiceFailure agentServiceFailure({
  required String status,
  required String message,
  Object? cause,
}) => _failureOf(status: status, message: message, cause: cause).failure;

/// The A2UI messages carried by a chunk's or message's parts: the data
/// parts with [a2uiPartMimeType], `{messages: [...]}` (or the pre-spec
/// `envelopes`). Malformed payloads are skipped, never thrown.
List<Map<String, Object?>> a2uiMessagesFrom(List<Part>? parts) => [
  for (final part in parts ?? const <Part>[])
    if (part.metadata?['mimeType'] == a2uiPartMimeType)
      if (part.data?['messages'] ?? part.data?['envelopes']
          case final List<Object?> messages)
        for (final m in messages)
          if (m is Map) Map<String, Object?>.from(m),
];

/// Records the `x-genkit-trace-id` header of each response, so the turn
/// can report its trace.
final class _TraceRecordingClient extends http.BaseClient {
  new(this._inner);

  final http.Client _inner;

  /// The trace id of the latest response, if the server sent one.
  String? lastTraceId;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final response = await _inner.send(request);
    final trace = response.headers['x-genkit-trace-id'];
    if (trace != null && trace.isNotEmpty) lastTraceId = trace;
    return response;
  }

  @override
  void close() => _inner.close();
}
