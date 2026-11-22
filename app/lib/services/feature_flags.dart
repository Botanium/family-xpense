import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The confidence policy of the capture pipeline (AI_PIPELINE 9), held in
/// Remote Config and mirrored on the server in `config/runtime`.
///
/// Initial values are estimates; WP-35 tunes them against the evaluation
/// set.
@immutable
final class CaptureThresholds {
  /// Creates thresholds; the defaults are AI_PIPELINE 9's.
  const new({
    this.high = 0.85,
    this.low = 0.55,
    this.intentMin = 0.90,
    this.onDeviceCap = 0.80,
    this.duplicateWarn = 0.80,
    this.recurringOffer = 0.75,
  });

  /// The documented defaults.
  static const CaptureThresholds defaults = CaptureThresholds();

  /// `conf_high`: at or above, prefill with no badge.
  final double high;

  /// `conf_low`: below, do not prefill; ask.
  final double low;

  /// `conf_intent_min`: an intent below this always asks.
  final double intentMin;

  /// `conf_on_device_cap`: ceiling for uncalibrated sources.
  final double onDeviceCap;

  /// `dup_warn`: show "Looks like one you already saved".
  final double duplicateWarn;

  /// `recurring_offer`: offer to repeat the entry after saving.
  final double recurringOffer;

  @override
  bool operator ==(Object other) =>
      other is CaptureThresholds &&
      other.high == high &&
      other.low == low &&
      other.intentMin == intentMin &&
      other.onDeviceCap == onDeviceCap &&
      other.duplicateWarn == duplicateWarn &&
      other.recurringOffer == recurringOffer;

  @override
  int get hashCode => Object.hash(
    high,
    low,
    intentMin,
    onDeviceCap,
    duplicateWarn,
    recurringOffer,
  );

  @override
  String toString() =>
      'CaptureThresholds(high: $high, low: $low, intent: $intentMin, '
      'cap: $onDeviceCap, dup: $duplicateWarn, recurring: $recurringOffer)';
}

/// Switches the owner flips in the Firebase console (Remote Config), so a
/// feature can be turned on without an app release.
///
/// Every flag has a local default that applies until a fetch lands, and
/// whenever the console has no value for it. Defaults are the safe side:
/// off, and for the capture pipeline the values in AI_PIPELINE 2 and 9.
@immutable
final class FeatureFlags {
  /// Creates flags; the defaults are what a build sees before any fetch.
  const new({
    this.appleSignInEnabled = false,
    this.routerNoModelUsesDecide = true,
    this.thresholds = CaptureThresholds.defaults,
  });

  /// Builds flags from Remote Config getters. A threshold outside 0 to 1,
  /// or a `conf_low` above `conf_high`, falls back to the defaults, so a
  /// console typo cannot turn every guess into a prefill.
  factory fromValues({
    required bool Function(String key) getBool,
    required double Function(String key) getDouble,
  }) {
    double unit(String key, double fallback) {
      final v = getDouble(key);
      return v.isNaN || v < 0 || v > 1 ? fallback : v;
    }

    const d = CaptureThresholds.defaults;
    var thresholds = CaptureThresholds(
      high: unit(confHighKey, d.high),
      low: unit(confLowKey, d.low),
      intentMin: unit(confIntentMinKey, d.intentMin),
      onDeviceCap: unit(confOnDeviceCapKey, d.onDeviceCap),
      duplicateWarn: unit(dupWarnKey, d.duplicateWarn),
      recurringOffer: unit(recurringOfferKey, d.recurringOffer),
    );
    if (thresholds.low > thresholds.high) thresholds = d;
    return FeatureFlags(
      appleSignInEnabled: getBool(appleSignInKey),
      routerNoModelUsesDecide: getBool(routerNoModelUsesDecideKey),
      thresholds: thresholds,
    );
  }

  /// What a fresh install sees.
  static const FeatureFlags defaults = FeatureFlags();

  /// Remote Config key of [appleSignInEnabled].
  static const String appleSignInKey = 'apple_sign_in_enabled';

