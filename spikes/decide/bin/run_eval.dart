// WP-S4: runs the AI_PIPELINE 7 question set over the 60 utterances and
// writes raw responses, scores and a Markdown report to ../evidence/.
//
// The key is read from Secret Manager (latest version) when the run starts;
// see lib/secret.dart. Needs gcloud signed in with access to the secret.
//
//   dart run bin/run_eval.dart [--passes 2] [--tag main] \
//     [--category-options leaves|all] [--only category]
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:wp_s4_decide/decisions_client.dart';
import 'package:wp_s4_decide/household.dart';
import 'package:wp_s4_decide/question_set.dart';
import 'package:wp_s4_decide/scoring.dart';
import 'package:xpense_shared/xpense_shared.dart';

const double pricePerMillion = 0.10;

Future<void> main(List<String> args) async {
  final opts = _args(args);
  final passes = int.parse(opts['passes'] ?? '2');
  final tag = opts['tag'] ?? 'main';
  final catOptions = CategoryOptions.values.byName(
    opts['category-options'] ?? 'leaves',
  );
  final only = opts['only']?.split(',').toSet();

  final cases = loadCases('data/utterances.json');
  if (opts.containsKey('rescore')) {
    // Rebuild the report from the saved responses: no API calls.
    final (results, keysAsked) = _loadSaved(tag);
    File('evidence/${tag}_report.md').writeAsStringSync(
      _report(
        tag: tag,
        cases: cases,
        results: results,
        keysAsked: keysAsked,
        retries: 0,
        catOptions: catOptions,
        keySummary:
            'Re-scored from evidence/raw/${tag}_responses.jsonl with no API '
            'calls. The calls themselves used secret version 2 (see '
            'docs/spikes/WP-S4.md, "Secret versions used").',
      ),
    );
    stdout.writeln('re-scored evidence/${tag}_report.md');
    return;
  }
  final client = await DecisionsClient.open();
  stdout.writeln('secret version ${client.keyVersion}');
  final ctx = parseContext();
  final rng = math.Random(7);
  Directory('evidence/raw').createSync(recursive: true);
  final raw = File('evidence/raw/${tag}_responses.jsonl').openWrite();

  // results[pass][caseId] = outcome
  final results = <int, Map<String, DecisionOutcome>>{};
  final keysAsked = <String, List<String>>{};
  var retries = 0;
  var sampleWritten = false;

  for (var pass = 1; pass <= passes; pass++) {
    results[pass] = {};
    for (final c in cases) {
      if (only != null && !c.expect.keys.any(only.contains)) continue;
      final parse = parseText(c.text, ctx);
      var keys = questionKeysFor(parse, hasCandidates: c.candidates.isNotEmpty);
      if (only != null) keys = keys.where(only.contains).toList();
      keysAsked[c.id] = keys;
      final input = sharedInput(c.text, parse, candidates: c.candidates);
      final body = decisionRequest(
        input,
        buildQuestions(keys, categoryOptions: catOptions),
      );
      if (!sampleWritten) {
        File(
          'evidence/${tag}_sample_request.json',
        ).writeAsStringSync(const JsonEncoder.withIndent('  ').convert(body));
        sampleWritten = true;
      }
      var outcome = await client.send(body);
      var attempt = 1;
      if (outcome is DecisionHttpError && outcome.retryable ||
          outcome is DecisionTransportError) {
        retries++;
        await Future<void>.delayed(
          Duration(milliseconds: 250 + rng.nextInt(500)),
        );
        outcome = await client.send(body);
        attempt = 2;
      }
      results[pass]![c.id] = outcome;
      raw.writeln(
        jsonEncode({
          'pass': pass,
          'case': c.id,
          'slice': c.slice,
          'attempt': attempt,
          'keys': keys,
          'input': input,
          ...outcome.toJson(),
        }),
      );
      stdout.write(outcome is DecisionAnswered ? '.' : '[${outcome.kind}]');
    }
    stdout.writeln(' pass $pass done');
  }
  await raw.close();
  client.close();

  final report = _report(
    tag: tag,
    cases: cases,
    results: results,
    keysAsked: keysAsked,
    retries: retries,
    catOptions: catOptions,
    keySummary: client.keySummary,
  );
  File('evidence/${tag}_report.md').writeAsStringSync(report);
  stdout.writeln('wrote evidence/${tag}_report.md');
}

