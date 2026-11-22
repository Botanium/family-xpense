// WP-S1 spike (throwaway). Drives the served agent over HTTP with
// remoteAgent, the same transport the Flutter client uses:
//   turn 1: text that produces the two-draft surface;
//   turn 2 (Q5): ONE user message carrying an A2UI action data part AND text.
//
//   dart run bin/http_client.dart [baseUrl] [hid] [uid]
// ignore_for_file: experimental_member_use
import 'dart:convert';
import 'dart:io';

import 'package:genkit/client.dart';
import 'package:genkit/experimental_client.dart';

Future<void> main(List<String> args) async {
  final base = args.isNotEmpty ? args[0] : 'http://localhost:8085';
  final hid = args.length > 1 ? args[1] : 'hh_demo';
  final uid = args.length > 2 ? args[2] : 'u_owner';
  final agent = remoteAgent(
    url: '$base/api/spikeAgent',
    headers: () => {'x-spike-hid': hid, 'x-spike-uid': uid},
  );
  final chat = agent.chat();

  final r1 = await chat.send(
    text: 'Salary 3,200 came in and I paid 1,400 rent',
  );
  stdout.writeln('turn 1 session=${chat.sessionId} snapshot=${r1.snapshotId}');

  // The action message a2ui_core 0.8 builds (RendererToAgentMessagePayload),
  // written out by hand here: {messages: [{version, action}]}.
  final action = {
    'messages': [
      {
        'version': '1.0',
        'action': {
          'name': 'xp.saved',
          'surfaceId': 'cap_k3m9',
          'sourceComponentId': 'root',
          'timestamp': DateTime.utc(2026, 11, 22, 14).toIso8601String(),
          'context': {
            'draftIds': ['d1', 'd2'],
            'txnIds': ['t_101', 't_102'],
          },
        },
      },
    ],
  };
  final r2 = await chat.send(
    message: Message(
      role: Role.user,
      content: [
        DataPart(data: action, metadata: {'mimeType': 'application/a2ui+json'}),
        TextPart(text: 'Also, the rent was split with my sister.'),
      ],
    ),
  );
  stdout.writeln('turn 2 snapshot=${r2.snapshotId}');
  stdout.writeln('turn 2 reply: ${jsonEncode(r2.message?.toJson())}');
  stdout.writeln(
    'client history roles: '
    '${chat.messages.map((m) => '${m.role}:${m.content.length}').toList()}',
  );
  agent.close();
}
