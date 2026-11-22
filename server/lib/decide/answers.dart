/// Maps Decisions answers to [DecideResponse].
///
/// A `choice` answer is `{choice, probabilities, confidence}`; a yes/no
/// answer is `{noul, confidence}`, where `noul` is P(yes) clipped to 0.01 to
/// 0.99 (WP-S4). An answer whose choice is not one of the options sent, or
/// whose numbers are out of range, is dropped rather than passed on.
library;

import 'package:xpense_agent/decide/classifier.dart';
import 'package:xpense_agent/decide/question_set.dart';
import 'package:xpense_shared/xpense_shared.dart';

/// The response for [plan] from the API's [answers].
DecideResponse mapAnswers(
  DecideRequestPlan plan,
  Map<String, Object?> answers, {
  required bool calibrated,
}) {
  final json = <String, Object?>{};
  for (final q in plan.asked) {
    final raw = answers[q.key];
    if (raw is! Map) continue;
    final answer = raw.cast<String, Object?>();
    final mapped = choiceQuestions.contains(q)
        ? _choice(answer, plan.options[q] ?? const {})
        : _yesNo(answer);
    if (mapped != null) json[q.key] = mapped;
  }
  json['calibrated'] = calibrated;
  return DecideResponse.fromJson(json);
}

Map<String, Object?>? _choice(Map<String, Object?> a, Set<String> options) {
  final choice = a['choice'];
  if (choice is! String || !options.contains(choice)) return null;
  final probabilities = <String, num>{
    if (a['probabilities'] case final Map<Object?, Object?> p)
      for (final MapEntry(:key, :value) in p.entries)
        if (key is String && options.contains(key) && _unit(value) != null)
          key: _unit(value)!,
  };
  final confidence = _unit(a['confidence']) ?? probabilities[choice];
  return {
    'choice': choice,
    if (probabilities.isNotEmpty) 'probabilities': probabilities,
    'confidence': ?confidence?.toDouble(),
  };
}

Map<String, Object?>? _yesNo(Map<String, Object?> a) {
  final p = _unit(a['noul'])?.toDouble();
  if (p == null) return null;
  final confidence =
      _unit(a['confidence'])?.toDouble() ?? (p > 0.5 ? p : 1 - p);
  return {'probability': p, 'confidence': confidence};
}

num? _unit(Object? v) => v is num && v >= 0 && v <= 1 ? v : null;

/// The question keys answered in [response].
Set<DecideQuestion> answeredIn(DecideResponse response) {
  final json = response.toJson();
  return {
    for (final q in DecideQuestion.values)
      if (json[q.key] != null) q,
  };
}
