import 'dart:async';

import 'package:xpense_app/services/feature_flags.dart';

/// A [FeatureFlagSource] held in memory, for tests and the `fakes`
/// environment. Calling `set` plays the part of a console change.
final class FakeFeatureFlags implements FeatureFlagSource {
  /// Starts with the given flags, by default [FeatureFlags.defaults].
  new([this._flags = FeatureFlags.defaults]);

  FeatureFlags _flags;
  final StreamController<FeatureFlags> _changes =
      StreamController<FeatureFlags>.broadcast(sync: true);

  /// How many times [refresh] was called.
  int refreshes = 0;

  @override
  FeatureFlags get current => _flags;

  @override
  Stream<FeatureFlags> changes() => _changes.stream;

  @override
  Future<void> refresh() async => refreshes++;

  /// Changes the flags, as if the owner flipped them in the console.
  void set(FeatureFlags flags) {
    _flags = flags;
    if (!_changes.isClosed) _changes.add(flags);
  }

  /// Closes the change stream.
  Future<void> dispose() => _changes.close();
}
