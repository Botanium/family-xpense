import 'dart:async';

import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xpense_app/app.dart';
import 'package:xpense_app/core/routing/routing.dart';
import 'package:xpense_app/core/theme/theme.dart';
import 'package:xpense_app/core/ui/ui.dart';
import 'package:xpense_app/data/auth_repository.dart';
import 'package:xpense_app/data/auth_repository_fake.dart';
import 'package:xpense_app/features/onboarding/onboarding_gate.dart';
import 'package:xpense_app/services/feature_flags.dart';
import 'package:xpense_app/services/service_failure.dart';
import 'package:xpense_app/services/speech_capture.dart';

import '../routing/router_test.dart' show openLink;
import '../support/test_app.dart';

/// An iPhone 12 to 14 class screen, as on the reference artboards.
void usePhone(WidgetTester tester) {
  tester.view
    ..physicalSize = const Size(390, 844) * 3
    ..devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

Future<ProviderContainer> pumpSignedOut(
  WidgetTester tester, [
  TestServices? services,
]) {
  usePhone(tester);
  return pumpXpenseApp(tester, services ?? TestServices(signedIn: false));
}

/// Signed out, with Apple sign-in turned on in Remote Config.
TestServices appleOn() => TestServices(
  signedIn: false,
  flags: const FeatureFlags(appleSignInEnabled: true),
);

Uri location(ProviderContainer container) =>
    container.read(routerProvider).state.uri;

/// Scrolls [label] into view, taps it and settles.
Future<void> tapLabel(WidgetTester tester, String label) async {
  final target = find.text(label, skipOffstage: false);
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tester.tap(target);
  await tester.pumpAndSettle();
}

Future<ProviderContainer> openCreateAccount(
  WidgetTester tester, [
  TestServices? services,
]) async {
  final container = await pumpSignedOut(tester, services);
  await tapLabel(tester, 'Get started');
  return container;
}

Future<ProviderContainer> openEmail(
  WidgetTester tester, [
  TestServices? services,
]) async {
  final container = await openCreateAccount(tester, services);
  await tapLabel(tester, 'Continue with email');
  return container;
}

Finder field(String label) => find.descendant(
  of: find.ancestor(of: find.text(label), matching: find.byType(XpTextField)),
  matching: find.byType(EditableText),
);

/// What iOS may autofill into the field labelled [label]. The Cupertino
/// field hands hints to the platform itself, not to its EditableText.
Iterable<String>? autofill(WidgetTester tester, String label) => tester
    .widget<CupertinoTextField>(
      find.descendant(
        of: find.ancestor(
          of: find.text(label),
          matching: find.byType(XpTextField),
        ),
        matching: find.byType(CupertinoTextField),
      ),
    )
    .autofillHints;

void main() {
  group('Welcome (screen 1)', () {
    testWidgets('signed out, the app opens on Welcome, not Home', (
      tester,
    ) async {
      final container = await pumpSignedOut(tester);

      expect(location(container).path, OnboardingRoutes.welcome);
      expect(find.text('Family Xpense'), findsOneWidget);
      expect(find.text("Say it. We'll sort it."), findsOneWidget);
      expect(find.byType(TranscriptQuote), findsOneWidget);
      expect(find.byType(EntrySlip), findsOneWidget);
      expect(find.textContaining('USD 60', findRichText: true), findsOneWidget);
      expect(find.text('≈ IQD 102,300'), findsOneWidget);
      expect(find.text('Get started'), findsOneWidget);
      expect(find.text('I have an invite from my partner'), findsOneWidget);
      expect(find.byType(XpTabBar), findsNothing);
    });

    testWidgets('signed in, the app opens on Home', (tester) async {
      usePhone(tester);
      final container = await pumpXpenseApp(tester, TestServices());
      expect(location(container).path, AppRoutes.home);
    });

    testWidgets('a deep link while signed out lands on Welcome', (
      tester,
    ) async {
      final container = await pumpSignedOut(tester);
      await openLink(tester, 'xpense://ask?text=lunch');
      expect(location(container).path, OnboardingRoutes.welcome);
    });

    testWidgets('signing out from anywhere returns to Welcome', (tester) async {
      usePhone(tester);
      final services = TestServices();
      final container = await pumpXpenseApp(tester, services);
      await services.auth.signOut();
      await tester.pumpAndSettle();
      expect(location(container).path, OnboardingRoutes.welcome);
    });
  });

  group('Create account (screen 2)', () {
    testWidgets('flag on: three methods of equal weight, Apple first', (
      tester,
    ) async {
      final container = await openCreateAccount(tester, appleOn());

      expect(location(container).path, OnboardingRoutes.createAccount);
      expect(find.text('CREATE ACCOUNT'), findsOneWidget);
      expect(find.bySemanticsLabel('Step 1 of 4'), findsOneWidget);
      final buttons = [
        for (final label in [
          'Continue with Apple',
          'Continue with Google',
          'Continue with email',
        ])
          find.ancestor(of: find.text(label), matching: find.byType(XpButton)),
      ];
      // Equal width and the same minimum height. (The test font is wider
      // than Geist, so a long label may wrap here and not on a phone.)
      final widths = buttons.map((b) => tester.getSize(b).width).toSet();
      expect(widths, hasLength(1), reason: 'equal width');
      final kinds = buttons.map((b) => tester.widget<XpButton>(b).kind).toSet();
      expect(kinds, {XpButtonKind.secondary}, reason: 'equal style');
      final tops = buttons.map((b) => tester.getTopLeft(b).dy).toList();
      expect(tops, orderedEquals([...tops]..sort()), reason: 'Apple first');
      expect(
        find.textContaining('Private by default.', findRichText: true),
        findsOneWidget,
      );
    });

    testWidgets('flag off (the default): no Apple; Google and email', (
      tester,
    ) async {
      final services = TestServices(signedIn: false);
      expect(services.flags.current.appleSignInEnabled, isFalse);
      await openCreateAccount(tester, services);

      expect(find.text('Continue with Apple'), findsNothing);
      final buttons = [
        for (final label in ['Continue with Google', 'Continue with email'])
          find.ancestor(of: find.text(label), matching: find.byType(XpButton)),
      ];
      final widths = buttons.map((b) => tester.getSize(b).width).toSet();
      expect(widths, hasLength(1), reason: 'equal width');
      final kinds = buttons.map((b) => tester.widget<XpButton>(b).kind).toSet();
      expect(kinds, {XpButtonKind.secondary}, reason: 'equal style');
      // Google takes Apple's place: 32 pt under the paragraph, not 32 + 64.
      final paragraph = find.text(
        'Each of you signs in on your own phone. Your partner joins the same '
        'household later with an invite.',
      );
      expect(
        tester.getTopLeft(buttons.first).dy -
            tester.getBottomLeft(paragraph).dy,
        XpSpace.s32,
      );

      await tapLabel(tester, 'Continue with Google');
      expect(services.auth.calls, ['google']);
    });

    testWidgets('turning the flag on in the console shows Apple live', (
      tester,
    ) async {
      final services = TestServices(signedIn: false);
      final container = await openCreateAccount(tester, services);
      expect(find.text('Continue with Apple'), findsNothing);

      services.flags.set(const FeatureFlags(appleSignInEnabled: true));
      await tester.pumpAndSettle();
      expect(find.text('Continue with Apple'), findsOneWidget);
      await tapLabel(tester, 'Continue with Apple');
      expect(services.auth.calls, ['apple']);
      expect(location(container).path, OnboardingRoutes.tryIt);

      // And off again hides it on the next visit.
      services.flags.set(FeatureFlags.defaults);
      await services.auth.signOut();
      await tester.pumpAndSettle();
      await tapLabel(tester, 'Get started');
      expect(find.text('Continue with Apple'), findsNothing);
    });

    testWidgets('Terms and Privacy Policy links open their pages', (
      tester,
    ) async {
      final container = await openCreateAccount(tester);

      await tester.tapOnText(find.textRange.ofSubstring('Terms'));
      await tester.pumpAndSettle();
      expect(location(container).path, OnboardingRoutes.terms);
      expect(find.text('TERMS'), findsOneWidget);

      await tester.tap(find.bySemanticsLabel('Back'));
      await tester.pumpAndSettle();
      await tester.tapOnText(find.textRange.ofSubstring('Privacy Policy'));
      await tester.pumpAndSettle();
      expect(location(container).path, OnboardingRoutes.privacy);
      expect(find.text('PRIVACY POLICY'), findsOneWidget);
    });

    testWidgets('Apple signs in and the gate moves on to Try it', (
      tester,
    ) async {
      final services = appleOn();
      final container = await openCreateAccount(tester, services);

      await tapLabel(tester, 'Continue with Apple');

      expect(services.auth.calls, ['apple']);
      expect(location(container).path, OnboardingRoutes.tryIt);
      expect(find.text('TRY IT'), findsOneWidget);
    });

    testWidgets('while signing in: a spinner, every button disabled', (
      tester,
    ) async {
      final services = appleOn();
      final container = await openCreateAccount(tester, services);
      services.auth.hold = Completer<void>();

      await tester.tap(find.text('Continue with Google'));
      await tester.pump();

      expect(find.bySemanticsLabel('Signing in…'), findsOneWidget);
      for (final label in [
        'Continue with Apple',
        'Continue with Google',
        'Continue with email',
      ]) {
        final button = tester.widget<XpButton>(
          find.ancestor(of: find.text(label), matching: find.byType(XpButton)),
        );
        expect(button.onPressed, isNull, reason: label);
      }
      // A second tap does not start a second sign-in.
      await tester.tap(find.text('Continue with Apple'));
      await tester.pump();
      expect(services.auth.calls, ['google']);

      services.auth.hold!.complete();
      await tester.pumpAndSettle();
      expect(location(container).path, OnboardingRoutes.tryIt);
    });

    testWidgets('closing the Google sheet shows nothing', (tester) async {
      final services = TestServices(signedIn: false);
      final container = await openCreateAccount(tester, services);
      services.auth.nextFailure = const AuthCancelled();

      await tapLabel(tester, 'Continue with Google');

      expect(location(container).path, OnboardingRoutes.createAccount);
      expect(find.byType(OfflineBanner), findsNothing);
      expect(find.text("Couldn't sign in. Try again."), findsNothing);
    });

    testWidgets('a failure shows inline under the buttons', (tester) async {
      final services = TestServices(signedIn: false);
      await openCreateAccount(tester, services);

      for (final (failure, message) in [
        (
          const AuthMethodUnavailable(),
          "This sign-in method isn't available yet. Use another one.",
        ),
        (
          const AuthTooManyAttempts(),
          'Too many attempts. Wait a few minutes, then try again.',
        ),
        (
          const AuthOtherMethod(),
          'This email already has an account that uses another sign-in '
              'method. Use that one.',
        ),
        (const AuthUnknown('x'), "Couldn't sign in. Try again."),
      ]) {
        services.auth.nextFailure = failure;
        await tapLabel(tester, 'Continue with Google');
        expect(find.text(message), findsOneWidget, reason: failure.code);
      }
    });

    testWidgets('offline: a banner with Try again, which retries', (
      tester,
    ) async {
      final services = TestServices(signedIn: false);
      final container = await openCreateAccount(tester, services);
      services.auth.nextFailure = const AuthOffline();

      await tapLabel(tester, 'Continue with Google');

      expect(find.byType(OfflineBanner), findsOneWidget);
      expect(
        find.text("You're offline. Signing in needs a connection."),
        findsOneWidget,
      );
      await tapLabel(tester, 'Try again');
      expect(services.auth.calls, ['google', 'google']);
      expect(location(container).path, OnboardingRoutes.tryIt);
    });

    testWidgets('the invite path signs in, then opens the join screen', (
      tester,
    ) async {
      final container = await pumpSignedOut(tester);
      await tapLabel(tester, 'I have an invite from my partner');
      expect(
        find.text(
          'Each of you signs in on your own phone. Sign in first, then enter '
          'the invite code your partner shared.',
        ),
        findsOneWidget,
      );

      await tapLabel(tester, 'Continue with Google');
      expect(location(container).path, AppRoutes.join);
    });

    testWidgets('an invite link keeps its code through sign-in', (
      tester,
    ) async {
      final container = await pumpSignedOut(tester);
      await openLink(tester, 'xpense://join?code=ABCD-2345-XY');
      expect(location(container).toString(), '/welcome?code=ABCD2345XY');

      await tapLabel(tester, 'Get started');
      await tapLabel(tester, 'Continue with Google');

      expect(location(container).path, AppRoutes.join);
      expect(
        location(container).queryParameters[AppRoutes.codeParam],
        'ABCD2345XY',
      );
    });
  });

  group('Email form', () {
    testWidgets('creates an account and moves on to Try it', (tester) async {
      final services = TestServices(signedIn: false);
      final container = await openEmail(tester, services);
      expect(find.text('Your email and a password'), findsOneWidget);

      await tester.enterText(field('Email'), 'ada@example.com');
      await tester.enterText(field('Password'), 'secret1');
      await tapLabel(tester, 'Create account');

      expect(services.auth.accounts, {'ada@example.com': 'secret1'});
      expect(location(container).path, OnboardingRoutes.tryIt);
    });

    testWidgets('the password is hidden and autofill knows the fields', (
      tester,
    ) async {
      await openEmail(tester);
      expect(
        tester.widget<EditableText>(field('Password')).obscureText,
        isTrue,
      );
      expect(autofill(tester, 'Password'), [AutofillHints.newPassword]);
      expect(autofill(tester, 'Email'), [AutofillHints.email]);
    });

    testWidgets('empty and malformed fields are named under the field', (
      tester,
    ) async {
      final services = TestServices(signedIn: false);
      await openEmail(tester, services);

      await tapLabel(tester, 'Create account');
      expect(find.text('Enter your email.'), findsOneWidget);
      expect(find.text('Enter your password.'), findsOneWidget);

      await tester.enterText(field('Email'), 'ada');
      await tester.enterText(field('Password'), '123');
      await tapLabel(tester, 'Create account');
      expect(
        find.text('Enter an email like name@example.com.'),
        findsOneWidget,
      );
      expect(find.text('Use at least 6 characters.'), findsOneWidget);
      expect(services.auth.calls, isEmpty, reason: 'nothing was sent');

      // Editing a field clears its message.
      await tester.enterText(field('Email'), 'ada@example.com');
      await tester.pump();
      expect(find.text('Enter an email like name@example.com.'), findsNothing);
      expect(find.text('Use at least 6 characters.'), findsOneWidget);
    });

    testWidgets('an email in use is named under the email field', (
      tester,
    ) async {
      final services = TestServices(signedIn: false);
      services.auth.accounts['ada@example.com'] = 'secret1';
      await openEmail(tester, services);

      await tester.enterText(field('Email'), 'ada@example.com');
      await tester.enterText(field('Password'), 'another1');
      await tapLabel(tester, 'Create account');

      expect(
        find.text(
          "There's already an account with this email. Sign in instead.",
        ),
        findsOneWidget,
      );
    });

    testWidgets('signs in to an existing account; a wrong password says so', (
      tester,
    ) async {
      final services = TestServices(signedIn: false);
      services.auth.accounts['ada@example.com'] = 'secret1';
      final container = await openEmail(tester, services);

      await tapLabel(tester, 'I already have an account');
      expect(find.text('SIGN IN'), findsOneWidget);
      expect(find.text('Welcome back'), findsOneWidget);
      expect(autofill(tester, 'Password'), [AutofillHints.password]);

      await tester.enterText(field('Email'), 'ada@example.com');
      await tester.enterText(field('Password'), 'wrong!');
      await tapLabel(tester, 'Sign in');
      expect(find.text("That email and password don't match."), findsOneWidget);

      await tester.enterText(field('Password'), 'secret1');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(location(container).path, OnboardingRoutes.tryIt);
    });

    testWidgets('forgot password sends a reset and says so', (tester) async {
      final services = TestServices(signedIn: false);
      await openEmail(tester, services);
      await tapLabel(tester, 'I already have an account');

      await tester.enterText(field('Email'), 'ada@example.com');
      services.auth.hold = Completer<void>();
      await tester.tap(find.text('Forgot password?'));
      await tester.pump();
      // Sending a reset locks the form but is not signing in.
      expect(find.text('Signing in…'), findsNothing);
      final signIn = tester.widget<XpButton>(
        find.ancestor(
          of: find.text('Sign in'),
          matching: find.byType(XpButton),
        ),
      );
      expect(signIn.onPressed, isNull);
      services.auth.hold!.complete();
      await tester.pumpAndSettle();

      expect(services.auth.resets, ['ada@example.com']);
      expect(
        find.text(
          "If there's an account for ada@example.com, a link to reset the "
          'password is on its way.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('while creating: Signing in…, fields and buttons locked', (
      tester,
    ) async {
      final services = TestServices(signedIn: false);
      final container = await openEmail(tester, services);
      services.auth.hold = Completer<void>();

      await tester.enterText(field('Email'), 'ada@example.com');
      await tester.enterText(field('Password'), 'secret1');
      await tester.tap(find.text('Create account'));
      await tester.pump();

      expect(find.text('Signing in…'), findsOneWidget);
      final primary = tester.widget<XpButton>(
        find.ancestor(
          of: find.text('Signing in…'),
          matching: find.byType(XpButton),
        ),
      );
      expect(primary.onPressed, isNull);
      expect(
        tester.widget<XpTextField>(find.byType(XpTextField).first).enabled,
        isFalse,
      );

      services.auth.hold!.complete();
      await tester.pumpAndSettle();
      expect(location(container).path, OnboardingRoutes.tryIt);
    });

    testWidgets('offline: banner; Try again sends the form again', (
      tester,
    ) async {
      final services = TestServices(signedIn: false);
      final container = await openEmail(tester, services);
      services.auth.nextFailure = const AuthOffline();

      await tester.enterText(field('Email'), 'ada@example.com');
      await tester.enterText(field('Password'), 'secret1');
      await tapLabel(tester, 'Create account');
      expect(find.byType(OfflineBanner), findsOneWidget);

      await tapLabel(tester, 'Try again');
      expect(location(container).path, OnboardingRoutes.tryIt);
    });

    testWidgets('offline reset: Try again resends the reset, not sign-in', (
      tester,
    ) async {
      final services = TestServices(signedIn: false);
      final container = await openEmail(tester, services);
      await tapLabel(tester, 'I already have an account');
      services.auth.nextFailure = const AuthOffline();

      await tester.enterText(field('Email'), 'ada@example.com');
      await tapLabel(tester, 'Forgot password?');
      expect(find.byType(OfflineBanner), findsOneWidget);
      expect(services.auth.resets, isEmpty);

      await tapLabel(tester, 'Try again');

      expect(services.auth.calls, ['sendPasswordReset', 'sendPasswordReset']);
      expect(services.auth.resets, ['ada@example.com']);
      expect(find.text('Enter your password.'), findsNothing);
      expect(find.byType(OfflineBanner), findsNothing);
      expect(
        find.text(
          "If there's an account for ada@example.com, a link to reset the "
          'password is on its way.',
        ),
        findsOneWidget,
      );
      expect(location(container).path, OnboardingRoutes.email);
    });

    testWidgets('a failed sign-in is retried as a sign-in after a reset', (
      tester,
    ) async {
      final services = TestServices(signedIn: false);
      services.auth.accounts['ada@example.com'] = 'secret1';
      final container = await openEmail(tester, services);
      await tapLabel(tester, 'I already have an account');
      await tester.enterText(field('Email'), 'ada@example.com');
      await tapLabel(tester, 'Forgot password?');

      services.auth.nextFailure = const AuthOffline();
      await tester.enterText(field('Password'), 'secret1');
      await tapLabel(tester, 'Sign in');
      expect(find.byType(OfflineBanner), findsOneWidget);

      await tapLabel(tester, 'Try again');
      expect(services.auth.calls.last, 'signInWithEmail');
      expect(location(container).path, OnboardingRoutes.tryIt);
    });
  });

  group('Try it (screen 5)', () {
    Future<(ProviderContainer, TestServices)> openTryIt(
      WidgetTester tester,
    ) async {
      final services = TestServices(signedIn: false);
      final container = await openCreateAccount(tester, services);
      await tapLabel(tester, 'Continue with Google');
      expect(location(container).path, OnboardingRoutes.tryIt);
      return (container, services);
    }

    testWidgets('microphone pre-prompt, examples, Type instead, Skip', (
      tester,
    ) async {
      await openTryIt(tester);

      expect(find.bySemanticsLabel('Step 4 of 4'), findsOneWidget);
      expect(find.text('Tell me your last purchase'), findsOneWidget);
      expect(
        find.textContaining('The microphone and speech recognition'),
        findsOneWidget,
      );
      expect(find.text('Things you can say'), findsOneWidget);
      expect(find.text('“42.80 at Costco for groceries”'), findsOneWidget);
      expect(find.text('TWO AT ONCE'), findsOneWidget);
      expect(find.text('Type instead'), findsOneWidget);
      expect(find.text('Skip for now'), findsOneWidget);
      expect(find.byType(CaptureDock), findsOneWidget);
      // Nothing to go back to right after signing in.
      expect(find.bySemanticsLabel('Back'), findsNothing);
    });

    testWidgets('Skip for now goes Home', (tester) async {
      final (container, _) = await openTryIt(tester);
      await tapLabel(tester, 'Skip for now');
      expect(location(container).path, AppRoutes.home);
    });

    testWidgets('typed: the message shows, then Go to Home', (tester) async {
      final (container, _) = await openTryIt(tester);

      await tapLabel(tester, 'Type instead');
      await tester.enterText(find.byType(EditableText), 'lunch 12000 IQD');
      await tester.testTextInput.receiveAction(TextInputAction.send);
      await tester.pumpAndSettle();

      expect(find.text('“lunch 12000 IQD”'), findsOneWidget);
      expect(
        find.text('Got it. In this preview nothing is sorted or saved yet.'),
        findsOneWidget,
      );
      expect(find.text('Skip for now'), findsNothing);
      await tapLabel(tester, 'Go to Home');
      expect(location(container).path, AppRoutes.home);
    });

    testWidgets('an example goes into the text field, unsent', (tester) async {
      await openTryIt(tester);
      await tapLabel(tester, '“Gave Alex 300”');

      final text = tester.widget<EditableText>(find.byType(EditableText));
      expect(text.controller.text, 'Gave Alex 300');
      expect(find.text('Go to Home'), findsNothing);
    });

    testWidgets('no recogniser: the orange button falls back to typing', (
      tester,
    ) async {
      await openTryIt(tester);

      await tester.tap(find.bySemanticsLabel('Talk'));
      await tester.pumpAndSettle();

      expect(
        find.text("Voice isn't available on this phone yet. Type instead."),
        findsOneWidget,
      );
      expect(find.byType(EditableText), findsOneWidget);
    });

    testWidgets('declined permission says how to turn it on', (tester) async {
      final (_, services) = await openTryIt(tester);
      services.speech.script = [const SpeechFailed(ServicePermissionDenied())];

      await tester.tap(find.bySemanticsLabel('Talk'));
      await tester.pumpAndSettle();

      expect(
        find.text(
          'Microphone access is off. Turn it on in Settings, or type instead.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('spoken: the transcript is handed over like typed text', (
      tester,
    ) async {
      final (_, services) = await openTryIt(tester);
      services.speech.script = [
        const SpeechLevel(0.4),
        const SpeechPartial('Gave Alex'),
        const SpeechFinal('Gave Alex 300'),
      ];

      await tester.tap(find.bySemanticsLabel('Talk'));
      await tester.pumpAndSettle();

      expect(find.text('“Gave Alex 300”'), findsOneWidget);
      expect(find.text('Go to Home'), findsOneWidget);
    });
  });

  group('every onboarding screen', () {
    for (final brightness in Brightness.values) {
      testWidgets('builds at 2x text in ${brightness.name} without overflow', (
        tester,
      ) async {
        tester.platformDispatcher
          ..textScaleFactorTestValue = 2
          ..platformBrightnessTestValue = brightness;
        addTearDown(tester.platformDispatcher.clearAllTestValues);
        // The fullest layout: all three sign-in methods.
        final services = appleOn();
        final container = await pumpSignedOut(tester, services);
        expect(find.text('Get started', skipOffstage: false), findsOneWidget);
        await tapLabel(tester, 'Get started');
        expect(
          find.text('Continue with Apple', skipOffstage: false),
          findsOneWidget,
        );
        await tapLabel(tester, 'Continue with email');
        expect(find.byType(XpTextField, skipOffstage: false), findsNWidgets(2));
        await tester.tap(find.bySemanticsLabel('Back'));
        await tester.pumpAndSettle();

        await tapLabel(tester, 'Continue with Apple');
        expect(location(container).path, OnboardingRoutes.tryIt);
        expect(find.byType(CaptureDock), findsOneWidget);
        expect(services.auth.currentUser, FakeAuthRepository.providerUser);
      });
    }
  });
}
