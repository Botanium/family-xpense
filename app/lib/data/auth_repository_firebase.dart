// The Firebase Auth adapter behind `AuthRepository` (ARCHITECTURE 4.4).
// Only the composition root names this file.
import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import 'package:xpense_app/data/auth_repository.dart';
import 'package:xpense_shared/xpense_shared.dart';

/// [AuthRepository] over `firebase_auth`.
///
/// Apple and Google both use `signInWithProvider`: Apple through the native
/// sheet (needs the Sign in with Apple entitlement), Google through the
/// Firebase web flow (needs the app's callback URL scheme in Info.plist).
/// No Google or Apple SDK is added.
final class FirebaseAuthRepository implements AuthRepository {
  /// Wraps a Firebase Auth instance.
  new(this._auth);

  /// Wraps [FirebaseAuth.instance], pointed at the Auth emulator when
  /// [emulator] is `host:port` (from `--dart-define=XPENSE_AUTH_EMULATOR`).
  /// Call after `Firebase.initializeApp()`.
  static Future<FirebaseAuthRepository> connect({String? emulator}) async {
    final auth = FirebaseAuth.instance;
    final target = parseEmulatorHost(emulator);
    if (target != null) {
      await auth.useAuthEmulator(target.host, target.port);
    }
    return FirebaseAuthRepository(auth);
  }

  final FirebaseAuth _auth;

  @override
  AuthUser? get currentUser => _toUser(_auth.currentUser);

  @override
  Stream<AuthUser?> authStateChanges() => _auth.authStateChanges().map(_toUser);

  @override
  Future<Result<AuthUser, AuthFailure>> signInWithApple() => _run(
    () => _auth.signInWithProvider(
      AppleAuthProvider()
        ..addScope('email')
        ..addScope('name'),
    ),
  );

  @override
  Future<Result<AuthUser, AuthFailure>> signInWithGoogle() => _run(
    () => _auth.signInWithProvider(
      GoogleAuthProvider()..setCustomParameters({'prompt': 'select_account'}),
    ),
  );

  @override
  Future<Result<AuthUser, AuthFailure>> createAccountWithEmail({
    required String email,
    required String password,
  }) => _run(
    () => _auth.createUserWithEmailAndPassword(
      email: email.trim(),
      password: password,
    ),
  );

  @override
  Future<Result<AuthUser, AuthFailure>> signInWithEmail({
    required String email,
    required String password,
  }) => _run(
    () => _auth.signInWithEmailAndPassword(
      email: email.trim(),
      password: password,
    ),
  );

  @override
  Future<Result<void, AuthFailure>> sendPasswordReset({
    required String email,
  }) async {
    try {
      await _auth.sendPasswordResetEmail(email: email.trim());
      return const Ok(null);
    } on FirebaseAuthException catch (error, stack) {
      return Err(_failure(error, stack));
    }
  }

  @override
  Future<void> signOut() => _auth.signOut();

  Future<Result<AuthUser, AuthFailure>> _run(
    Future<UserCredential> Function() call,
  ) async {
    try {
      final user = _toUser((await call()).user);
      return user == null
          ? const Err(AuthUnknown('no_user'))
          : Ok<AuthUser, AuthFailure>(user);
    } on FirebaseAuthException catch (error, stack) {
      return Err(_failure(error, stack));
    }
  }

  // Expected failures (a wrong password, a closed sheet) are values, not
  // bugs; only codes the app does not know are reported.
  static AuthFailure _failure(FirebaseAuthException error, StackTrace stack) {
    final failure = authFailureFromCode(error.code);
    if (failure is AuthUnknown) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stack,
          library: 'auth_repository',
          context: ErrorDescription('while signing in'),
        ),
      );
    }
    return failure;
  }

  static AuthUser? _toUser(User? user) => user == null
      ? null
      : AuthUser(
          uid: user.uid,
          email: user.email,
          displayName: user.displayName,
        );
}

/// Parses `host:port` for the Auth emulator; null when [value] is empty or
/// malformed, so a bad define means "no emulator" rather than a crash.
({String host, int port})? parseEmulatorHost(String? value) {
  final text = value?.trim() ?? '';
  final colon = text.lastIndexOf(':');
  if (colon <= 0) return null;
  final port = int.tryParse(text.substring(colon + 1));
  if (port == null || port <= 0 || port > 65535) return null;
  return (host: text.substring(0, colon), port: port);
}
