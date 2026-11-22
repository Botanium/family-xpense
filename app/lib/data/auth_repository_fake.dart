// An in-memory `AuthRepository` for tests and the `fakes` environment.
// Only the composition root and tests name this file.
import 'dart:async';

import 'package:xpense_app/data/auth_repository.dart';
import 'package:xpense_shared/xpense_shared.dart';

/// An [AuthRepository] that keeps accounts in memory.
///
/// Apple and Google sign in as [providerUser] at once. Email accounts behave
/// like Firebase's: a new address needs an `@` and a password of at least
/// [minPasswordLength] characters, and signing in needs the same password.
/// Tests steer it with [nextFailure] and hold calls open with [hold].
final class FakeAuthRepository implements AuthRepository {
  /// Creates the fake, signed in as [signedIn] (or signed out).
  new({AuthUser? signedIn}) : _user = signedIn;

  /// Who Apple and Google sign in as.
  static const AuthUser providerUser = AuthUser(
    uid: 'fake-provider-user',
    email: 'you@example.com',
    displayName: 'You',
  );

  /// Shortest password the fake accepts, like Firebase's default policy.
  static const int minPasswordLength = 6;

  AuthUser? _user;
  final StreamController<AuthUser?> _changes =
      StreamController<AuthUser?>.broadcast(sync: true);

  /// Email accounts: address to password.
  final Map<String, String> accounts = {};

  /// When set, the next call fails with it (then it clears).
  AuthFailure? nextFailure;

  /// When set, every call waits for it before answering, so a test can see
  /// the loading state.
  Completer<void>? hold;

  /// Every call made, by name, in order.
  final List<String> calls = [];

  /// Emails that were sent a password reset.
  final List<String> resets = [];

  @override
  AuthUser? get currentUser => _user;

  @override
  Stream<AuthUser?> authStateChanges() async* {
    yield _user;
    yield* _changes.stream;
  }

  @override
  Future<Result<AuthUser, AuthFailure>> signInWithApple() =>
      _answer('apple', () => _signIn(providerUser));

  @override
  Future<Result<AuthUser, AuthFailure>> signInWithGoogle() =>
      _answer('google', () => _signIn(providerUser));

  @override
  Future<Result<AuthUser, AuthFailure>> createAccountWithEmail({
    required String email,
    required String password,
  }) => _answer('createAccountWithEmail', () {
    final address = email.trim().toLowerCase();
    if (!address.contains('@')) return const Err(AuthInvalidEmail());
    if (accounts.containsKey(address)) return const Err(AuthEmailInUse());
    if (password.length < minPasswordLength) {
      return const Err(AuthWeakPassword());
    }
    accounts[address] = password;
    return _signIn(_emailUser(address));
  });

  @override
  Future<Result<AuthUser, AuthFailure>> signInWithEmail({
    required String email,
    required String password,
  }) => _answer('signInWithEmail', () {
    final address = email.trim().toLowerCase();
    if (!address.contains('@')) return const Err(AuthInvalidEmail());
    if (accounts[address] != password) {
      return const Err(AuthWrongCredentials());
    }
    return _signIn(_emailUser(address));
  });

  @override
  Future<Result<void, AuthFailure>> sendPasswordReset({
    required String email,
  }) => _answer('sendPasswordReset', () {
    final address = email.trim().toLowerCase();
    if (!address.contains('@')) return const Err(AuthInvalidEmail());
    resets.add(address);
    return const Ok(null);
  });

  @override
  Future<void> signOut() async {
    calls.add('signOut');
    _set(null);
  }

  /// Closes the change stream.
  Future<void> dispose() => _changes.close();

  Future<Result<T, AuthFailure>> _answer<T>(
    String name,
    Result<T, AuthFailure> Function() outcome,
  ) async {
    calls.add(name);
    await hold?.future;
    final failure = nextFailure;
    if (failure != null) {
      nextFailure = null;
      return Err(failure);
    }
    return outcome();
  }

  Result<AuthUser, AuthFailure> _signIn(AuthUser user) {
    _set(user);
    return Ok(user);
  }

  void _set(AuthUser? user) {
    _user = user;
    if (!_changes.isClosed) _changes.add(user);
  }

  static AuthUser _emailUser(String address) =>
      AuthUser(uid: 'fake-email-${address.hashCode}', email: address);
}
