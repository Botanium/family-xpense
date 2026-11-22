// WP-S4: writes the shared input and question keys for every case to
// ../evidence/inputs.md, with no API call, so the parser's part is visible.
import 'dart:io';

import 'package:wp_s4_decide/household.dart';
import 'package:wp_s4_decide/question_set.dart';
import 'package:wp_s4_decide/scoring.dart';
import 'package:xpense_shared/xpense_shared.dart';

void main() {
  final ctx = parseContext();
  final b = StringBuffer('# Shared inputs and question keys per case\n\n');
  for (final c in loadCases('data/utterances.json')) {
    final parse = parseText(c.text, ctx);
    final keys = questionKeysFor(parse, hasCandidates: c.candidates.isNotEmpty);
    b
      ..writeln('## ${c.id} (${c.slice})')
      ..writeln()
      ..writeln('Keys: ${keys.join(', ')}')
      ..writeln()
      ..writeln('```text')
      ..writeln(sharedInput(c.text, parse, candidates: c.candidates))
      ..writeln('```')
      ..writeln();
  }
  File('evidence/inputs.md').writeAsStringSync(b.toString());
}
