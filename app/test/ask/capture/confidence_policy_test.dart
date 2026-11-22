// The confidence policy (AI_PIPELINE 9, story S3.10).
import 'package:flutter_test/flutter_test.dart';
import 'package:xpense_app/features/ask/capture/confidence_policy.dart';
import 'package:xpense_app/services/feature_flags.dart';
import 'package:xpense_shared/xpense_shared.dart';

void main() {
  const policy = ConfidencePolicy(CaptureThresholds.defaults);
  ChoiceAnswer answer(String choice, double c) =>
      ChoiceAnswer(choice: choice, confidence: c);

  group('per field', () {
    test('at or above conf_high: prefilled, no badge', () {
      expect(
        policy.pick(answer('dining', 0.85), calibrated: true),
        const FieldPick(
          value: 'dining',
          confidence: 0.85,
          show: FieldShow.prefilled,
        ),
      );
    });

    test('between conf_low and conf_high: prefilled with Guessed', () {
      expect(
        policy.pick(answer('dining', 0.55), calibrated: true)!.show,
        FieldShow.guessed,
      );
      expect(
        policy.pick(answer('dining', 0.84), calibrated: true)!.show,
        FieldShow.guessed,
      );
    });

    test('below conf_low: not prefilled; the slip asks', () {
      expect(
        policy.pick(answer('dining', 0.54), calibrated: true),
        const FieldPick(value: null, confidence: 0.54, show: FieldShow.ask),
      );
    });

    test('the catch-all and a missing answer pick nothing', () {
      expect(policy.pick(answer('unspecified', 0.99), calibrated: true), null);
      expect(policy.pick(null, calibrated: true), null);
      expect(policy.pick(ChoiceAnswer(), calibrated: true), null);
    });
  });

  test('uncalibrated answers are capped at conf_on_device_cap, so they are '
      'never prefilled without a badge', () {
    final p = policy.pick(answer('dining', 0.97), calibrated: false)!;
    expect(p.confidence, 0.80);
    expect(p.show, FieldShow.guessed);
  });

  test('the intent asks below conf_intent_min', () {
    expect(policy.intentSettled(0.90), isTrue);
    expect(policy.intentSettled(0.89), isFalse);
  });

  test('the recurring offer follows recurring_offer', () {
    expect(policy.offersRecurring(0.75), isTrue);
    expect(policy.offersRecurring(0.74), isFalse);
  });

  test('thresholds from Remote Config move the bands', () {
    const strict = ConfidencePolicy(CaptureThresholds(high: 0.95, low: 0.7));
    expect(strict.showFor(0.9), FieldShow.guessed);
    expect(strict.showFor(0.6), FieldShow.ask);
  });

  test('follow-ups are asked intent, amount or currency, account, category, '
      'person, date', () {
    expect(
      inFollowUpOrder([
        'occurredOn',
        'categoryId',
        'personName',
        'intent',
        'accountId',
        'currency',
        'note',
      ]),
      [
        'intent',
        'currency',
        'accountId',
        'categoryId',
        'personName',
        'occurredOn',
        'note',
      ],
    );
  });

  group('FeatureFlags.fromValues', () {
    FeatureFlags read(Map<String, Object> values) => FeatureFlags.fromValues(
      getBool: (k) => values[k] as bool? ?? false,
      getDouble: (k) => values[k] as double? ?? 0,
    );

    test('reads every threshold and the router switch', () {
      final flags = read({
        ...FeatureFlags.remoteDefaults,
        'conf_high': 0.9,
        'router_no_model_uses_decide': false,
      });
      expect(flags.thresholds.high, 0.9);
      expect(flags.thresholds.low, 0.55);
      expect(flags.routerNoModelUsesDecide, isFalse);
    });

    test('a value outside 0 to 1 falls back to its default', () {
      final flags = read({...FeatureFlags.remoteDefaults, 'conf_low': 1.5});
      expect(flags.thresholds.low, 0.55);
    });

    test('conf_low above conf_high falls back to all defaults', () {
      final flags = read({
        ...FeatureFlags.remoteDefaults,
        'conf_low': 0.9,
        'conf_high': 0.6,
      });
      expect(flags.thresholds, CaptureThresholds.defaults);
    });
  });
}
