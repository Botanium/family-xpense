/// Dataset loading and the numbers the spike reports: accuracy per question,
/// reliability tables, expected calibration error, threshold simulation,
/// latency and token statistics.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:wp_s4_decide/household.dart';
import 'package:wp_s4_decide/question_set.dart';

const List<String> choiceKeys = ['intent', 'category', 'account', 'who'];
const List<String> noulKeys = [
  'multi_entry',
  'repayable',
  'needs_followup',
  'is_recurring',
  'duplicate',
];

final class Case {
  const new({
    required this.id,
    required this.slice,
    required this.text,
    required this.expect,
    required this.candidates,
  });

  factory fromJson(Map<String, Object?> j) => Case(
    id: j['id']! as String,
    slice: j['slice']! as String,
    text: j['text']! as String,
    expect: (j['expect']! as Map).cast<String, Object?>(),
    candidates: [
      for (final c in (j['candidates'] as List?) ?? const [])
        Candidate.fromJson((c as Map).cast<String, Object?>()),
    ],
  );

  final String id;
  final String slice;
  final String text;
  final Map<String, Object?> expect;
  final List<Candidate> candidates;

  /// Acceptable option keys for a choice question, or `null` (not scored).
  Set<String>? acceptable(String key) {
    final v = expect[key];
    if (v is! List) return null;
    return {
      for (final s in v.cast<String>())
        key == 'account' ? accountLabels[s]! : s,
    };
  }

  /// The expected yes/no answer, or `null` (not scored).
  bool? expected(String key) => expect[key] as bool?;

  /// Whether the account is named in the message (all acceptable answers
  /// are real accounts).
  bool get accountStated {
    final a = acceptable('account');
    return a != null && !a.contains('unspecified');
  }
}

List<Case> loadCases(String path) {
  final doc = jsonDecode(File(path).readAsStringSync()) as Map;
  return [
    for (final c in doc['cases'] as List)
      Case.fromJson((c as Map).cast<String, Object?>()),
  ];
}

/// One scored answer.
final class Scored {
  const new({
    required this.caseId,
    required this.slice,
    required this.key,
    required this.correct,
    required this.confidence,
    this.answer,
    this.probabilityYes,
    this.label,
    this.top3,
  });

  final String caseId;
  final String slice;
  final String key;

  /// Top-1 in the acceptable set (choice) or `(p ≥ 0.5) == label` (noul).
  final bool correct;

  /// The API's `confidence`.
  final double confidence;
  final String? answer;
  final double? probabilityYes;
  final bool? label;
  final bool? top3;

  Map<String, Object?> toJson() => {
    'case': caseId,
    'slice': slice,
    'key': key,
    'correct': correct,
    'confidence': confidence,
    'answer': ?answer,
    'pYes': ?probabilityYes,
    'label': ?label,
    'top3': ?top3,
  };
}

/// Scores the answers of one response against [c].
List<Scored> scoreCase(Case c, Map<String, Object?> answers) {
  final out = <Scored>[];
  for (final key in choiceKeys) {
    final ok = c.acceptable(key);
    final a = (answers[key] as Map?)?.cast<String, Object?>();
    if (ok == null || a == null) continue;
    final choice = a['choice'] as String?;
    final probs = (a['probabilities'] as Map? ?? {}).cast<String, Object?>();
    final ranked = probs.entries.toList()
      ..sort((x, y) => (y.value! as num).compareTo(x.value! as num));
    out.add(
      Scored(
        caseId: c.id,
        slice: c.slice,
        key: key,
        correct: ok.contains(choice),
        confidence: (a['confidence'] as num? ?? 0).toDouble(),
        answer: choice,
        top3: ranked.take(3).any((e) => ok.contains(e.key)),
      ),
    );
  }
  for (final key in noulKeys) {
    final label = c.expected(key);
    final a = (answers[key] as Map?)?.cast<String, Object?>();
    if (label == null || a == null) continue;
    final p = (a['noul'] as num? ?? 0).toDouble();
    out.add(
      Scored(
        caseId: c.id,
        slice: c.slice,
        key: key,
        correct: (p >= 0.5) == label,
        confidence: (a['confidence'] as num? ?? 0).toDouble(),
        probabilityYes: p,
        label: label,
      ),
    );
  }
  return out;
}

