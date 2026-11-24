// The Firebase Auth adapter behind `AuthRepository` (ARCHITECTURE 4.4).
// Only the composition root names this file.
import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:google_sign_in/google_sign_in.dart';

import 'package:xpense_app/data/auth_repository.dart';
import 'package:xpense_shared/xpense_shared.dart';

/// [AuthRepository] over `firebase_auth`.
///
/// Apple uses `signInWithProvider` and its native sheet (needs the Sign in
/// with Apple entitlement). Google uses native Google Sign-In
/// ([GoogleAccountSheet]) and hands its tokens to `signInWithCredential`.
/// Firebase's own Google web flow is not used: its page on firebaseapp.com
/// calls Identity Toolkit with the iOS API key, which only accepts calls
/// that name an allowed iOS bundle id, so Google answered it with 403.
final class FirebaseAuthRepository implements AuthRepository {
  /// Wraps a Firebase Auth instance and Google's account sheet.
  new(this._auth, {required this._google});

  /// Wraps [FirebaseAuth.instance], pointed at the Auth emulator when
  /// [emulator] is `host:port` (from `--dart-define=XPENSE_AUTH_EMULATOR`).
  /// Google Sign-In uses the iOS OAuth client of the bundled
  /// GoogleService-Info.plist (`CLIENT_ID`). Call after
  /// `Firebase.initializeApp()`.
  static Future<FirebaseAuthRepository> connect({String? emulator}) async {
    final auth = FirebaseAuth.instance;
    final target = parseEmulatorHost(emulator);
    if (target != null) {
      await auth.useAuthEmulator(target.host, target.port);
    }
    return FirebaseAuthRepository(
      auth,
      google: NativeGoogleAccountSheet(
        clientId: Firebase.app().options.iosClientId,
      ),
    );
  }

  final FirebaseAuth _auth;
  final GoogleAccountSheet _google;

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
  Future<Result<AuthUser, AuthFailure>> signInWithGoogle() async {
    final GoogleTokens tokens;
    try {
      tokens = await _google.authenticate();
    } on GoogleSignInException catch (error, stack) {
      return Err(_googleFailure(error, stack));
    } on PlatformException catch (error, stack) {
      return Err(_googlePlatformFailure(error, stack));
    }
    // The Firebase errors, account linking included
    // (`account-exists-with-different-credential`), map as for every other
    // method.
    return await _run(
      () => _auth.signInWithCredential(
        GoogleAuthProvider.credential(
          idToken: tokens.idToken,
          accessToken: tokens.accessToken,
        ),
      ),
    );
  }

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
  Future<void> signOut() async {
    await _auth.signOut();
    // Forget the Google account too, so the next "Continue with Google"
    // asks which account. Firebase is already signed out, so a failure here
    // is reported, not thrown.
    try {
      await _google.signOut();
    } on Exception catch (error, stack) {
      _report(error, stack, 'while signing out of Google');
    }
  }

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
    if (failure is AuthUnknown) _report(error, stack, 'while signing in');
    return failure;
  }

  // A closed sheet is expected; a misconfigured client is a bug in the
  // build, so it is reported as well as shown as "unavailable".
  static AuthFailure _googleFailure(
    GoogleSignInException error,
    StackTrace stack,
  ) {
    final failure = authFailureFromGoogle(error.code);
    if (failure is! AuthCancelled) {
      _report(error, stack, 'while signing in with Google');
    }
    return failure;
  }

  static AuthFailure _googlePlatformFailure(
    PlatformException error,
    StackTrace stack,
  ) {
    final failure = authFailureFromGooglePlatformCode(error.code);
    if (failure is AuthUnknown) {
      _report(error, stack, 'while signing in with Google');
    }
    return failure;
  }

  static void _report(Object error, StackTrace stack, String context) {
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: error,
        stack: stack,
        library: 'auth_repository',
        context: ErrorDescription(context),
      ),
    );
  }

  static AuthUser? _toUser(User? user) => user == null
      ? null
      : AuthUser(
          uid: user.uid,
          email: user.email,
          displayName: user.displayName,
        );
}

