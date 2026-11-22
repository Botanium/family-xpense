// WP-S1 spike client (throwaway, never merged into app/).
//
// One MessageProcessor (a2ui_core 0.8.0) per conversation. Agent surfaces
// (streamed from the spike server, which runs genkit_a2ui 0.6.0 on
// a2ui_core 0.7.0) and locally built raw-map surfaces go through the same
// processor and render side by side.
//
//   cd ../server && genkit start -- dart run bin/server.dart   (PORT=8085)
//   flutter run -d <simulator>
// ignore_for_file: experimental_member_use, deprecated_member_use
import 'package:a2ui_core/a2ui_core.dart';
import 'package:a2ui_flutter/a2ui_flutter.dart';
import 'package:flutter/material.dart';
import 'package:genkit/client.dart';
import 'package:genkit/experimental_client.dart';

import 'a2ui_helpers.dart';
import 'local_builder.dart';
import 'spike_catalog.dart';

const _agentUrl = String.fromEnvironment(
  'AGENT_URL',
  defaultValue: 'http://localhost:8085/api/spikeAgent',
);

void main() => runApp(const SpikeApp());

class SpikeApp extends StatelessWidget {
  const SpikeApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'WP-S1',
    theme: ThemeData(colorSchemeSeed: Colors.blueGrey, useMaterial3: true),
    home: const SpikeScreen(),
  );
}

sealed class Entry {}

class ProseEntry extends Entry {
  ProseEntry(this.who, this.text);
  final String who;
  String text;
}

class SurfaceEntry extends Entry {
  SurfaceEntry(this.surfaceId, this.source);
  final String surfaceId;
  final String source;
}

class SpikeScreen extends StatefulWidget {
  const SpikeScreen({super.key});

  @override
  State<SpikeScreen> createState() => _SpikeScreenState();
}

class _SpikeScreenState extends State<SpikeScreen> {
  late final AgentApi _agent = remoteAgent(
    url: _agentUrl,
    headers: () => {'x-spike-hid': 'hh_demo', 'x-spike-uid': 'u_owner'},
  );
  late final _chat = _agent.chat();
  late final MessageProcessor<ComponentImplementation> _processor;
  final _entries = <Entry>[];
  final _log = <String>[];
  var _busy = false;
  var _nextSource = 'agent';

  @override
  void initState() {
    super.initState();
    _processor = MessageProcessor<ComponentImplementation>(
      catalogs: [spikeCatalog],
      unifiedOutbound: true,
      outboundListener: (message) {
        if (message is ActionMessage) {
          _note(
            'outbound action ${message.action.name} '
            'context=${message.action.context}',
          );
          if (message.action.name.startsWith('xp.local.')) return;
          if (_busy) {
            _note('ignored: a turn is running');
            return;
          }
          _runTurn(a2uiActionToMessage(message));
        }
      },
      onError: (e) => _note('renderer error: ${e.message}'),
    );
    _processor.model.onSurfaceCreated.subscribe((s) {
      setState(() {
        if (!_entries.any((e) => e is SurfaceEntry && e.surfaceId == s.id)) {
          _entries.add(SurfaceEntry(s.id, _nextSource));
        }
      });
    });
    _processor.model.onSurfaceDeleted.subscribe((_) => setState(() {}));
  }

  @override
  void dispose() {
    _agent.close();
    super.dispose();
  }

  void _note(String line) {
    debugPrint('[spike] $line');
    if (mounted) setState(() => _log.add(line));
  }

  void _process(Iterable<Map<String, dynamic>> messages, String source) {
    _nextSource = source;
    for (final m in messages) {
      try {
        _processor.processMessages([m]);
        _note(
          '$source: processed ${m.keys.where((k) => k != 'version').first}',
        );
      } on Object catch (e) {
        _note('$source: SKIPPED message: $e');
      }
    }
  }

  Future<void> _runTurn(Message message) async {
    setState(() => _busy = true);
    final text = message.content.map((p) => p.text ?? '[data]').join(' + ');
    _entries.add(ProseEntry('you', text));
    final reply = ProseEntry('agent', '');
    _entries.add(reply);
    try {
      final turn = _chat.sendStream(message: message);
      await for (final chunk in turn.stream) {
        final parts = chunk.raw.modelChunk?.content;
        if (chunk.text.isNotEmpty) setState(() => reply.text += chunk.text);
        _process(a2uiMessagesFrom(parts), 'agent');
      }
      await turn.response;
    } on Object catch (e) {
      _note('turn failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _sendText(String text) => _runTurn(
    Message(
      role: Role.user,
      content: [TextPart(text: text)],
    ),
  );

  void _sendSavedWithText() {
    final action = ActionMessage(
      version: A2uiProtocolVersion.v1_0.jsonValue,
      action: A2uiRendererAction(
        name: 'xp.saved',
        surfaceId: 'cap_k3m9',
        sourceComponentId: 'root',
        timestamp: DateTime.now().toUtc(),
        context: {
          'draftIds': ['d1', 'd2'],
          'txnIds': ['t_101', 't_102'],
        },
      ),
    );
    _runTurn(
      a2uiActionToMessage(
        action,
        text: 'Also, the rent was split with my sister.',
      ),
    );
  }

  Widget _surface(SurfaceEntry e) {
    final surface = _processor.model.getSurface(e.surfaceId);
    if (surface == null) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: e.source == 'local' ? Colors.amber.shade50 : Colors.blue.shade50,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '${e.source.toUpperCase()} surface "${e.surfaceId}"',
            style: const TextStyle(fontSize: 10, fontFamily: 'Menlo'),
          ),
          A2uiSurface(key: ObjectKey(surface), surface: surface),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('WP-S1 A2UI round trip')),
    body: SafeArea(
      child: Column(
        children: [
          Wrap(
            spacing: 6,
            children: [
              FilledButton(
                key: const ValueKey('ask_two'),
                onPressed: _busy
                    ? null
                    : () => _sendText(
                        'Salary 3,200 came in and I paid 1,400 rent',
                      ),
                child: const Text('Agent: 2 entries'),
              ),
              FilledButton(
                key: const ValueKey('ask_alex'),
                onPressed: _busy ? null : () => _sendText('Alex borrowed 300'),
                child: const Text('Agent: Alex'),
              ),
              OutlinedButton(
                key: const ValueKey('local'),
                onPressed: () => _process(localCaptureSurface(), 'local'),
                child: const Text('Local surface'),
              ),
              OutlinedButton(
                key: const ValueKey('saved_text'),
                onPressed: _busy ? null : _sendSavedWithText,
                child: const Text('Saved + text'),
              ),
            ],
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(12),
              children: [
                for (final e in _entries)
                  switch (e) {
                    ProseEntry(:final who, :final text) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Text('$who: $text'),
                    ),
                    final SurfaceEntry s => _surface(s),
                  },
              ],
            ),
          ),
          SizedBox(
            height: 110,
            child: ListView(
              reverse: true,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: [
                for (final l in _log.reversed.take(30))
                  Text(
                    l,
                    style: const TextStyle(fontSize: 10, fontFamily: 'Menlo'),
                  ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}