/// A reliability table row.
final class Bin {
  new(this.lo, this.hi);
  final double lo;
  final double hi;
  int n = 0;
  double sumPredicted = 0;
  double sumObserved = 0;

  double get meanPredicted => n == 0 ? 0 : sumPredicted / n;
  double get observed => n == 0 ? 0 : sumObserved / n;
}

/// Reliability over (predicted probability, observed 0/1) pairs.
final class Reliability {
  new(Iterable<(double, bool)> pairs, {this.bins = 10, double lo = 0}) {
    final width = (1 - lo) / bins;
    table = [
      for (var i = 0; i < bins; i++) Bin(lo + i * width, lo + (i + 1) * width),
    ];
    for (final (p, y) in pairs) {
      var i = ((p - lo) / width).floor();
      i = i.clamp(0, bins - 1);
      table[i]
        ..n += 1
        ..sumPredicted += p
        ..sumObserved += y ? 1 : 0;
      n += 1;
      brierSum += math.pow(p - (y ? 1 : 0), 2);
    }
  }

  final int bins;
  late final List<Bin> table;
  int n = 0;
  double brierSum = 0;

  /// Expected calibration error: Σ n_b/N · |observed − predicted|.
  double get ece {
    if (n == 0) return 0;
    var s = 0.0;
    for (final b in table) {
      if (b.n == 0) continue;
      s += b.n / n * (b.observed - b.meanPredicted).abs();
    }
    return s;
  }

  double get brier => n == 0 ? 0 : brierSum / n;

  String markdown({String predicted = 'mean confidence'}) {
    final b = StringBuffer()
      ..writeln('| bin | n | $predicted | observed | gap |')
      ..writeln('|---|---|---|---|---|');
    for (final bin in table) {
      if (bin.n == 0) continue;
      b.writeln(
        '| ${bin.lo.toStringAsFixed(2)}–${bin.hi.toStringAsFixed(2)} '
        '| ${bin.n} | ${bin.meanPredicted.toStringAsFixed(3)} '
        '| ${bin.observed.toStringAsFixed(3)} '
        '| ${(bin.observed - bin.meanPredicted).toStringAsFixed(3)} |',
      );
    }
    b.writeln(
      '\nN = $n, ECE = ${ece.toStringAsFixed(3)}, '
      'Brier = ${brier.toStringAsFixed(3)}',
    );
    return b.toString();
  }
}

/// Simple order statistics.
final class Stats {
  new(Iterable<num> values)
    : sorted = values.map((v) => v.toDouble()).toList()..sort();

  final List<double> sorted;

  int get n => sorted.length;
  double get mean => n == 0 ? 0 : sorted.reduce((a, b) => a + b) / n;
  double get min => n == 0 ? 0 : sorted.first;
  double get max => n == 0 ? 0 : sorted.last;

  /// Nearest-rank percentile.
  double pct(double p) {
    if (n == 0) return 0;
    final rank = (p / 100 * n).ceil().clamp(1, n);
    return sorted[rank - 1];
  }

  String row(String label, {int digits = 0}) {
    String f(double v) => v.toStringAsFixed(digits);
    return '| $label | $n | ${f(mean)} | ${f(pct(50))} | ${f(pct(90))} '
        '| ${f(pct(95))} | ${f(min)} | ${f(max)} |';
  }

  static const String header =
      '| measure | n | mean | p50 | p90 | p95 | min | max |\n'
      '|---|---|---|---|---|---|---|---|';
}

String pct(int a, int b) =>
    b == 0 ? 'n/a' : '${(100 * a / b).toStringAsFixed(1)}% ($a/$b)';
