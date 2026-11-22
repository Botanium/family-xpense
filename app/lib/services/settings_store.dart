import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Which theme the app paints.
enum AppearanceMode {
  /// Follow the iPhone's light or dark setting.
  system,

  /// Always the Signal light theme.
  light,

  /// Always the graphite dark theme.
  dark,
}

/// The phone-local settings the first frame needs (ARCHITECTURE 3.3).
///
/// Household settings (privacy mode, base currency, rate label) live in
/// Firestore and arrive with their packages; this holds only what belongs
/// to this phone and must be known before the first paint.
@immutable
final class AppSettings {
  /// Creates settings; the defaults are what a fresh install sees.
  const new({this.appearance = AppearanceMode.system, this.faceIdLock = false});

  /// What a fresh install sees.
  static const AppSettings defaults = AppSettings();

  /// The theme to paint.
  final AppearanceMode appearance;

  /// Whether the app asks for Face ID (or the passcode) on a cold start and
  /// after a minute in the background (BACKLOG S1.2).
  final bool faceIdLock;

  /// Returns a copy with the given fields replaced.
  AppSettings copyWith({AppearanceMode? appearance, bool? faceIdLock}) =>
      AppSettings(
        appearance: appearance ?? this.appearance,
        faceIdLock: faceIdLock ?? this.faceIdLock,
      );

  @override
  bool operator ==(Object other) =>
      other is AppSettings &&
      other.appearance == appearance &&
      other.faceIdLock == faceIdLock;

  @override
  int get hashCode => Object.hash(appearance, faceIdLock);

  @override
  String toString() =>
      'AppSettings(appearance: ${appearance.name}, faceIdLock: $faceIdLock)';
}

/// Storage keys and their encoding, shared by every [SettingsStore] that
/// writes key-value pairs, so a bad stored value always falls back to the
/// default instead of failing the launch.
abstract final class SettingsKeys {
  /// Appearance, stored as the [AppearanceMode] name.
  static const String appearance = 'settings.appearance';

  /// Face ID lock, stored as a bool.
  static const String faceIdLock = 'settings.faceIdLock';

  /// Every key, for stores that preload an allow-list.
  static const Set<String> all = {appearance, faceIdLock};

  /// Decodes stored values; unknown or missing values become defaults.
  static AppSettings decode({String? appearance, bool? faceIdLock}) =>
      AppSettings(
        appearance:
            AppearanceMode.values.asNameMap()[appearance] ??
            AppSettings.defaults.appearance,
        faceIdLock: faceIdLock ?? AppSettings.defaults.faceIdLock,
      );
}

/// Reads and writes [AppSettings] on this phone.
///
/// The store is opened by the composition root before `runApp`, so
/// [current] is available synchronously when the first frame is built and
/// the theme never flips after launch.
abstract interface class SettingsStore {
  /// The settings read at startup, or the last ones saved.
  AppSettings get current;

  /// Persists [settings]. Completes after the write is committed.
  Future<void> save(AppSettings settings);
}

/// The [SettingsStore] for this run. Throws until the composition root sets
/// it.
final settingsStoreProvider = Provider<SettingsStore>(
  (ref) =>
      throw UnimplementedError('settingsStoreProvider is set in bootstrap()'),
  name: 'settingsStoreProvider',
);

/// The single source of truth for [AppSettings] in the running app.
///
/// The root reads it for the theme and the lock; Settings changes it. A
/// change is published only after the store has committed it.
///
/// Changes are queued: each one is applied to the settings as they stand
/// after every earlier change has been saved, so two changes made while a
/// save is still running both survive (PR #13 review). There is no way to
/// save a whole snapshot, which is what let a later save undo an earlier
/// one.
final class AppSettingsController extends Notifier<AppSettings> {
  Future<void> _queue = Future<void>.value();

  @override
  AppSettings build() => ref.watch(settingsStoreProvider).current;

  /// Applies [change] to the latest settings, persists the result, then
  /// publishes it. Completes once this change is committed. Throws what the
  /// store throws, so the caller can report it; the published value is then
  /// unchanged, and later changes still run.
  Future<void> update(AppSettings Function(AppSettings current) change) {
    final run = _queue.then((_) => _apply(change));
    // A failed save must not block the changes queued after it.
    _queue = run.then<void>((_) {}, onError: (Object _) {});
    return run;
  }

  Future<void> _apply(AppSettings Function(AppSettings current) change) async {
    if (!ref.mounted) return;
    final next = change(state);
    if (next == state) return;
    await ref.read(settingsStoreProvider).save(next);
    if (!ref.mounted) return;
    state = next;
  }
}

/// The app's current [AppSettings].
final appSettingsProvider =
    NotifierProvider<AppSettingsController, AppSettings>(
      AppSettingsController.new,
      name: 'appSettingsProvider',
    );
