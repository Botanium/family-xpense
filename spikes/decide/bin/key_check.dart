// WP-S4: checks the key-rotation path without spending real work. The client
// starts with a deliberately invalid key; the API rejects it, the client
// re-reads the latest secret version once and retries. Prints the outcome
// and the version, never the key.
//
//   dart run bin/key_check.dart
import 'dart:io';

import 'package:wp_s4_decide/decisions_client.dart';
import 'package:wp_s4_decide/secret.dart';

Future<void> main() async {
  final client = DecisionsClient(
    key: const ApiKey('not-a-real-key-wp-s4', 'invalid'),
  );
  final o = await client.send(
    decisionRequest('Bought bread for 2,000 dinars', {
      'is_food': {'type': 'noul', 'instructions': 'Is this about food?'},
    }),
  );
  client.close();
  stdout.writeln('outcome: ${o.kind} (HTTP ${o.status})');
  stdout.writeln(client.keySummary);
  exit(o is DecisionAnswered && client.keyRefreshes == 1 ? 0 : 1);
}