/// Maps how Google's account sheet failed to an [AuthFailure].
///
/// Google says the list of codes may grow, so anything not named here is
/// [AuthUnknown] with the code's name as detail.
AuthFailure authFailureFromGoogle(GoogleSignInExceptionCode code) =>
    switch (code) {
      GoogleSignInExceptionCode.canceled => const AuthCancelled(),
      // No iOS OAuth client in the config, or the SDK is set up wrongly
      // (for example the REVERSED_CLIENT_ID URL scheme is missing).
      GoogleSignInExceptionCode.clientConfigurationError ||
      GoogleSignInExceptionCode.providerConfigurationError =>
        const AuthMethodUnavailable(),
      _ => AuthUnknown('google.${code.name}'),
    };

/// Maps an error the iOS plugin passes through untyped (a
/// `PlatformException` whose code is `<NSError domain>: <code>`) to an
/// [AuthFailure]. Errors of `NSURLErrorDomain` mean no connection.
AuthFailure authFailureFromGooglePlatformCode(String code) =>
    code.startsWith('NSURLErrorDomain')
    ? const AuthOffline()
    : AuthUnknown('google.$code');

/// The tokens of the Google account the person picked.
typedef GoogleTokens = ({String idToken, String? accessToken});

/// Google's account sheet, the native Google Sign-In SDK. A seam so the
/// repository is tested without the plugin.
abstract interface class GoogleAccountSheet {
  /// Shows the sheet and returns the picked account's tokens. Throws
  /// [GoogleSignInException] (code `canceled` when the person closed the
  /// sheet) or, for errors the plugin does not type, [PlatformException].
  Future<GoogleTokens> authenticate();

  /// Forgets the signed-in Google account on this phone.
  Future<void> signOut();
}

/// [GoogleAccountSheet] over the `google_sign_in` plugin.
final class NativeGoogleAccountSheet implements GoogleAccountSheet {
  /// Uses the iOS OAuth client `clientId` (`CLIENT_ID` in
  /// GoogleService-Info.plist). Its reversed form must be a URL scheme in
  /// Info.plist (Flutter/Flavors.xcconfig, checked when the app is built).
  new({required this._clientId});

  final String? _clientId;
  Future<void>? _initialized;

  // OpenID Connect scopes: granted with the sign-in itself, so asking for
  // their access token never shows a second sheet.
  static const _scopes = ['email', 'profile'];

  // `GoogleSignIn.initialize` may run only once per process; a failed run
  // may be tried again.
  Future<void> _initialize() async {
    final clientId = _clientId;
    if (clientId == null || clientId.isEmpty) {
      throw const GoogleSignInException(
        code: GoogleSignInExceptionCode.clientConfigurationError,
        description: 'GoogleService-Info.plist has no CLIENT_ID',
      );
    }
    final initializing = _initialized ??= GoogleSignIn.instance.initialize(
      clientId: clientId,
    );
    try {
      await initializing;
    } on Object {
      if (identical(_initialized, initializing)) _initialized = null;
      rethrow;
    }
  }

  @override
  Future<GoogleTokens> authenticate() async {
    await _initialize();
    final account = await GoogleSignIn.instance.authenticate(
      scopeHint: _scopes,
    );
    final idToken = account.authentication.idToken;
    if (idToken == null) {
      throw const GoogleSignInException(
        code: GoogleSignInExceptionCode.unknownError,
        description: 'Google returned no ID token',
      );
    }
    // Firebase needs only the ID token; the access token is passed when
    // Google has one without asking again.
    String? accessToken;
    try {
      accessToken = (await account.authorizationClient.authorizationForScopes(
        _scopes,
      ))?.accessToken;
    } on GoogleSignInException {
      accessToken = null;
    }
    return (idToken: idToken, accessToken: accessToken);
  }

  @override
  Future<void> signOut() async {
    // Without a client the sheet never opened, so nothing is remembered.
    // Otherwise the SDK may hold an account from an earlier launch.
    final clientId = _clientId;
    if (clientId == null || clientId.isEmpty) return;
    await _initialize();
    await GoogleSignIn.instance.signOut();
  }
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
