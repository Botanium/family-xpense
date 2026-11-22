import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:xpense_app/data/auth_repository.dart';
import 'package:xpense_app/data/auth_repository_fake.dart';
import 'package:xpense_app/data/auth_repository_firebase.dart';
import 'package:xpense_shared/xpense_shared.dart';

void main() {
  group('authFailureFromCode', () {
    // The codes firebase_auth 7.1.0 reports on iOS (AuthErrors.swift turns
    // ERROR_FOO_BAR into foo-bar) and on the web.
    const table = <String, AuthFailure>{
      'canceled': AuthCancelled(),
      'web-context-cancelled': AuthCancelled(),
      'popup-closed-by-user': AuthCancelled(),
      'network-request-failed': AuthOffline(),
      'invalid-email': AuthInvalidEmail(),
      'wrong-password': AuthWrongCredentials(),
      'user-not-found': AuthWrongCredentials(),
      'invalid-credential': AuthWrongCredentials(),
      'email-already-in-use': AuthEmailInUse(),
      'weak-password': AuthWeakPassword(),
      'password-does-not-meet-requirements': AuthWeakPassword(),
      'too-many-requests': AuthTooManyAttempts(),
      'user-disabled': AuthAccountDisabled(),
      'account-exists-with-different-credential': AuthOtherMethod(),
      'operation-not-allowed': AuthMethodUnavailable(),
      'unsupported-platform': AuthMethodUnavailable(),
    };
    for (final MapEntry(key: code, value: failure) in table.entries) {
      test('$code is ${failure.code}', () {
        expect(authFailureFromCode(code), failure);
      });
    }

    test('an unknown code keeps the code as detail', () {
      expect(
        authFailureFromCode('keychain-error'),
        const AuthUnknown('keychain-error'),
      );
      expect(const AuthUnknown('x').code, 'auth.unknown');
    });

    test('every failure has a stable auth.* code and no user text', () {
      for (final failure in [...table.values, const AuthUnknown('x')]) {
        expect(failure.code, startsWith('auth.'));
        expect(failure.toString(), startsWith('auth.'));
      }
    });
  });

  group('parseEmulatorHost', () {
    test('reads host:port', () {
      expect(parseEmulatorHost('localhost:9099'), (
        host: 'localhost',
        port: 9099,
      ));
      expect(parseEmulatorHost(' 127.0.0.1:9099 '), (
        host: '127.0.0.1',
        port: 9099,
      ));
    });

    test('anything else means no emulator', () {
      for (final value in [
        null,
        '',
        'localhost',
        ':9099',
        'localhost:',
        'localhost:x',
        'h:0',
        'h:70000',
      ]) {
        expect(parseEmulatorHost(value), isNull, reason: '$value');
      }
    });
  });

  group('FakeAuthRepository', () {
    test('creates an email account, then signs in to it', () async {
      final auth = FakeAuthRepository();
      expect(auth.currentUser, isNull);

      final created = await auth.createAccountWithEmail(
        email: ' Ada@Example.com ',
        password: 'secret1',
      );
      expect(created, isA<Ok<AuthUser, AuthFailure>>());
      expect(auth.currentUser?.email, 'ada@example.com');

      await auth.signOut();
      expect(auth.currentUser, isNull);

      expect(
        await auth.signInWithEmail(
          email: 'ada@example.com',
          password: 'nope00',
        ),
        const Err<AuthUser, AuthFailure>(AuthWrongCredentials()),
      );
      expect(
        await auth.signInWithEmail(
          email: 'ada@example.com',
          password: 'secret1',
        ),
        isA<Ok<AuthUser, AuthFailure>>(),
      );
    });

    test(
      'refuses an address in use, a weak password and a bad address',
      () async {
        final auth = FakeAuthRepository()
          ..accounts['ada@example.com'] = 'secret1';
        expect(
          await auth.createAccountWithEmail(
            email: 'ada@example.com',
            password: 'secret2',
          ),
          const Err<AuthUser, AuthFailure>(AuthEmailInUse()),
        );
        expect(
          await auth.createAccountWithEmail(
            email: 'bo@example.com',
            password: '123',
          ),
          const Err<AuthUser, AuthFailure>(AuthWeakPassword()),
        );
        expect(
          await auth.createAccountWithEmail(email: 'bo', password: 'secret2'),
          const Err<AuthUser, AuthFailure>(AuthInvalidEmail()),
        );
        expect(auth.currentUser, isNull);
      },
    );

    test('nextFailure answers the next call only', () async {
      final auth = FakeAuthRepository()..nextFailure = const AuthOffline();
      expect(
        await auth.signInWithApple(),
        const Err<AuthUser, AuthFailure>(AuthOffline()),
      );
      expect(await auth.signInWithApple(), isA<Ok<AuthUser, AuthFailure>>());
      expect(auth.calls, ['apple', 'apple']);
    });

    test(
      'authStateChanges starts with the current user, then follows',
      () async {
        final auth = FakeAuthRepository();
        final seen = <AuthUser?>[];
        final sub = auth.authStateChanges().listen(seen.add);
        await pumpEventQueue();
        await auth.signInWithGoogle();
        await auth.signOut();
        await pumpEventQueue();
        await sub.cancel();
        expect(seen, [null, FakeAuthRepository.providerUser, null]);
      },
    );

    test('hold keeps a call open', () async {
      final auth = FakeAuthRepository()..hold = Completer<void>();
      var done = false;
      unawaited(auth.signInWithApple().then((_) => done = true));
      await pumpEventQueue();
      expect(done, isFalse);
      auth.hold!.complete();
      await pumpEventQueue();
      expect(done, isTrue);
    });

    test('a password reset needs a valid address', () async {
      final auth = FakeAuthRepository();
      expect(
        await auth.sendPasswordReset(email: 'x'),
        const Err<void, AuthFailure>(AuthInvalidEmail()),
      );
      expect(
        await auth.sendPasswordReset(email: 'ada@example.com'),
        isA<Ok<void, AuthFailure>>(),
      );
      expect(auth.resets, ['ada@example.com']);
    });
  });

  test('AuthUser keeps email and name out of its string form', () {
    const user = AuthUser(
      uid: 'u1',
      email: 'ada@example.com',
      displayName: 'Ada',
    );
    expect(user.toString(), 'AuthUser(u1)');
    expect(
      user,
      const AuthUser(uid: 'u1', email: 'ada@example.com', displayName: 'Ada'),
    );
  });
}
