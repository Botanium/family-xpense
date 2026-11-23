/// Measures the A2UI instructions `a2ui()` injects into every agent model
/// call, for the full shared catalog and the agent's trimmed view.
///
///     tool/with_gemini_key.sh dart run tool/instruction_tokens.dart
///
/// Without `GEMINI_API_KEY` it prints characters only. Token counts come
/// from the Gemini `countTokens` endpoint for the agent's default model.
library;

import 'dart:convert';
import 'dart:io';

import 'package:genkit_a2ui/a2ui.dart';
import 'package:xpense_agent/catalog/xpense_catalog_loader.dart';

Future<void> main(List<String> args) async {
  final model = args.isEmpty ? 'gemini-3.5-flash-lite' : args.first;
  final json = await readCatalogJson();
  final rows = <(String, int, int, int?)>[];
  for (final (name, trim) in [
    ('full shared catalog', false),
    ('agent view (trimmed)', true),
  ]) {
    final catalog = agentCatalog(json, trim: trim);
    final text = renderCatalogInstructions(catalog);
    rows.add((
      name,
      catalog.components.length,
      text.length,
      await _countTokens(text, model),
    ));
  }
  stdout
    ..writeln('| catalog | components | characters | tokens ($model) |')
    ..writeln('|---|---|---|---|');
  for (final (name, n, chars, tokens) in rows) {
    stdout.writeln('| $name | $n | $chars | ${tokens ?? 'n/a (no key)'} |');
  }
}

Future<int?> _countTokens(String text, String model) async {
  final key = Platform.environment['GEMINI_API_KEY'];
  if (key == null || key.isEmpty) return null;
  final client = HttpClient();
  try {
    final req = await client.postUrl(
      Uri.parse(
        'https://generativelanguage.googleapis.com/v1beta/models/'
        '$model:countTokens',
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
    if (res.statusCode != 200) {
      stderr.writeln('countTokens: HTTP ${res.statusCode}');
      return null;
    }
    return body['totalTokens'] as int?;
  } finally {
    client.close();
  }
}
