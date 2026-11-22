/// The confidence policy (AI_PIPELINE 9, story S3.10): what a field shows
/// for a given confidence. Pure; the thresholds come from Remote Config.
library;

import 'package:flutter/foundation.dart';
import 'package:xpense_app/services/feature_flags.dart';
import 'package:xpense_shared/xpense_shared.dart';

/// The Decisions catch-all option: "the message does not say"
/// (AI_PIPELINE 7). An answer about the message, never a value.
const String unspecifiedChoice = 'unspecified';

/// The order follow-ups are asked in, one at a time (AI_PIPELINE 9):
/// intent, amount or currency, account, category, person, date.
const List<String> followUpOrder = [
  'intent',
  'amountMinor',
  'currency',
  'accountId',
  'toAccountId',
  'categoryId',
  'personName',
  'occurredOn',
];

/// Sorts [fields] into [followUpOrder]; unknown fields go last, in their
/// given order.
List<String> inFollowUpOrder(Iterable<String> fields) {
  final given = fields.toSet();
  return [
    for (final f in followUpOrder)
      if (given.contains(f)) f,
    for (final f in given)
      if (!followUpOrder.contains(f)) f,
  ];
}

/// How a field is shown.
enum FieldShow {
  /// At or above `conf_high`, or set by a rule or the member's own words:
  /// prefilled, no badge.
  prefilled,

  /// Between `conf_low` and `conf_high`: prefilled with a "Guessed" badge.
  guessed,

  /// Below `conf_low`: not prefilled; the slip asks.
  ask,
}

/// One classified field after the policy.
@immutable
final class FieldPick {
  /// Creates a pick.
  const new({
    required this.value,
    required this.confidence,
    required this.show,
  });

  /// The chosen value, or null when the field is asked.
  final String? value;

  /// The confidence after the uncalibrated cap.
  final double confidence;

  /// How the field is shown.
  final FieldShow show;

  @override
  bool operator ==(Object other) =>
      other is FieldPick &&
      other.value == value &&
      other.confidence == confidence &&
      other.show == show;

  @override
  int get hashCode => Object.hash(value, confidence, show);

  @override
  String toString() => 'FieldPick($value, $confidence, ${show.name})';
}

/// Applies the thresholds to Decisions answers and on-device guesses.
@immutable
final class ConfidencePolicy {
  /// Creates the policy.
  const new(this.thresholds);

  /// The Remote Config thresholds.
  final CaptureThresholds thresholds;

  /// [confidence] capped at `conf_on_device_cap` when it came from an
  /// uncalibrated source (the Flash-Lite fallback, an on-device model).
  double cap(double confidence, {required bool calibrated}) {
    final c = confidence.clamp(0.0, 1.0);
    return calibrated || c < thresholds.onDeviceCap
        ? c
        : thresholds.onDeviceCap;
  }

  /// How a field with [confidence] (already capped) is shown.
  FieldShow showFor(double confidence) => confidence >= thresholds.high
      ? FieldShow.prefilled
      : confidence >= thresholds.low
      ? FieldShow.guessed
      : FieldShow.ask;

  /// The pick for a choice [answer], or null when there is no answer or it
  /// is the catch-all.
  FieldPick? pick(ChoiceAnswer? answer, {required bool calibrated}) {
    final choice = answer?.choice;
    if (answer == null || choice == null || choice == unspecifiedChoice) {
      return null;
    }
    final c = cap(answer.confidence ?? 0, calibrated: calibrated);
    final show = showFor(c);
    return FieldPick(
      value: show == FieldShow.ask ? null : choice,
      confidence: c,
      show: show,
    );
  }

  /// Whether an intent with [confidence] (already capped) may stand
  /// without asking (`conf_intent_min`).
  bool intentSettled(double confidence) => confidence >= thresholds.intentMin;

  /// Whether a recurring guess with [probability] earns the offer.
  bool offersRecurring(double probability) =>
      probability >= thresholds.recurringOffer;
}
