// WP-S1 spike (throwaway). Q7: size of the text a2ui() injects into the
// system prompt, per catalog. Writes each rendering to ../evidence/ and a
// summary table. Token counts need a Gemini key (countTokens); without one
// the summary gives characters, words and a chars/4 and chars/3.5 range.
//
//   dart run bin/instruction_size.dart
import 'dart:convert';
import 'dart:io';

import 'package:genkit_a2ui/a2ui.dart';

A2uiCatalog _load(String path) => A2uiCatalog.fromJson(
  (jsonDecode(File(path).readAsStringSync()) as Map).cast<String, dynamic>(),
);

Future<void> main() async {
  final spike = _load('../catalog/spike_catalog.json');
  final full = _load('../catalog/xpense_sizing_draft.json');
  // One component only, to isolate the fixed contract (preamble + grammar).
  final textOnly = A2uiCatalog(
    id: 'https://example.invalid/text-only.json',
    components: [
      A2uiCatalogComponent.simple(
        name: 'Text',
        description: 'Text.',
        params: [const A2uiParam.dynamicValue('text', required: true)],
      ),
    ],
    protocolVersion: '1.0',
  );
  final rows = <List<Object>>[];
  for (final (name, cat) in [
    ('one-component', textOnly),
    ('spike (5 components)', spike),
    ('xpense draft (24 components)', full),
    ('basic A2UI catalog (18 components)', basicCatalog),
  ]) {
    final text = renderCatalogInstructions(cat);
    final file = name.split(' ').first.replaceAll('-', '_').toLowerCase();
    File('../evidence/q7_instructions_$file.txt').writeAsStringSync(text);
    final tokens = await _countTokens(text);
    final words = text.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;
    rows.add([
      name,
      cat.components.length,
      text.length,
      words,
      (text.length / 4).round(),
      (text.length / 3.5).round(),
      tokens ?? 'n/a (no GEMINI_API_KEY)',
    ]);
  }
  final out = StringBuffer(
    '| catalog | components | chars | words | ~tokens (chars/4) | ~tokens (chars/3.5) | countTokens |\n'
    '|---|---|---|---|---|---|---|\n',
  );
  for (final r in rows) {
    out.writeln('| ${r.join(' | ')} |');
  }
  File('../evidence/q7_summary.md').writeAsStringSync(out.toString());
  stdout.write(out);
}

/// Exact count from the Gemini API when a key is set (not run in WP-S1: no
/// key was available).
Future<int?> _countTokens(String text) async {
  final key = Platform.environment['GEMINI_API_KEY'];
  if (key == null || key.isEmpty) return null;
  final client = HttpClient();
  try {
    final req = await client.postUrl(
      Uri.parse(
        'https://generativelanguage.googleapis.com/v1beta/models/'
        'gemini-3.5-flash-lite:countTokens',
      ),
    );
    req.headers
      ..contentType = ContentType.json
      ..set('x-goog-api-key', key);
    req.write(
      jsonEncode({
        'contents': [
          {
            'parts': [
              {'text': text},
            ],
          },
        ],
      }),
    );
    final res = await req.close();
    final body = jsonDecode(await res.transform(utf8.decoder).join()) as Map;
    return body['totalTokens'] as int?;
  } finally {
    client.close();
  }
}