  /// Remote Config key of [routerNoModelUsesDecide].
  static const String routerNoModelUsesDecideKey =
      'router_no_model_uses_decide';

  /// Remote Config keys of [thresholds] (AI_PIPELINE 9).
  static const String confHighKey = 'conf_high';

  /// See [confHighKey].
  static const String confLowKey = 'conf_low';

  /// See [confHighKey].
  static const String confIntentMinKey = 'conf_intent_min';

  /// See [confHighKey].
  static const String confOnDeviceCapKey = 'conf_on_device_cap';

  /// See [confHighKey].
  static const String dupWarnKey = 'dup_warn';

  /// See [confHighKey].
  static const String recurringOfferKey = 'recurring_offer';

  /// Local defaults, keyed as in Remote Config.
  static final Map<String, Object> remoteDefaults = {
    appleSignInKey: defaults.appleSignInEnabled,
    routerNoModelUsesDecideKey: defaults.routerNoModelUsesDecide,
    confHighKey: CaptureThresholds.defaults.high,
    confLowKey: CaptureThresholds.defaults.low,
    confIntentMinKey: CaptureThresholds.defaults.intentMin,
    confOnDeviceCapKey: CaptureThresholds.defaults.onDeviceCap,
    dupWarnKey: CaptureThresholds.defaults.duplicateWarn,
    recurringOfferKey: CaptureThresholds.defaults.recurringOffer,
  };

  /// Whether Create account offers "Continue with Apple". Off until the
  /// paid Apple Developer Program enrollment is approved (DECISIONS D-39).
  final bool appleSignInEnabled;

  /// Row 8 of the router (AI_PIPELINE 2): a single entry from a phone with
  /// no on-device model goes to `/decide` with the raw text. Off restores
  /// the brief's "no model, go to the agent".
  final bool routerNoModelUsesDecide;

  /// The confidence policy (AI_PIPELINE 9).
  final CaptureThresholds thresholds;

  @override
  bool operator ==(Object other) =>
      other is FeatureFlags &&
      other.appleSignInEnabled == appleSignInEnabled &&
      other.routerNoModelUsesDecide == routerNoModelUsesDecide &&
      other.thresholds == thresholds;

  @override
  int get hashCode =>
      Object.hash(appleSignInEnabled, routerNoModelUsesDecide, thresholds);

  @override
  String toString() =>
      'FeatureFlags(appleSignIn: $appleSignInEnabled, '
      'noModelUsesDecide: $routerNoModelUsesDecide, $thresholds)';
}

/// Where [FeatureFlags] come from (Remote Config in dev and prod, a fake
/// otherwise).
abstract interface class FeatureFlagSource {
  /// The flags as activated now: the values fetched on an earlier launch,
  /// or the local defaults. Available synchronously at startup.
  FeatureFlags get current;

  /// Emits the flags whenever newly fetched values are activated.
  Stream<FeatureFlags> changes();

  /// Fetches and activates the latest values, then keeps listening for
  /// console changes. Best effort: completes normally when offline, and the
  /// current values stay.
  Future<void> refresh();
}

/// The [FeatureFlagSource] for this run. Throws until the composition root
/// sets it.
final featureFlagSourceProvider = Provider<FeatureFlagSource>(
  (ref) => throw UnimplementedError(
    'featureFlagSourceProvider is set in bootstrap()',
  ),
  name: 'featureFlagSourceProvider',
);

/// Keeps [FeatureFlags] current while the app runs, so a flag turned on in
/// the console shows without a restart.
final class FeatureFlagsController extends Notifier<FeatureFlags> {
  @override
  FeatureFlags build() {
    final source = ref.watch(featureFlagSourceProvider);
    final subscription = source.changes().listen((flags) => state = flags);
    ref.onDispose(subscription.cancel);
    return source.current;
  }
}

/// The app's current [FeatureFlags]. Read one flag with `select`.
final NotifierProvider<FeatureFlagsController, FeatureFlags>
featureFlagsProvider = NotifierProvider<FeatureFlagsController, FeatureFlags>(
  FeatureFlagsController.new,
  name: 'featureFlagsProvider',
);
