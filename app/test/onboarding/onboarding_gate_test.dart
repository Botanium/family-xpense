import 'package:flutter_test/flutter_test.dart';
import 'package:xpense_app/core/routing/routing.dart';
import 'package:xpense_app/data/auth_repository_fake.dart';
import 'package:xpense_app/data/household_repository.dart';
import 'package:xpense_app/data/household_repository_fake.dart';
import 'package:xpense_app/features/onboarding/onboarding_gate.dart';
import 'package:xpense_shared/xpense_shared.dart';

const member = InHousehold(FakeHouseholdRepository.sampleHousehold);

/// Signed in, a member unless [membership] says otherwise.
String? redirect(
  String location, {
  required bool signedIn,
  Membership membership = member,
}) => onboardingRedirect(
  Uri.parse(location),
  signedIn: signedIn,
  membership: signedIn ? membership : const MembershipUnknown(),
);

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
    test('for a member the app is open, setup and join included', () {
      for (final location in [
        AppRoutes.home,
        AppRoutes.join,
        AppRoutes.householdSetup,
        OnboardingRoutes.tryIt,
        AppRoutes.askWith(text: 'lunch'),
      ]) {
        expect(redirect(location, signedIn: true), isNull, reason: location);
      }
    });

    test('the signed-out screens give way to Home for a member', () {
      for (final location in [
        OnboardingRoutes.welcome,
        OnboardingRoutes.createAccount,
        OnboardingRoutes.emailWith(signIn: true),
      ]) {
        expect(
          redirect(location, signedIn: true),
          AppRoutes.home,
          reason: location,
        );
      }
    });

    test('and to household setup for someone without one (WP-12)', () {
      for (final location in [
        OnboardingRoutes.welcome,
        OnboardingRoutes.createAccount,
        OnboardingRoutes.emailWith(signIn: true),
      ]) {
        expect(
          redirect(location, signedIn: true, membership: const NoHousehold()),
          AppRoutes.householdSetup,
          reason: location,
        );
      }
    });

    test('while the membership loads, the sign-in screen stays', () {
      expect(
        redirect(
          OnboardingRoutes.emailWith(signIn: true),
          signedIn: true,
          membership: const MembershipUnknown(),
        ),
        isNull,
      );
      // Elsewhere nothing moves until it is known.
      expect(
        redirect(
          AppRoutes.home,
          signedIn: true,
          membership: const MembershipUnknown(),
        ),
        isNull,
      );
    });

    test('without a household only setup and joining are open', () {
      const none = NoHousehold();
      for (final location in [
        AppRoutes.householdSetup,
        AppRoutes.join,
        AppRoutes.joinWith(code: 'ABCD2345XY'),
        OnboardingRoutes.terms,
      ]) {
        expect(
          redirect(location, signedIn: true, membership: none),
          isNull,
          reason: location,
        );
      }
      for (final location in [
        AppRoutes.home,
        AppRoutes.accounts,
        OnboardingRoutes.tryIt,
        AppRoutes.askWith(text: 'lunch'),
        AppRoutes.settings,
        '/householdx',
      ]) {
        expect(
          redirect(location, signedIn: true, membership: none),
          AppRoutes.householdSetup,
          reason: location,
        );
      }
    });

    test('the invite path gives way to the join screen, with the code', () {
      for (final membership in [
        member,
        const NoHousehold(),
        const MembershipUnknown(),
      ]) {
        expect(
          redirect(
            OnboardingRoutes.emailWith(invite: true),
            signedIn: true,
            membership: membership,
          ),
          AppRoutes.join,
        );
        expect(
          redirect(
            OnboardingRoutes.createAccountWith(code: 'ABCD2345XY'),
            signedIn: true,
            membership: membership,
          ),
          AppRoutes.joinWith(code: 'ABCD2345XY'),
        );
      }
    });

    test('no rule sends a location to one another rule rewrites', () {
      for (final (signedIn, membership) in [
        (false, const MembershipUnknown()),
        (true, const MembershipUnknown()),
        (true, const NoHousehold()),
        (true, member),
      ]) {
        for (final location in [
          AppRoutes.home,
          AppRoutes.householdSetup,
          OnboardingRoutes.tryIt,
          OnboardingRoutes.welcome,
          OnboardingRoutes.createAccountWith(invite: true, code: 'C0DE1234'),
          AppRoutes.joinWith(code: 'C0DE1234'),
        ]) {
          final first = redirect(
            location,
            signedIn: signedIn,
            membership: membership,
          );
          if (first == null) continue;
          expect(
            redirect(first, signedIn: signedIn, membership: membership),
            isNull,
            reason: '$location -> $first ($signedIn, $membership)',
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
      final households = FakeHouseholdRepository(auth: auth, onSignIn: member);
      final gate = OnboardingGate(auth, households);
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
      // Signed in, then the membership became known.
      expect(notified, 2);

      await auth.signOut();
      await pumpEventQueue();
      expect(notified, 4);
      expect(
        gate.redirect(Uri.parse(AppRoutes.home)),
        OnboardingRoutes.welcome,
      );
    });

    test(
      'notifies when the household appears or goes, not when it changes',
      () async {
        final auth = FakeAuthRepository(
          signedIn: FakeAuthRepository.providerUser,
        );
        final households = FakeHouseholdRepository(
          membership: const NoHousehold(),
          auth: auth,
        );
        final gate = OnboardingGate(auth, households);
        addTearDown(gate.dispose);
        var notified = 0;
        gate.addListener(() => notified++);
        await pumpEventQueue();
        expect(
          gate.redirect(Uri.parse(AppRoutes.home)),
          AppRoutes.householdSetup,
        );

        final result = await households.create(
          name: 'Our home',
          displayName: 'Alex',
          baseCurrency: Currency.usd,
        );
        expect(result, isA<Ok<String, HouseholdFailure>>());
        await pumpEventQueue();
        expect(notified, 1);
        expect(gate.redirect(Uri.parse(AppRoutes.home)), isNull);

        // The partner joining changes the household, not the membership kind.
        households.setMembership(
          const InHousehold(
            HouseholdSummary(
              id: 'fake-new-household',
              name: 'Our home',
              baseCurrency: Currency.usd,
              memberCount: 2,
            ),
          ),
        );
        await pumpEventQueue();
        expect(notified, 1);
      },
    );
  });
}
