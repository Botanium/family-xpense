import 'package:xpense_app/services/secure_store.dart';

/// A [SecureStore] held in memory: for tests, and for the app until the
/// Keychain adapter lands. Nothing survives a restart.
final class MemorySecureStore implements SecureStore {
  /// Creates a store, optionally with [initial] values.
  new([Map<String, String> initial = const {}]) : _values = {...initial};

  final Map<String, String> _values;

  @override
  Future<String?> read(String key) async => _values[key];

  @override
  Future<void> write(String key, String value) async => _values[key] = value;

  @override
  Future<void> delete(String key) async => _values.remove(key);
}
