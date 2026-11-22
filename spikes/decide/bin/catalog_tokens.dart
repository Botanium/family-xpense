// WP-S4: exact token count of the instructions a2ui() injects for the
// merged Xpense catalog (WP-31), measured with countTokens on the agent's
// model. Complements the WP-S1 script, which measured the sizing draft.
//
//   dart run bin/catalog_tokens.dart   (reads the latest key version itself)
import 'dart:convert';
import 'dart:io';

import 'package:genkit/genkit.dart';
import 'package:genkit_a2ui/a2ui.dart';
import 'package:wp_s4_decide/secret.dart';
import 'package:xpense_shared/xpense_shared.dart';

const String model = 'gemini-3.5-flash-lite';

Future<void> main() async {
  var key = await readLatestKey();
  final ai = Genkit(isDevEnv: false);
  final catalog = await loadCatalog(
    ai,
    id: xpenseCatalogLookupId,
    file: '../../packages/xpense_shared/$xpenseCatalogPackagePath',
  );
  final text = renderCatalogInstructions(catalog);
  var (status, tokens) = await _countTokens(key.value, text);
  var reReads = 0;
  if (status == 400 || status == 401 || status == 403) {
    // A rejected key: re-read the latest version once and retry.
    key = await readLatestKey();
    reReads++;
    (status, tokens) = await _countTokens(key.value, text);
  }
  final words = text.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;
  final out = StringBuffer()
    ..writeln('# Injected catalog instructions, merged Xpense catalog')
    ..writeln()
    ..writeln(
      '| catalog | components | chars | words | countTokens ($model) '
      '| chars per token |',
    )
    ..writeln('|---|---|---|---|---|---|')
    ..writeln(
      '| xpense_catalog.json (WP-31, main) | ${catalog.components.length} '
      '| ${text.length} | $words | $tokens '
      '| ${tokens == null ? 'n/a' : (text.length / tokens).toStringAsFixed(2)} |',
    );
  out
    ..writeln()
    ..writeln(
      'Secret version used: ${key.version}; key re-reads after an API-key '
      'error: $reReads.',
    );
  File('evidence/catalog_tokens.md').writeAsStringSync(out.toString());
  stdout.write(out);
  await ai.shutdown();
}

Future<(int, int?)> _countTokens(String key, String text) async {
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
      stderr.writeln('countTokens HTTP ${res.statusCode}: ${body['error']}');
      return (res.statusCode, null);
    }
    return (res.statusCode, body['totalTokens'] as int?);
  } finally {
    client.close();
  }
}
