// WP-S1 spike (throwaway). Q4 follow-up: can the agent update a surface the
// phone built, if the phone sends that surface's createSurface in the user
// turn (as an A2UI data part beside the text)?
//
//   dart run bin/local_surface_probe.dart
// ignore_for_file: experimental_member_use
import 'dart:convert';
import 'dart:io';

import 'package:genkit/experimental.dart';
import 'package:genkit/genkit.dart';
import 'package:genkit_a2ui/a2ui.dart';
import 'package:wp_s1_server/scripted_model.dart';

const _catalogId =
    'https://familyxpense.app/a2ui/catalogs/xpense-spike/v1/catalog.json';

Future<void> main() async {
  final ai = Genkit(plugins: [A2uiPlugin()]);
  await loadCatalog(
    ai,
    id: 'xpense-spike',
    file: '../catalog/spike_catalog.json',
  );
  final model = defineScriptedModel(ai);
  final agent = ai.defineAgent(
    name: 'probeLocal',
    model: modelRef(model.name),
    use: [a2ui(catalog: 'xpense-spike', validate: 'strict', repair: false)],
    store: InMemorySessionStore(),
  );
  final localCreate = {
    'version': '1.0',
    'createSurface': {
      'surfaceId': 'local_cap_1',
      'catalogId': _catalogId,
      'components': [
        {
          'id': 'root',
          'component': 'EntryList',
          'drafts': {'@path': '/drafts'},
        },
      ],
      'dataModel': {
        'drafts': [
          {
            'id': 'd1',
            'intent': 'expense',
            'amountMinor': 10000,
            'currency': 'IQD',
          },
        ],
      },
    },
  };

  for (final withSurface in [false, true]) {
    final chat = agent.chat();
    try {
      final r = await chat.send(
        message: Message(
          role: Role.user,
          content: [
            if (withSurface)
              DataPart(
                data: {
                  'messages': [localCreate],
                },
                metadata: {'mimeType': 'application/a2ui+json'},
              ),
            TextPart(text: 'please fill the account for that one'),
          ],
        ),
      );
      stdout.writeln(
        'withSurface=$withSurface OK: '
        '${jsonEncode(a2uiEnvelopesFromParts(r.message?.content).toList())}',
      );
    } on Object catch (e) {
      stdout.writeln('withSurface=$withSurface FAILED: $e');
    }
  }
}
