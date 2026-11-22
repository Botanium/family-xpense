import 'dart:async';

import 'package:xpense_app/services/settings_store.dart';

/// A [SettingsStore] held in memory, for tests and previews.
final class MemorySettingsStore implements SettingsStore {
  /// Creates a store that starts with the given settings, or the defaults.
  new([this._current = AppSettings.defaults]);

  AppSettings _current;

  /// How many times [save] has committed; tests use it to prove a change
  /// was persisted.
  int saves = 0;

  /// When set, [save] throws this instead of saving.
  Exception? failWith;

  /// When set, every [save] waits for this to complete before it commits,
  /// so a test can overlap two saves.
  Completer<void>? gate;

  @override
  AppSettings get current => _current;

  @override
  Future<void> save(AppSettings settings) async {
    await gate?.future;
    if (failWith case final Exception error) throw error;
    _current = settings;
    saves++;
  }
}
