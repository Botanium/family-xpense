// The Remote Config adapter behind `FeatureFlagSource`. Only the
// composition root names this file.
import 'dart:async';

import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:flutter/foundation.dart';

import 'package:xpense_app/services/feature_flags.dart';

/// [FeatureFlagSource] over Firebase Remote Config.
///
/// [open] sets the local defaults before the first frame; values activated
/// on an earlier launch apply at once. [refresh] (after the first frame)
/// fetches and activates, then follows console changes in real time, so
/// turning a flag on needs neither a release nor a restart.
final class RemoteConfigFeatureFlags implements FeatureFlagSource {
  new _(this._config);

  /// Wraps [FirebaseRemoteConfig.instance] with the local defaults set.
  /// Call after `Firebase.initializeApp()`.
  static Future<RemoteConfigFeatureFlags> open() async {
    final config = FirebaseRemoteConfig.instance;
    await config.setDefaults(FeatureFlags.remoteDefaults);
    return RemoteConfigFeatureFlags._(config);
  }

  final FirebaseRemoteConfig _config;
  final StreamController<FeatureFlags> _changes =
      StreamController<FeatureFlags>.broadcast();
  StreamSubscription<RemoteConfigUpdate>? _updates;

  @override
  FeatureFlags get current => FeatureFlags.fromValues(
    getBool: _config.getBool,
    getDouble: _config.getDouble,
  );

  @override
  Stream<FeatureFlags> changes() => _changes.stream;

  @override
  Future<void> refresh() async {
    try {
      if (await _config.fetchAndActivate()) _changes.add(current);
    } on Exception catch (error) {
      // Offline or throttled: the activated values and defaults stay.
      debugPrint('Remote Config fetch failed: $error');
    }
    _updates ??= _config.onConfigUpdated.listen(
      (_) => unawaited(_activate()),
      onError: (Object error) =>
          debugPrint('Remote Config updates stopped: $error'),
    );
  }

  /// Stops following console changes and closes [changes].
  Future<void> dispose() async {
    await _updates?.cancel();
    await _changes.close();
  }

  Future<void> _activate() async {
    try {
      await _config.activate();
      _changes.add(current);
    } on Exception catch (error) {
      debugPrint('Remote Config activate failed: $error');
    }
  }
}
