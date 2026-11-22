// WP-S4: what each question costs in input tokens and latency, so WP-33 can
// price a request from the keys it asks. One message (exp-02, which has a
// duplicate candidate), each question alone, the full set, and the
// category question with both option lists. Each request runs 3 times.
//
//   dart run bin/token_breakdown.dart
import 'dart:io';

import 'package:wp_s4_decide/decisions_client.dart';
import 'package:wp_s4_decide/household.dart';
import 'package:wp_s4_decide/question_set.dart';
import 'package:wp_s4_decide/scoring.dart';
import 'package:xpense_shared/xpense_shared.dart';

const allKeys = [
  'intent',
  'category',
  'account',
  'who',
  'multi_entry',
  'repayable',
  'needs_followup',
  'is_recurring',
  'duplicate',
];

Future<void> main() async {
  final client = await DecisionsClient.open();
  final c = loadCases('data/utterances.json')
      .firstWhere((c) => c.id == 'exp-02');
  final parse = parseText(c.text, parseContext());
  final input = sharedInput(c.text, parse, candidates: c.candidates);

  Future<(int, List<int>)> measure(Map<String, Object?> questions) async {
    var tokens = 0;
    final ms = <int>[];
    for (var i = 0; i < 3; i++) {
      final o = await client.send(decisionRequest(input, questions));
      if (o is! DecisionAnswered) throw StateError('not answered: ${o.kind}');
      tokens = o.inputTokens;
      ms.add(o.latency.inMilliseconds);
    }
    return (tokens, ms);
  }

  final b = StringBuffer()
    ..writeln('# WP-S4 token and latency breakdown per question')
    ..writeln()
    ..writeln(
      'Message exp-02 with one duplicate candidate; shared input is '
      '${input.length} characters. Each row is 3 runs; latency is the '
      'median.',
    )
    ..writeln()
    ..writeln('```text\n$input\n```')
    ..writeln()
    ..writeln('| request | input tokens | median ms |')
    ..writeln('|---|---|---|');

  final probe = {
    'probe': {'type': 'noul', 'instructions': 'Is this about money?'},
  };
  final (base, baseMs) = await measure(probe);
  b.writeln(
    '| shared input + one 5-word yes/no question (baseline) | $base '
    '| ${_median(baseMs)} |',
  );
  var sumAlone = 0;
  for (final key in allKeys) {
    final (t, ms) = await measure(buildQuestions([key]));
    sumAlone += t - base;
    b.writeln('| `$key` alone | $t (+${t - base}) | ${_median(ms)} |');
  }
  final (allOpts, allMs) = await measure(
    buildQuestions(['category'], categoryOptions: .all),
  );
  b.writeln(
    '| `category` alone, 45 options (with groups) | $allOpts '
    '(+${allOpts - base}) | ${_median(allMs)} |',
  );
  final (full, fullMs) = await measure(buildQuestions(allKeys));
  b
    ..writeln('| all 9 questions | $full | ${_median(fullMs)} |')
    ..writeln()
    ..writeln(
      'Shared input billed once: the 9 questions alone add $sumAlone tokens '
      'over the baseline in total; the full request is ${full - base} over '
      'the baseline.',
    );

  b
    ..writeln()
    ..writeln(client.keySummary);
  client.close();
  File('evidence/token_breakdown.md').writeAsStringSync(b.toString());
  stdout.write(b);
}

int _median(List<int> xs) => (List.of(xs)..sort())[xs.length ~/ 2];
