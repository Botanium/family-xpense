import 'package:flutter_test/flutter_test.dart';
import 'package:xpense_app/core/routing/routing.dart';
import 'package:xpense_app/data/auth_repository_fake.dart';
import 'package:xpense_app/features/onboarding/onboarding_gate.dart';

String? redirect(String location, {required bool signedIn}) =>
    onboardingRedirect(Uri.parse(location), signedIn: signedIn);

void main() {
  group('onboardingRedirect, signed out', () {
    test('Welcome and its sign-in screens stay open', () {
      for (final location in [
        OnboardingRoutes.welcome,
        '${OnboardingRoutes.welcome}?code=ABCD2345XY',
        OnboardingRoutes.createAccount,
        OnboardingRoutes.createAccountWith(invite: true),
        OnboardingRoutes.email,
        OnboardingRoutes.emailWith(signIn: true),
      ]) {
        expect(redirect(location, signedIn: false), isNull, reason: location);
      }
    });

    test('everything else goes to Welcome', () {
      for (final location in [
        AppRoutes.home,
        AppRoutes.activity,
        AppRoutes.askWith(text: 'lunch'),
        AppRoutes.settings,
        AppRoutes.entry('t1'),
        OnboardingRoutes.tryIt,
        '/welcomeback',
      ]) {
        expect(
          redirect(location, signedIn: false),
          OnboardingRoutes.welcome,
          reason: location,
        );
      }
    });

    test('a join link keeps its code on the way to Welcome', () {
      expect(
        redirect(AppRoutes.joinWith(code: 'ABCD2345XY'), signedIn: false),
        '/welcome?code=ABCD2345XY',
      );
      expect(
        redirect(AppRoutes.join, signedIn: false),
        OnboardingRoutes.welcome,
      );
    });

    test('legal pages, not-found and the gallery are open to all', () {
      for (final location in [
        OnboardingRoutes.terms,
        OnboardingRoutes.privacy,
        AppRoutes.notFound,
        AppRoutes.gallery,
      ]) {
        expect(redirect(location, signedIn: false), isNull, reason: location);
        expect(redirect(location, signedIn: true), isNull, reason: location);
      }
    });
  });

  group('onboardingRedirect, signed in', () {
    test('the app is open', () {
      for (final location in [
        AppRoutes.home,
        AppRoutes.join,
        OnboardingRoutes.tryIt,
        AppRoutes.askWith(text: 'lunch'),
      ]) {
        expect(redirect(location, signedIn: true), isNull, reason: location);
      }
    });

    test('the signed-out screens give way to Try it', () {
      for (final location in [
        OnboardingRoutes.welcome,
        OnboardingRoutes.createAccount,
        OnboardingRoutes.emailWith(signIn: true),
      ]) {
        expect(
          redirect(location, signedIn: true),
          OnboardingRoutes.tryIt,
          reason: location,
        );
      }
    });

    test('the invite path gives way to the join screen, with the code', () {
      expect(
        redirect(OnboardingRoutes.emailWith(invite: true), signedIn: true),
        AppRoutes.join,
      );
      expect(
        redirect(
          OnboardingRoutes.createAccountWith(code: 'ABCD2345XY'),
          signedIn: true,
        ),
        AppRoutes.joinWith(code: 'ABCD2345XY'),
      );
    });

    test('no rule sends a location to one another rule rewrites', () {
      for (final signedIn in [true, false]) {
        for (final location in [
          AppRoutes.home,
          OnboardingRoutes.welcome,
          OnboardingRoutes.createAccountWith(invite: true, code: 'C0DE1234'),
          AppRoutes.joinWith(code: 'C0DE1234'),
        ]) {
          final first = redirect(location, signedIn: signedIn);
          if (first == null) continue;
          expect(
            redirect(first, signedIn: signedIn),
            isNull,
            reason: '$location -> $first (signedIn: $signedIn)',
          );
        }
      }
    });
  });

  group('OnboardingRoutes', () {
    test('builders put identity in the query', () {
      expect(OnboardingRoutes.welcomeWith(), '/welcome');
      expect(OnboardingRoutes.welcomeWith(code: ''), '/welcome');
      expect(
        OnboardingRoutes.createAccountWith(invite: true, code: 'X1'),
        '/welcome/account?invite=1&code=X1',
      );
      expect(
        OnboardingRoutes.emailWith(signIn: true),
        '/welcome/account/email?mode=signin',
      );
    });
  });

  group('OnboardingGate', () {
    test('notifies once per sign-in or sign-out, and redirects live', () async {
      final auth = FakeAuthRepository();
      final gate = OnboardingGate(auth);
      addTearDown(gate.dispose);
      var notified = 0;
      gate.addListener(() => notified++);
      await pumpEventQueue();

      expect(
        gate.redirect(Uri.parse(AppRoutes.home)),
        OnboardingRoutes.welcome,
      );
      await auth.signInWithApple();
      // The repository knows before its event arrives.
      expect(gate.redirect(Uri.parse(AppRoutes.home)), isNull);
      await pumpEventQueue();
      expect(notified, 1);

      await auth.signOut();
      await pumpEventQueue();
      expect(notified, 2);
      expect(
        gate.redirect(Uri.parse(AppRoutes.home)),
        OnboardingRoutes.welcome,
      );
    });
  });
}
