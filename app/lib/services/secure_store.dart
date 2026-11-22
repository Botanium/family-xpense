import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Small secrets kept in the iOS Keychain (ARCHITECTURE 3.2), such as the
/// device's push token or a cached session key.
///
/// The adapter over `flutter_secure_storage` arrives with the first package
/// that stores a secret; until then the composition root uses
/// `MemorySecureStore`. Non-secret preferences live in `SettingsStore`.
abstract interface class SecureStore {
  /// Returns the value stored under [key], or null.
  Future<String?> read(String key);

  /// Stores [value] under [key].
  Future<void> write(String key, String value);

  /// Removes [key]; removing a missing key is not an error.
  Future<void> delete(String key);
}

/// The [SecureStore] for this run. Throws until the composition root sets
/// it.
final secureStoreProvider = Provider<SecureStore>(
  (ref) =>
      throw UnimplementedError('secureStoreProvider is set in bootstrap()'),
  name: 'secureStoreProvider',
);