/// Saved outcomes by pass and case, and the keys asked per case.
(Map<int, Map<String, DecisionOutcome>>, Map<String, List<String>>) _loadSaved(
  String tag,
) {
  final results = <int, Map<String, DecisionOutcome>>{};
  final keysAsked = <String, List<String>>{};
  for (final line in File(
    'evidence/raw/${tag}_responses.jsonl',
  ).readAsLinesSync().where((l) => l.trim().isNotEmpty)) {
    final r = (jsonDecode(line) as Map).cast<String, Object?>();
    final id = r['case']! as String;
    keysAsked[id] = (r['keys']! as List).cast<String>();
    (results[r['pass']! as int] ??= {})[id] = classify(
      r['status']! as int,
      jsonEncode(r['body']),
      Duration(milliseconds: r['latencyMs']! as int),
    );
  }
  return (results, keysAsked);
}

Map<String, String> _args(List<String> args) {
  final out = <String, String>{};
  for (var i = 0; i + 1 < args.length; i += 2) {
    out[args[i].replaceFirst('--', '')] = args[i + 1];
  }
  return out;
}

String _report({
  required String tag,
  required List<Case> cases,
  required Map<int, Map<String, DecisionOutcome>> results,
  required Map<String, List<String>> keysAsked,
  required int retries,
  required CategoryOptions catOptions,
  required String keySummary,
}) {
  final b = StringBuffer()
    ..writeln('# WP-S4 run `$tag`')
    ..writeln()
    ..writeln(
      'Category options: `${catOptions.name}` '
      '(${categoryCriteria(catOptions).length}). Passes: ${results.length}. '
      'Retries used: $retries. Generated ${DateTime.now().toUtc()} UTC.',
    )
    ..writeln()
    ..writeln(keySummary)
    ..writeln();

  final byId = {for (final c in cases) c.id: c};
  final scoredByPass = <int, List<Scored>>{};
  final nonAnswered = <String>[];
  for (final MapEntry(key: pass, value: outcomes) in results.entries) {
    final scored = <Scored>[];
    for (final MapEntry(key: id, value: o) in outcomes.entries) {
      if (o is DecisionAnswered) {
        scored.addAll(scoreCase(byId[id]!, o.answers));
      } else {
        nonAnswered.add('pass $pass $id: ${jsonEncode(o.toJson())}');
      }
    }
    scoredByPass[pass] = scored;
  }
  final s1 = scoredByPass[1]!;

  // Accuracy per question, every pass.
  b
    ..writeln('## Accuracy per question')
    ..writeln()
    ..writeln(
      '| question | ${[for (final p in results.keys) 'pass $p'].join(' | ')} |',
    )
    ..writeln('|---|${[for (final _ in results.keys) '---'].join('|')}|');
  for (final key in [...choiceKeys, ...noulKeys]) {
    final cells = [
      for (final p in results.keys)
        () {
          final xs = scoredByPass[p]!.where((s) => s.key == key);
          return pct(xs.where((s) => s.correct).length, xs.length);
        }(),
    ];
    b.writeln('| `$key` | ${cells.join(' | ')} |');
  }
  final cat = s1.where((s) => s.key == 'category');
  final intent = s1.where((s) => s.key == 'intent');
  final acct = s1.where((s) => s.key == 'account');
  final stated = acct.where((s) => byId[s.caseId]!.accountStated);
  final unstated = acct.where((s) => !byId[s.caseId]!.accountStated);
  b
    ..writeln()
    ..writeln('Pass 1 details:')
    ..writeln()
    ..writeln(
      '- category top-3: '
      '${pct(cat.where((s) => s.top3 ?? false).length, cat.length)}',
    )
    ..writeln(
      '- account when stated: '
      '${pct(stated.where((s) => s.correct).length, stated.length)}; '
      'not stated (expects `unspecified`): '
      '${pct(unstated.where((s) => s.correct).length, unstated.length)}',
    );

  // Intent by slice.
  b
    ..writeln()
    ..writeln('### Intent by slice (pass 1)')
    ..writeln()
    ..writeln('| slice | intent correct | mean confidence |')
    ..writeln('|---|---|---|');
  final slices = <String>{for (final c in cases) c.slice};
  for (final slice in slices) {
    final xs = intent.where((s) => s.slice == slice).toList();
    if (xs.isEmpty) continue;
    final mean = Stats(xs.map((s) => s.confidence)).mean;
    b.writeln(
      '| $slice | ${pct(xs.where((s) => s.correct).length, xs.length)} '
      '| ${mean.toStringAsFixed(2)} |',
    );
  }

  // Gates that this spike can speak to.
  final amb = s1.where(
    (s) => s.key == 'needs_followup' && s.slice == 'ambiguous',
  );
  final explicit = s1.where(
    (s) => s.key == 'needs_followup' && s.slice == 'single_explicit',
  );
  final multi = s1.where((s) => s.key == 'multi_entry');
  final multiPos = multi.where((s) => s.label ?? false);
  final multiNeg = multi.where((s) => !(s.label ?? true));
  b
    ..writeln()
    ..writeln('### Follow-up and routing (pass 1, threshold 0.5)')
    ..writeln()
    ..writeln(
      '- `needs_followup` recall on the ambiguous slice: '
      '${pct(amb.where((s) => (s.probabilityYes ?? 0) >= 0.5).length, amb.length)}',
    )
    ..writeln(
      '- `needs_followup` rate on the explicit slice: '
      '${pct(explicit.where((s) => (s.probabilityYes ?? 0) >= 0.5).length, explicit.length)}',
    )
    ..writeln(
      '- `multi_entry` recall: '
      '${pct(multiPos.where((s) => s.correct).length, multiPos.length)}; '
      'false re-routes of single messages: '
      '${pct(multiNeg.where((s) => !s.correct).length, multiNeg.length)}',
    );

  // Calibration.
  final choice = s1.where((s) => choiceKeys.contains(s.key));
  final noul = s1.where((s) => noulKeys.contains(s.key));
  b
    ..writeln()
    ..writeln('## Calibration (pass 1)')
    ..writeln()
    ..writeln('### Choice questions, top-1 confidence vs correct')
    ..writeln()
    ..writeln(
      Reliability([for (final s in choice) (s.confidence, s.correct)])
          .markdown(),
    )
    ..writeln('### Yes/no questions, P(yes) vs label')
    ..writeln()
    ..writeln(
      Reliability([for (final s in noul) (s.probabilityYes!, s.label!)])
          .markdown(predicted: 'mean P(yes)'),
    )
    ..writeln('### All answers, confidence vs correct')
    ..writeln()
    ..writeln(
      Reliability([for (final s in s1) (s.confidence, s.correct)]).markdown(),
    )
    ..writeln('### ECE per question')
    ..writeln()
    ..writeln('| question | n | accuracy | mean confidence | ECE | Brier |')
    ..writeln('|---|---|---|---|---|---|');
  for (final key in [...choiceKeys, ...noulKeys]) {
    final xs = s1.where((s) => s.key == key).toList();
    if (xs.isEmpty) continue;
    final r = Reliability([for (final s in xs) (s.confidence, s.correct)]);
    b.writeln(
      '| `$key` | ${xs.length} '
      '| ${(xs.where((s) => s.correct).length / xs.length).toStringAsFixed(3)} '
      '| ${Stats(xs.map((s) => s.confidence)).mean.toStringAsFixed(3)} '
      '| ${r.ece.toStringAsFixed(3)} | ${r.brier.toStringAsFixed(3)} |',
    );
  }

  // Thresholds from AI_PIPELINE 9.
  b
    ..writeln()
    ..writeln('## Confidence policy simulation (pass 1, choice questions)')
    ..writeln()
    ..writeln(
      'Defaults (AI_PIPELINE 9): prefill at ≥ 0.85, "Guessed" from 0.55, '
      'ask below 0.55. Intent has no "Guessed" state: it is prefilled at '
      '≥ 0.90 (`conf_intent_min`) and always asked below.',
    )
    ..writeln()
    ..writeln(
      '| question | n | prefilled | wrong when prefilled | guessed '
      '| wrong when guessed | asked |',
    )
    ..writeln('|---|---|---|---|---|---|---|');
  for (final key in choiceKeys) {
    final xs = choice.where((s) => s.key == key).toList();
    // Intent below conf_intent_min always asks, so it has no guessed band.
    final isIntent = key == 'intent';
    final high = isIntent ? 0.90 : 0.85;
    final low = isIntent ? 0.90 : 0.55;
    final pre = xs.where((s) => s.confidence >= high);
    final guess = xs.where((s) => s.confidence >= low && s.confidence < high);
    final ask = xs.where((s) => s.confidence < low);
    b.writeln(
      '| `$key` | ${xs.length} | ${pct(pre.length, xs.length)} '
      '| ${pct(pre.where((s) => !s.correct).length, pre.length)} '
      '| ${isIntent ? 'n/a' : pct(guess.length, xs.length)} '
      '| ${isIntent ? 'n/a' : pct(guess.where((s) => !s.correct).length, guess.length)} '
      '| ${pct(ask.length, xs.length)} |',
    );
  }
  b
    ..writeln()
    ..writeln('Sweep of `conf_high` over all choice answers:')
    ..writeln()
    ..writeln('| conf_high | prefilled | wrong prefills (of all answers) |')
    ..writeln('|---|---|---|');
  final cs = choice.toList();
  for (var t = 0.50; t < 0.991; t += 0.05) {
    final pre = cs.where((s) => s.confidence >= t);
    b.writeln(
      '| ${t.toStringAsFixed(2)} | ${pct(pre.length, cs.length)} '
      '| ${pct(pre.where((s) => !s.correct).length, cs.length)} |',
    );
  }

  // Latency and tokens.
  final answered = [
    for (final outcomes in results.values)
      for (final o in outcomes.values)
        if (o is DecisionAnswered) o,
  ];
  final first = results[1]!.values.first;
  b
    ..writeln()
    ..writeln('## Latency and tokens (all passes)')
    ..writeln()
    ..writeln(Stats.header)
    ..writeln(
      Stats(answered.map((o) => o.latency.inMilliseconds)).row('latency, ms'),
    )
    ..writeln(Stats(answered.map((o) => o.inputTokens)).row('input tokens'))
    ..writeln(
      Stats(answered.map((o) => o.inputTokens * pricePerMillion / 1e6 * 1e5))
          .row('cost, USD per 100k calls', digits: 2),
    )
    ..writeln()
    ..writeln(
      'First request of the run (cold connection): '
      '${first.latency.inMilliseconds} ms.',
    )
    ..writeln()
    ..writeln('By number of questions asked:')
    ..writeln()
    ..writeln(Stats.header);
  final byCount = <int, List<DecisionAnswered>>{};
  for (final outcomes in results.values) {
    for (final MapEntry(key: id, value: o) in outcomes.entries) {
      if (o is DecisionAnswered) {
        (byCount[keysAsked[id]!.length] ??= []).add(o);
      }
    }
  }
  for (final n in byCount.keys.toList()..sort()) {
    b
      ..writeln(
        Stats(byCount[n]!.map((o) => o.inputTokens))
            .row('$n questions: tokens'),
      )
      ..writeln(
        Stats(byCount[n]!.map((o) => o.latency.inMilliseconds))
            .row('$n questions: ms'),
      );
  }
  final usageKeys = <String>{for (final o in answered) ...o.usage.keys};
  b
    ..writeln()
    ..writeln('Usage fields seen: ${usageKeys.map((k) => '`$k`').join(', ')}.')
    ..writeln(
      'Sample usage: `${jsonEncode(answered.isEmpty ? {} : answered.first.usage)}`',
    );

  // Determinism between passes.
  if (results.length > 1) {
    var maxDiff = 0.0;
    var changedTop = 0;
    var compared = 0;
    for (final MapEntry(key: id, value: o1) in results[1]!.entries) {
      final o2 = results[2]![id];
      if (o1 is! DecisionAnswered || o2 is! DecisionAnswered) continue;
      for (final MapEntry(key: k, value: a1) in o1.answers.entries) {
        final a2 = o2.answers[k];
        if (a1 is! Map || a2 is! Map) continue;
        compared++;
        if (a1['choice'] != a2['choice']) changedTop++;
        final p1 = (a1['noul'] ?? a1['confidence']) as num?;
        final p2 = (a2['noul'] ?? a2['confidence']) as num?;
        if (p1 != null && p2 != null) {
          maxDiff = math.max(maxDiff, (p1 - p2).abs().toDouble());
        }
      }
    }
    b
      ..writeln()
      ..writeln('## Determinism (pass 1 vs pass 2)')
      ..writeln()
      ..writeln(
        '$compared answers compared; top choice changed in $changedTop; '
        'largest change in P(yes) or confidence: ${maxDiff.toStringAsFixed(4)}.',
      );
  }

  // Non-answered outcomes.
  b
    ..writeln()
    ..writeln('## Errors and blocks during the run')
    ..writeln();
  if (nonAnswered.isEmpty) {
    b.writeln('None.');
  } else {
    for (final line in nonAnswered) {
      b.writeln('- `$line`');
    }
  }

  // Every miss, pass 1.
  b
    ..writeln()
    ..writeln('## Misses (pass 1)')
    ..writeln()
    ..writeln('| case | question | expected | got | confidence |')
    ..writeln('|---|---|---|---|---|');
  for (final s in s1.where((s) => !s.correct)) {
    final c = byId[s.caseId]!;
    final expected = s.label?.toString() ?? c.expect[s.key].toString();
    final got = s.answer == null
        ? 'P(yes) ${s.probabilityYes!.toStringAsFixed(2)}'
        : _label(s.answer!);
    b.writeln(
      '| ${s.caseId} "${c.text}" | `${s.key}` | $expected | $got '
      '| ${s.confidence.toStringAsFixed(2)} |',
    );
  }

  File('evidence/${tag}_scores.json')
      .writeAsStringSync(jsonEncode([for (final s in s1) s.toJson()]));
  return b.toString();
}

String _label(String key) {
  for (final MapEntry(key: label, value: id) in accountLabels.entries) {
    if (id == key) return label;
  }
  return key;
}
