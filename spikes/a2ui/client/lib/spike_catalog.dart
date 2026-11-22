// WP-S1 spike (throwaway). Client half of the spike catalog: the basic
// Column, Text and Button from a2ui_flutter plus cut-down EntryList and
// ChoicePrompt, registered under the same catalogId the server loads from
// ../catalog/spike_catalog.json.
// ignore_for_file: deprecated_member_use
import 'package:a2ui_core/a2ui_core.dart';
import 'package:a2ui_flutter/a2ui_flutter.dart';
import 'package:a2ui_flutter/basic_catalog.dart';
import 'package:flutter/material.dart';
import 'package:json_schema_builder/json_schema_builder.dart';

const spikeCatalogId =
    'https://familyxpense.app/a2ui/catalogs/xpense-spike/v1/catalog.json';

/// Counts builds per component id, so a test or the screen can show that a
/// sibling re-rendered after a write.
final Map<String, int> buildCounts = {};

final ComponentImplementation entryList = ComponentImplementation(
  name: 'EntryList',
  schema: Schema.object(
    properties: {
      'drafts': CommonSchemasV1.dynamicValue,
      'status': Schema.string(enumValues: ['review', 'saved']),
      'title': CommonSchemasV1.dynamicString,
    },
    required: ['drafts'],
  ),
  builder: (context, node, props, buildChild) {
    buildCounts[node.componentId] = (buildCounts[node.componentId] ?? 0) + 1;
    final drafts = props.list('drafts').whereType<Map>().toList();
    final draftsBinding = props.writable('drafts');
    return EntryListView(
      title: props.string('title'),
      drafts: drafts,
      builds: buildCounts[node.componentId]!,
      // Q3: write one field back through the binding of the whole array.
      onToggleWho: draftsBinding == null
          ? null
          : (index) {
              final next = [
                for (final d in drafts) Map<String, Object?>.from(d),
              ];
              final who = next[index]['who'];
              next[index]['who'] = who == 'joint' ? 'me' : 'joint';
              draftsBinding.set(next);
            },
    );
  },
);

final ComponentImplementation choicePrompt = ComponentImplementation(
  name: 'ChoicePrompt',
  schema: Schema.object(
    properties: {
      'question': CommonSchemasV1.dynamicString,
      'options': Schema.list(
        items: Schema.object(
          properties: {
            'label': Schema.string(),
            'value': Schema.string(),
            'hint': Schema.string(),
          },
          required: ['label', 'value'],
        ),
      ),
      'value': CommonSchemasV1.dynamicString,
      'allowOther': Schema.boolean(),
      'action': Schema.fromMap(const {
        r'$ref': r'common_types.json#/$defs/Action',
      }),
    },
    required: ['question', 'options', 'value'],
  ),
  builder: (context, node, props, buildChild) {
    buildCounts[node.componentId] = (buildCounts[node.componentId] ?? 0) + 1;
    final binding = props.writable('value');
    final action = props.action('action');
    return ChoicePromptView(
      question: props.string('question') ?? '',
      options: props.list('options').whereType<Map>().toList(),
      selected: props.string('value'),
      onPick: (value) async {
        // Q3: a pick writes the bound path locally ...
        binding?.set(value);
        // ... and fires the action only if the agent asked for one.
        if (action != null) await action();
      },
    );
  },
);

/// The spike catalog, in the shape a2ui_flutter's own basicCatalog() uses.
final CatalogImplementation spikeCatalog = CatalogImplementation(
  id: spikeCatalogId,
  protocolVersion: A2uiProtocolVersion.v1_0,
  components: [
    BasicComponents.column,
    BasicComponents.text,
    BasicComponents.button,
    entryList,
    choicePrompt,
  ],
  functions: [
    for (final f in BasicCatalog.v1_0().functions.values)
      if (f.name == 'required' || f.name == 'formatNumber') f,
  ],
  definitions: BasicComponents.api.definitions,
);

class EntryListView extends StatelessWidget {
  const EntryListView({
    required this.drafts,
    required this.builds,
    this.title,
    this.onToggleWho,
    super.key,
  });

  final String? title;
  final List<Map> drafts;
  final int builds;
  final void Function(int index)? onToggleWho;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (title != null) Text(title!, style: t.titleSmall),
        for (final (i, d) in drafts.indexed)
          Container(
            margin: const EdgeInsets.only(top: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.black26),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${d['intent']} · ${d['categoryId'] ?? '—'}'.toUpperCase(),
                  style: t.labelSmall?.copyWith(fontFamily: 'Menlo'),
                ),
                Text(
                  '${d['title'] ?? d['personName'] ?? d['id']}  '
                  '${d['currency']} ${d['amountMinor']} (minor)',
                  style: t.bodyLarge,
                ),
                Row(
                  children: [
                    Text('who: ${d['who'] ?? '—'}'),
                    if ((d['guessed'] as List?)?.contains('who') ?? false)
                      const Text('  GUESSED', style: TextStyle(fontSize: 10)),
                    const Spacer(),
                    if (onToggleWho != null)
                      TextButton(
                        key: ValueKey('toggleWho_$i'),
                        onPressed: () => onToggleWho!(i),
                        child: const Text('change who'),
                      ),
                  ],
                ),
                if (d['note'] != null) Text('note: ${d['note']}'),
                if ((d['missing'] as List?)?.isNotEmpty ?? false)
                  Text('missing: ${(d['missing'] as List).join(', ')}'),
              ],
            ),
          ),
        Text('EntryList builds: $builds', style: t.labelSmall),
      ],
    );
  }
}

class ChoicePromptView extends StatelessWidget {
  const ChoicePromptView({
    required this.question,
    required this.options,
    required this.onPick,
    this.selected,
    super.key,
  });

  final String question;
  final List<Map> options;
  final String? selected;
  final void Function(String value) onPick;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(question, style: Theme.of(context).textTheme.titleSmall),
      Wrap(
        spacing: 8,
        children: [
          for (final o in options)
            ChoiceChip(
              key: ValueKey('choice_${o['value']}'),
              label: Text('${o['label']}'),
              selected: selected == o['value'],
              onSelected: (_) => onPick('${o['value']}'),
            ),
        ],
      ),
    ],
  );
}
