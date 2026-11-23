// The genkit adapter behind AgentClient, against genkit's own streaming
// wire format (`data: {...}\n\n` frames), served by a mock HTTP client.
import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:xpense_app/services/agent_client.dart';
import 'package:xpense_app/services/agent_client_remote.dart';
import 'package:xpense_app/services/service_failure.dart';

const Map<String, Object?> _surface = {
  'version': '1.0',
  'createSurface': {
    'surfaceId': 'cap_1',
    'catalogId':
        'https://bitrelia.com/xpense/a2ui/catalogs/xpense/v1/catalog.json',
    'components': [
      {'id': 'root', 'component': 'Text', 'text': 'hi'},
    ],
  },
};

String _frame(Map<String, Object?> payload) =>
    'data: ${jsonEncode(payload)}\n\n';

String _okStream() =>
    _frame({
      'message': {
        'modelChunk': {
          'content': [
            {'text': 'Got it. '},
          ],
        },
      },
    }) +
    _frame({
      'message': {
        'modelChunk': {
          'content': [
            {
              'data': {
                'messages': [_surface],
              },
              'metadata': {'mimeType': a2uiPartMimeType},
            },
          ],
        },
      },
    }) +
    _frame({
      'result': {
        'sessionId': 's1',
        'snapshotId': 'snap1',
        'finishReason': 'stop',
        'message': {
          'role': 'model',
          'content': [
            {'text': 'Got it. '},
          ],
        },
      },
    });

/// A mock server that records requests and answers each with [respond].
final class _Server {
  new(this.respond);

  final Future<http.StreamedResponse> Function(http.BaseRequest request, int n)
  respond;
  final List<http.Request> requests = [];

  http.Client client() => MockClient.streaming((request, body) async {
    final bytes = await body.toBytes();
    requests.add(
      http.Request(request.method, request.url)
        ..headers.addAll(request.headers)
        ..bodyBytes = bytes,
    );
    return await respond(request, requests.length);
  });
}

http.StreamedResponse _response(
  String body, {
  int status = 200,
  Map<String, String> headers = const {},
}) => http.StreamedResponse(
  Stream.value(utf8.encode(body)),
  status,
  headers: {'content-type': 'text/event-stream', ...headers},
);

RemoteAgentClient _client(
  _Server server, {
  List<bool>? refreshes,
  Duration timeout = const Duration(seconds: 5),
}) => RemoteAgentClient(
  baseUrl: Uri.parse('http://127.0.0.1:8080/'),
  idToken: ({forceRefresh = false}) async {
    refreshes?.add(forceRefresh);
    return forceRefresh ? 'fresh-token' : 'id-token';
  },
  appCheckToken: () async => 'app-check',
  timeout: timeout,
  httpClient: server.client,
);

