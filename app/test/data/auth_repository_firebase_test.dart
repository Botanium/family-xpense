// The Firebase adapter's Google sign-in: native Google Sign-In's tokens go
// to `signInWithCredential`, and every failure on the way becomes an
// AuthFailure. Firebase Auth and Google's sheet are fakes; no plugin runs.
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:xpense_app/data/auth_repository.dart';
import 'package:xpense_app/data/auth_repository_firebase.dart';
import 'package:xpense_shared/xpense_shared.dart';

final class _User implements User {
  @override
  String get uid => 'u1';

  @override
  String? get email => 'ada@example.com';

  @override
  String? get displayName => 'Ada';

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _Credential implements UserCredential {
  new(this.user);

  @override
  final User? user;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Firebase Auth that records the credentials it is given and answers with
/// [_User], [nextError] or no user.
final class _Auth implements FirebaseAuth {
  final credentials = <AuthCredential>[];
  FirebaseAuthException? nextError;
  bool returnsNoUser = false;
  int signOuts = 0;

  @override
  Future<UserCredential> signInWithCredential(AuthCredential credential) async {
    credentials.add(credential);
    if (nextError case final error?) throw error;
    return _Credential(returnsNoUser ? null : _User());
  }

  @override
  Future<void> signOut() async => signOuts++;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Google's sheet: returns [tokens] or throws [error].
final class _Sheet implements GoogleAccountSheet {
  GoogleTokens tokens = (idToken: 'id-token', accessToken: 'access-token');
  Exception? error;
  Exception? signOutError;
  int shown = 0;
  int signOuts = 0;

  @override
  Future<GoogleTokens> authenticate() async {
    shown++;
    if (error case final error?) throw error;
    return tokens;
  }

  @override
  Future<void> signOut() async {
    signOuts++;
    if (signOutError case final error?) throw error;
  }
}

void main() {
  late _Auth auth;
  late _Sheet sheet;
  late FirebaseAuthRepository repository;
  late List<FlutterErrorDetails> reported;
  late FlutterExceptionHandler? previousOnError;

  setUp(() {
    auth = _Auth();
    sheet = _Sheet();
    repository = FirebaseAuthRepository(auth, google: sheet);
    reported = [];
    previousOnError = FlutterError.onError;
    FlutterError.onError = reported.add;
  });

  tearDown(() => FlutterError.onError = previousOnError);

  group('signInWithGoogle', () {
    test('signs in to Firebase with the Google tokens', () async {
      final result = await repository.signInWithGoogle();

      expect(
        result,
        const Ok<AuthUser, AuthFailure>(
          AuthUser(uid: 'u1', email: 'ada@example.com', displayName: 'Ada'),
        ),
      );
      final credential = auth.credentials.single as OAuthCredential;
      expect(credential.providerId, 'google.com');
      expect(credential.idToken, 'id-token');
      expect(credential.accessToken, 'access-token');
      expect(reported, isEmpty);
    });

    test('an ID token alone is enough', () async {
      sheet.tokens = (idToken: 'id-token', accessToken: null);
      expect(
        await repository.signInWithGoogle(),
        isA<Ok<AuthUser, AuthFailure>>(),
      );
      final credential = auth.credentials.single as OAuthCredential;
      expect(credential.idToken, 'id-token');
      expect(credential.accessToken, isNull);
    });

    test('closing the sheet is AuthCancelled, not reported', () async {
      sheet.error = const GoogleSignInException(
        code: GoogleSignInExceptionCode.canceled,
      );
      expect(
        await repository.signInWithGoogle(),
        const Err<AuthUser, AuthFailure>(AuthCancelled()),
      );
      expect(auth.credentials, isEmpty);
      expect(reported, isEmpty);
    });

    test('a misconfigured client is unavailable and reported', () async {
      sheet.error = const GoogleSignInException(
        code: GoogleSignInExceptionCode.clientConfigurationError,
        description: 'GoogleService-Info.plist has no CLIENT_ID',
      );
      expect(
        await repository.signInWithGoogle(),
        const Err<AuthUser, AuthFailure>(AuthMethodUnavailable()),
      );
      expect(auth.credentials, isEmpty);
      expect(reported, hasLength(1));
    });

    test('an untyped network error is AuthOffline', () async {
      sheet.error = PlatformException(code: 'NSURLErrorDomain: -1009');
      expect(
        await repository.signInWithGoogle(),
        const Err<AuthUser, AuthFailure>(AuthOffline()),
      );
      expect(reported, isEmpty);
    });

    test('another untyped error is AuthUnknown and reported', () async {
      sheet.error = PlatformException(code: 'com.google.HTTPStatus: 500');
      expect(
        await repository.signInWithGoogle(),
        const Err<AuthUser, AuthFailure>(
          AuthUnknown('google.com.google.HTTPStatus: 500'),
        ),
      );
      expect(reported, hasLength(1));
    });

    test('an email made with another method is AuthOtherMethod', () async {
      auth.nextError = FirebaseAuthException(
        code: 'account-exists-with-different-credential',
      );
      expect(
        await repository.signInWithGoogle(),
        const Err<AuthUser, AuthFailure>(AuthOtherMethod()),
      );
      expect(reported, isEmpty);
    });

    test('Firebase errors map as for every other method', () async {
      for (final (code, failure) in [
        ('network-request-failed', const AuthOffline()),
        ('user-disabled', const AuthAccountDisabled()),
        ('operation-not-allowed', const AuthMethodUnavailable()),
        ('invalid-credential', const AuthWrongCredentials()),
      ]) {
        auth.nextError = FirebaseAuthException(code: code);
        expect(
          await repository.signInWithGoogle(),
          Err<AuthUser, AuthFailure>(failure),
          reason: code,
        );
      }
      expect(reported, isEmpty);
    });

    test('an unknown Firebase code is AuthUnknown and reported', () async {
      auth.nextError = FirebaseAuthException(code: 'keychain-error');
      expect(
        await repository.signInWithGoogle(),
        const Err<AuthUser, AuthFailure>(AuthUnknown('keychain-error')),
      );
      expect(reported, hasLength(1));
    });

    test('no Firebase user is AuthUnknown(no_user)', () async {
      auth.returnsNoUser = true;
      expect(
        await repository.signInWithGoogle(),
        const Err<AuthUser, AuthFailure>(AuthUnknown('no_user')),
      );
    });
  });

  group('signOut', () {
    test('signs out of Firebase and Google', () async {
      await repository.signOut();
      expect(auth.signOuts, 1);
      expect(sheet.signOuts, 1);
    });

    test('a Google failure is reported, not thrown', () async {
      sheet.signOutError = PlatformException(code: 'keychain');
      await repository.signOut();
      expect(auth.signOuts, 1);
      expect(reported, hasLength(1));
    });
  });

  group('authFailureFromGoogle', () {
    test('maps every code Google names today', () {
      const table = <GoogleSignInExceptionCode, AuthFailure>{
        GoogleSignInExceptionCode.canceled: AuthCancelled(),
        GoogleSignInExceptionCode.clientConfigurationError:
            AuthMethodUnavailable(),
        GoogleSignInExceptionCode.providerConfigurationError:
            AuthMethodUnavailable(),
        GoogleSignInExceptionCode.unknownError: AuthUnknown(
          'google.unknownError',
        ),
        GoogleSignInExceptionCode.interrupted: AuthUnknown(
          'google.interrupted',
        ),
        GoogleSignInExceptionCode.uiUnavailable: AuthUnknown(
          'google.uiUnavailable',
        ),
        GoogleSignInExceptionCode.userMismatch: AuthUnknown(
          'google.userMismatch',
        ),
      };
      expect(table.keys, containsAll(GoogleSignInExceptionCode.values));
      for (final MapEntry(key: code, value: failure) in table.entries) {
        expect(authFailureFromGoogle(code), failure, reason: code.name);
      }
    });
  });

  group('authFailureFromGooglePlatformCode', () {
    test('NSURLErrorDomain is offline, anything else unknown', () {
      expect(
        authFailureFromGooglePlatformCode('NSURLErrorDomain: -1009'),
        const AuthOffline(),
      );
      expect(
        authFailureFromGooglePlatformCode('google_sign_in'),
        const AuthUnknown('google.google_sign_in'),
      );
    });
  });

  group('NativeGoogleAccountSheet', () {
    test('without a client id it fails as misconfigured, before the '
        'plugin is touched', () async {
      final sheet = NativeGoogleAccountSheet(clientId: null);
      await expectLater(
        sheet.authenticate(),
        throwsA(
          isA<GoogleSignInException>().having(
            (e) => e.code,
            'code',
            GoogleSignInExceptionCode.clientConfigurationError,
          ),
        ),
      );
      // Nothing to forget, and no plugin call.
      await sheet.signOut();
    });
  });
}
