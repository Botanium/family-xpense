// Sign-in for one person on one phone (PRD ON-2, BACKLOG S1.3).
//
// This file is the interface features import. The Firebase adapter is
// `auth_repository_firebase.dart` and the fake is `auth_repository_fake.dart`;
// only the composition root and tests name them.
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:xpense_shared/xpense_shared.dart';

/// The person signed in on this phone.
@immutable
final class AuthUser {
  /// Creates a user.
  const new({required this.uid, this.email, this.displayName});

  /// The Firebase Auth uid; the id of the member document (DATA_MODEL 2.3).
  final String uid;

  /// The email, when the sign-in method shared one. Apple may hide it.
  final String? email;

  /// The name the sign-in method gave, if any.
  final String? displayName;

  @override
  bool operator ==(Object other) =>
      other is AuthUser &&
      other.uid == uid &&
      other.email == email &&
      other.displayName == displayName;

  @override
  int get hashCode => Object.hash(uid, email, displayName);

  // No email or name: this lands in logs.
  @override
  String toString() => 'AuthUser($uid)';
}

/// Why signing in, creating an account or resetting a password did not
/// work. A failure carries a stable [code], never a user-facing string; the
/// screen picks the words from the ARB file.
@immutable
sealed class AuthFailure implements Failure {
  const new();

  // Field-less failures are equal when they are the same case.
  @override
  bool operator ==(Object other) => other.runtimeType == runtimeType;

  @override
  int get hashCode => runtimeType.hashCode;

  @override
  String toString() => code;
}

/// The person closed the Apple or Google sheet. Not an error to show.
final class AuthCancelled extends AuthFailure {
  /// Creates the failure.
  const new();

  @override
  String get code => 'auth.cancelled';
}

/// No connection to Firebase Auth.
final class AuthOffline extends AuthFailure {
  /// Creates the failure.
  const new();

  @override
  String get code => 'auth.offline';
}

/// The email address is not a valid address.
final class AuthInvalidEmail extends AuthFailure {
  /// Creates the failure.
  const new();

  @override
  String get code => 'auth.invalid_email';
}

/// The email and password do not match an account. Firebase does not say
/// which one is wrong, so neither does the app.
final class AuthWrongCredentials extends AuthFailure {
  /// Creates the failure.
  const new();

  @override
  String get code => 'auth.wrong_credentials';
}

/// An account with this email already exists.
final class AuthEmailInUse extends AuthFailure {
  /// Creates the failure.
  const new();

  @override
  String get code => 'auth.email_in_use';
}

/// The new password is too weak for Firebase's password policy.
final class AuthWeakPassword extends AuthFailure {
  /// Creates the failure.
  const new();

  @override
  String get code => 'auth.weak_password';
}

/// Too many attempts from this phone; Firebase blocks it for a while.
final class AuthTooManyAttempts extends AuthFailure {
  /// Creates the failure.
  const new();

  @override
  String get code => 'auth.too_many_attempts';
}

/// The account was disabled by an administrator.
final class AuthAccountDisabled extends AuthFailure {
  /// Creates the failure.
  const new();

  @override
  String get code => 'auth.account_disabled';
}

/// The email already belongs to an account made with another method, such
/// as Google, so this method cannot sign in to it.
final class AuthOtherMethod extends AuthFailure {
  /// Creates the failure.
  const new();

  @override
  String get code => 'auth.other_method';
}

/// This sign-in method is not set up for the project or not supported on
/// this phone (for example Sign in with Apple before its entitlement).
final class AuthMethodUnavailable extends AuthFailure {
  /// Creates the failure.
  const new();

  @override
  String get code => 'auth.method_unavailable';
}

/// Anything else. The original error is reported where it was caught.
final class AuthUnknown extends AuthFailure {
  /// Creates the failure with a short machine-readable [detail].
  const new(this.detail);

  /// The Firebase error code or exception type. Never shown to the user.
  final String detail;

  @override
  String get code => 'auth.unknown';

  @override
  bool operator ==(Object other) =>
      other is AuthUnknown && other.detail == detail;

  @override
  int get hashCode => Object.hash(AuthUnknown, detail);

  @override
  String toString() => '$code($detail)';
}

/// Maps a Firebase Auth error code (`FirebaseAuthException.code`) to an
/// [AuthFailure]. Total: an unknown code gives [AuthUnknown].
///
/// Pure and here, not in the adapter, so the mapping is tested without a
/// Firebase app.
AuthFailure authFailureFromCode(String code) => switch (code) {
  // Apple's sheet reports `canceled`; the Google web sheet reports
  // `web-context-cancelled` (iOS) or `popup-closed-by-user` (web).
  'canceled' ||
  'cancelled' ||
  'web-context-cancelled' ||
  'web-context-canceled' ||
  'popup-closed-by-user' => const AuthCancelled(),
  'network-request-failed' => const AuthOffline(),
  'invalid-email' => const AuthInvalidEmail(),
  // With email enumeration protection on, Firebase answers both a wrong
  // password and an unknown email with `invalid-credential`.
  'wrong-password' ||
  'user-not-found' ||
  'invalid-credential' ||
  'invalid-login-credentials' ||
  'missing-password' => const AuthWrongCredentials(),
  'email-already-in-use' ||
  'credential-already-in-use' => const AuthEmailInUse(),
  'weak-password' ||
  'password-does-not-meet-requirements' => const AuthWeakPassword(),
  'too-many-requests' => const AuthTooManyAttempts(),
  'user-disabled' => const AuthAccountDisabled(),
  'account-exists-with-different-credential' => const AuthOtherMethod(),
  'operation-not-allowed' ||
  'unsupported-platform' ||
  'admin-restricted-operation' ||
  'not-handled' => const AuthMethodUnavailable(),
  _ => AuthUnknown(code),
};

/// Signs the person in with Firebase Auth (ARCHITECTURE 4.4).
///
/// Every method returns a [Result] and never throws for an expected
/// failure, so the screen switches over [AuthFailure]. The state of the
/// session is [currentUser] and [authStateChanges]; screens never navigate
/// on success themselves, the router's onboarding gate does.
abstract interface class AuthRepository {
  /// The signed-in person, or null. Correct synchronously from the first
  /// frame, so the router never shows Welcome to someone signed in.
  AuthUser? get currentUser;

  /// Emits the signed-in person, or null, whenever that changes.
  Stream<AuthUser?> authStateChanges();

  /// Sign in with Apple (shown first, DESIGN_SYSTEM 9, screen 2).
  Future<Result<AuthUser, AuthFailure>> signInWithApple();

  /// Sign in with Google.
  Future<Result<AuthUser, AuthFailure>> signInWithGoogle();

  /// Creates an email-and-password account and signs in to it.
  Future<Result<AuthUser, AuthFailure>> createAccountWithEmail({
    required String email,
    required String password,
  });

  /// Signs in to an existing email-and-password account.
  Future<Result<AuthUser, AuthFailure>> signInWithEmail({
    required String email,
    required String password,
  });

  /// Sends a password reset email. With email enumeration protection on,
  /// this succeeds whether or not an account exists.
  Future<Result<void, AuthFailure>> sendPasswordReset({required String email});

  /// Signs out on this phone.
  Future<void> signOut();
}

/// The [AuthRepository] for this run. Throws until the composition root
/// sets it.
final authRepositoryProvider = Provider<AuthRepository>(
  (ref) =>
      throw UnimplementedError('authRepositoryProvider is set in bootstrap()'),
  name: 'authRepositoryProvider',
);