void main() {
  test(
    'a turn streams text and surfaces, then ends with the trace id',
    () async {
      final server = _Server(
        (_, _) async =>
            _response(_okStream(), headers: {'x-genkit-trace-id': 'trace-123'}),
      );
      final conversation = _client(server).open();
      final events = await conversation
          .send(
            const AgentTurn(
              text: 'Salary 3200 and rent 1400',
              actions: [
                {'messages': <Object?>[]},
              ],
            ),
          )
          .toList();

      expect(events, hasLength(3));
      expect((events[0] as AgentReply).text, 'Got it. ');
      expect(
        (events[1] as AgentSurfaceMessages).messages.single['createSurface'],
        isA<Map<String, Object?>>(),
      );
      expect((events[2] as AgentTurnDone).traceId, 'trace-123');

      final request = server.requests.single;
      expect(request.url.toString(), 'http://127.0.0.1:8080/v1/agent');
      expect(request.headers['authorization'], 'Bearer id-token');
      expect(request.headers['x-firebase-appcheck'], 'app-check');
      final body = jsonDecode(request.body) as Map<String, Object?>;
      final content =
          ((body['data']! as Map)['message']! as Map)['content']! as List;
      // The action's data part first, then the text (ARCHITECTURE 7, rule 9).
      expect((content[0] as Map)['metadata'], {'mimeType': a2uiPartMimeType});
      expect((content[1] as Map)['text'], 'Salary 3200 and rent 1400');
      await conversation.close();
    },
  );

  test('the second turn of a conversation continues its session', () async {
    final server = _Server((_, _) async => _response(_okStream()));
    final conversation = _client(server).open();
    await conversation.send(const AgentTurn(text: 'one')).drain<void>();
    await conversation.send(const AgentTurn(text: 'two')).drain<void>();
    final second = jsonDecode(server.requests[1].body) as Map<String, Object?>;
    expect(jsonEncode(second['init']), contains('snap1'));
    await conversation.close();
  });

  group('typed failures', () {
    Future<ServiceFailure> failureFor(
      int status,
      Map<String, Object?> body,
    ) async {
      final server = _Server(
        (_, _) async => _response(jsonEncode(body), status: status),
      );
      final conversation = _client(server).open();
      final events = await conversation
          .send(const AgentTurn(text: 'x'))
          .toList();
      await conversation.close();
      return (events.single as AgentTurnFailed).failure;
    }

    test('429 over_limit is rate limited', () async {
      expect(
        await failureFor(429, {
          'code': 429,
          'status': 'RESOURCE_EXHAUSTED',
          'message': 'over_limit',
        }),
        const ServiceRateLimited(),
      );
    });

    test('403 on_device_mode is unavailable', () async {
      expect(
        await failureFor(403, {
          'code': 403,
          'status': 'PERMISSION_DENIED',
          'message': 'on_device_mode',
        }),
        const ServiceUnavailable(),
      );
    });

    test('503 is offline', () async {
      expect(
        await failureFor(503, {
          'code': 503,
          'status': 'UNAVAILABLE',
          'message': 'auth_unavailable',
        }),
        const ServiceOffline(),
      );
    });

    test('anything else is an error with a machine-readable detail', () async {
      expect(
        await failureFor(403, {
          'code': 403,
          'status': 'PERMISSION_DENIED',
          'message': 'not_member',
        }),
        const ServiceError('agent.permission_denied.not_member'),
      );
    });

    test('no answer at all is offline', () async {
      final server = _Server(
        (_, _) async => throw http.ClientException('connection refused'),
      );
      final conversation = _client(server).open();
      final events = await conversation
          .send(const AgentTurn(text: 'x'))
          .toList();
      expect(
        (events.single as AgentTurnFailed).failure,
        const ServiceOffline(),
      );
      await conversation.close();
    });
  });

  test('a refused ID token is retried once with a fresh one', () async {
    final server = _Server(
      (_, n) async => n == 1
          ? _response(
              jsonEncode({
                'code': 401,
                'status': 'UNAUTHENTICATED',
                'message': 'invalid_id_token',
              }),
              status: 401,
            )
          : _response(_okStream()),
    );
    final refreshes = <bool>[];
    final conversation = _client(server, refreshes: refreshes).open();
    final events = await conversation.send(const AgentTurn(text: 'x')).toList();
    expect(events.last, isA<AgentTurnDone>());
    expect(refreshes, [false, true]);
    expect(server.requests[1].headers['authorization'], 'Bearer fresh-token');
    await conversation.close();
  });

  test('cancel ends the turn as cancelled', () async {
    final hold = StreamController<List<int>>();
    final server = _Server((request, n) async {
      if (request.url.path.endsWith('/abort')) {
        return _response(_frame({'result': <String, Object?>{}}));
      }
      return http.StreamedResponse(hold.stream, 200);
    });
    final conversation = _client(server).open();
    final events = <AgentEvent>[];
    final done = Completer<void>();
    conversation
        .send(const AgentTurn(text: 'x'))
        .listen(events.add, onDone: done.complete);
    hold.add(
      utf8.encode(
        _frame({
          'message': {
            'modelChunk': {
              'content': [
                {'text': 'Thinking'},
              ],
            },
          },
        }),
      ),
    );
    await Future<void>.delayed(Duration.zero);
    await conversation.cancel();
    await done.future;
    expect((events.last as AgentTurnFailed).failure, const ServiceCancelled());
    await hold.close();
    await conversation.close();
  });

  test('a turn that stalls past the timeout is offline', () async {
    final server = _Server(
      (_, _) async =>
          http.StreamedResponse(StreamController<List<int>>().stream, 200),
    );
    final conversation = _client(
      server,
      timeout: const Duration(milliseconds: 50),
    ).open();
    final events = await conversation.send(const AgentTurn(text: 'x')).toList();
    expect((events.single as AgentTurnFailed).failure, const ServiceOffline());
    await conversation.close();
  });

  test('a second send while a turn runs fails at once as busy', () async {
    final hold = StreamController<List<int>>();
    final server = _Server(
      (_, _) async => http.StreamedResponse(hold.stream, 200),
    );
    final conversation = _client(server).open();
    final first = conversation.send(const AgentTurn(text: 'a')).toList();
    final second = await conversation.send(const AgentTurn(text: 'b')).toList();
    expect(
      (second.single as AgentTurnFailed).failure,
      const ServiceError('agent.busy'),
    );
    hold.add(utf8.encode(_okStream()));
    await hold.close();
    expect((await first).last, isA<AgentTurnDone>());
    await conversation.close();
  });

  test('a2uiMessagesFrom skips other parts and malformed payloads', () {
    expect(a2uiMessagesFrom(null), isEmpty);
  });
}
