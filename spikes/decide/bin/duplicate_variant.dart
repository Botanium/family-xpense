// WP-S4: the duplicate question missed 3 of 7 in the main run, always where
// the candidate was dated the day before. This compares the AI_PIPELINE 7
// wording with a second wording on those 7 cases plus 7 more, labelled
// before either wording was run on them.
//
//   GEMINI_API_KEY=... dart run bin/duplicate_variant.dart
import 'dart:io';

import 'package:wp_s4_decide/decisions_client.dart';
import 'package:wp_s4_decide/household.dart';
import 'package:wp_s4_decide/question_set.dart';
import 'package:wp_s4_decide/scoring.dart';
import 'package:xpense_shared/xpense_shared.dart';

typedef DupCase = ({String text, Candidate candidate, bool same});

const List<DupCase> extra = [
  (
    text: 'Paid rent 450 from checking',
    candidate: Candidate(
      id: 'x1',
      amount: 'USD 450',
      date: '2026-11-21',
      title: 'Rent, November, Checking account',
    ),
    same: true,
  ),
  (
    text: 'Internet bill 35,000 dinars',
    candidate: Candidate(
      id: 'x2',
      amount: 'IQD 35,000',
      date: '2026-11-21',
      title: 'Internet bill',
    ),
    same: true,
  ),
  (
    text: 'Got 100 dollars from Mom for Eid',
    candidate: Candidate(
      id: 'x3',
      amount: 'USD 100',
      date: '2026-11-22',
      title: 'Eid gift from Mom',
    ),
    same: true,
  ),
  (
    text: 'Costco groceries 42.80 on the joint card',
    candidate: Candidate(
      id: 'x4',
      amount: 'USD 42.80',
      date: '2026-11-21',
      title: 'Costco, Joint Visa card',
    ),
    same: true,
  ),
  (
    text: 'Bread 2,000',
    candidate: Candidate(
      id: 'x5',
      amount: 'IQD 2,000',
      date: '2026-11-21',
      title: 'Bread',
    ),
    same: false,
  ),
  (
    text: 'Taxi back home 5,000',
    candidate: Candidate(
      id: 'x6',
      amount: 'IQD 5,000',
      date: '2026-11-22',
      title: 'Taxi to work',
    ),
    same: false,
  ),
  (
    text: "Gave the neighbour's kid 5,000 dinars for Eid",
    candidate: Candidate(
      id: 'x7',
      amount: 'IQD 5,000',
      date: '2026-11-22',
      title: 'Eid money for nephew Rawa',
    ),
    same: false,
  ),
];

const Map<String, Object?> v2 = {
  'type': 'noul',
  'instructions':
      'Do the message and one of the recent entries describe the same '
      'real-world payment, so that saving the message would record it twice?',
  'criteria': {
    'true_description':
        'Same kind of payment, same amount and same purpose, person or '
        'merchant as a listed entry, even if that entry is dated a day '
        'earlier: it may have been saved already.',
    'false_description':
        'A separate event: a different purpose, person or merchant, or a '
        'routine purchase that is normally made again (bread, taxi rides).',
  },
};

Future<void> main() async {
  final client = DecisionsClient(apiKey: apiKeyFromEnvironment());
  final ctx = parseContext();
  final cases = <DupCase>[
    for (final c in loadCases('data/utterances.json'))
      if (c.expected('duplicate') case final same?)
        (text: c.text, candidate: c.candidates.single, same: same),
    ...extra,
  ];
  final b = StringBuffer()
    ..writeln('# WP-S4 duplicate question: two wordings')
    ..writeln()
    ..writeln('| message | candidate | label | P(yes) v1 | P(yes) v2 |')
    ..writeln('|---|---|---|---|---|');
  final pairs = {'v1': <(double, bool)>[], 'v2': <(double, bool)>[]};
  for (final c in cases) {
    final parse = parseText(c.text, ctx);
    final input = sharedInput(c.text, parse, candidates: [c.candidate]);
    final ps = <String, double>{};
    for (final (name, q) in [
      ('v1', buildQuestions(['duplicate'])['duplicate']),
      ('v2', v2),
    ]) {
      final o = await client.send(decisionRequest(input, {'duplicate': q}));
      if (o is! DecisionAnswered) throw StateError(o.kind);
      final p = ((o.answers['duplicate']! as Map)['noul']! as num).toDouble();
      ps[name] = p;
      pairs[name]!.add((p, c.same));
    }
    final cand = c.candidate;
    b.writeln(
      '| ${c.text} | ${cand.amount}, ${cand.date}, ${cand.title} | ${c.same} '
      '| ${ps['v1']!.toStringAsFixed(2)} | ${ps['v2']!.toStringAsFixed(2)} |',
    );
  }
  b.writeln();
  for (final MapEntry(key: name, value: xs) in pairs.entries) {
    final correct = xs.where((x) => (x.$1 >= 0.5) == x.$2).length;
    final r = Reliability(xs);
    b.writeln(
      '- $name: ${pct(correct, xs.length)} at 0.5; Brier '
      '${r.brier.toStringAsFixed(3)}; at `dup_warn` 0.80: warns on '
      '${xs.where((x) => x.$1 >= 0.8 && x.$2).length} of '
      '${xs.where((x) => x.$2).length} duplicates and '
      '${xs.where((x) => x.$1 >= 0.8 && !x.$2).length} of '
      '${xs.where((x) => !x.$2).length} non-duplicates.',
    );
  }
  client.close();
  File('evidence/duplicate_variant.md').writeAsStringSync(b.toString());
  stdout.write(b);
}
