import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Switches the owner flips in the Firebase console (Remote Config), so a
/// feature can be turned on without an app release.
///
/// Every flag has a local default that applies until a fetch lands, and
/// whenever the console has no value for it. Defaults are the safe side:
/// off.
@immutable
final class FeatureFlags {
  /// Creates flags; the defaults are what a build sees before any fetch.
  const new({this.appleSignInEnabled = false});

  /// What a fresh install sees.
  static const FeatureFlags defaults = FeatureFlags();

  /// Remote Config key of [appleSignInEnabled].
  static const String appleSignInKey = 'apple_sign_in_enabled';

  /// Local defaults, keyed as in Remote Config.
  static final Map<String, Object> remoteDefaults = {
    appleSignInKey: defaults.appleSignInEnabled,
  };

  /// Whether Create account offers "Continue with Apple". Off until the
  /// paid Apple Developer Program enrollment is approved (DECISIONS D-39).
  final bool appleSignInEnabled;

  @override
  bool operator ==(Object other) =>
      other is FeatureFlags && other.appleSignInEnabled == appleSignInEnabled;

  @override
  int get hashCode => appleSignInEnabled.hashCode;

  @override
  String toString() => 'FeatureFlags(appleSignIn: $appleSignInEnabled)';
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
