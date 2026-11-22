import 'package:shared_preferences/shared_preferences.dart';

import 'package:xpense_app/services/settings_store.dart';

/// [SettingsStore] over iOS `UserDefaults`, through `shared_preferences`.
///
/// [open] loads every settings key into memory once, so reads during the
/// first frame are synchronous. Values are not secrets; secrets go to
/// `SecureStore`.
final class PrefsSettingsStore implements SettingsStore {
  new _(this._prefs, this._current);

  /// Opens the store and reads the saved settings. The composition root
  /// awaits this before `runApp`.
  static Future<PrefsSettingsStore> open() async {
    final prefs = await SharedPreferencesWithCache.create(
      cacheOptions: const SharedPreferencesWithCacheOptions(
        allowList: SettingsKeys.all,
      ),
    );
    return PrefsSettingsStore._(
      prefs,
      SettingsKeys.decode(
        appearance: _read<String>(prefs, SettingsKeys.appearance),
        faceIdLock: _read<bool>(prefs, SettingsKeys.faceIdLock),
      ),
    );
  }

  final SharedPreferencesWithCache _prefs;
  AppSettings _current;

  @override
  AppSettings get current => _current;

  @override
  Future<void> save(AppSettings settings) async {
    await _prefs.setString(SettingsKeys.appearance, settings.appearance.name);
    await _prefs.setBool(SettingsKeys.faceIdLock, settings.faceIdLock);
    _current = settings;
  }

  // A value of another type under the same key counts as missing, so the
  // default applies instead of failing the launch.
  static T? _read<T extends Object>(
    SharedPreferencesWithCache prefs,
    String key,
  ) => switch (prefs.get(key)) {
    final T value => value,
    _ => null,
  };
}
