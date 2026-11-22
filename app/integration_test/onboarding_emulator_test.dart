// Onboarding on a simulator against the Firebase Auth and Firestore
// emulators (WP-11, BACKLOG S1.3; household setup since WP-12). Not run by
// CI: it needs a simulator and the emulators. The `emulators` environment
// uses the fake project `demo-xpense` and needs no config file.
//
//   cd firebase && firebase emulators:start --project demo-xpense \
//     --only auth,firestore
//   cd app && flutter test integration_test/onboarding_emulator_test.dart \
//     -d <simulator> --dart-define=XPENSE_ENV=emulators
//
// Without the local server the invite code is not made; the test then
// leaves household setup with "Invite later".
//
// Add --dart-define=XPENSE_DEMO_PACE=true to slow it down for the PR demo
// recording (DELEGATION rule 11).
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:xpense_app/app.dart';
import 'package:xpense_app/bootstrap.dart';
import 'package:xpense_app/core/routing/routing.dart';
import 'package:xpense_app/core/ui/ui.dart';
import 'package:xpense_app/data/auth_repository.dart';
import 'package:xpense_app/features/onboarding/onboarding_gate.dart';

const bool _demoPace = bool.fromEnvironment('XPENSE_DEMO_PACE');

/// Lets the demo recording show each step; instant otherwise.
Future<void> pause(WidgetTester tester, [int tenths = 10]) async {
  if (!_demoPace) return;
  for (var i = 0; i < tenths; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> tapText(WidgetTester tester, String text) async {
  final target = find.text(text, skipOffstage: false);
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tester.tap(target);
  await tester.pumpAndSettle();
}

Finder field(String label) => find.descendant(
  of: find.ancestor(of: find.text(label), matching: find.byType(XpTextField)),
  matching: find.byType(EditableText),
);

/// Types [text] into the field labelled [label], a few letters at a time
/// when pacing, so the recording shows typing.
Future<void> typeInto(WidgetTester tester, String label, String text) async {
  final target = field(label);
  await tester.tap(target);
  if (!_demoPace) {
    await tester.enterText(target, text);
  } else {
    for (var end = 3; end < text.length + 3; end += 3) {
      await tester.enterText(
        target,
        text.substring(0, end.clamp(0, text.length)),
      );
      await tester.pump(const Duration(milliseconds: 60));
    }
  }
  await tester.pumpAndSettle();
}

/// Pumps until [done] holds: sign-in is real network I/O, which
/// `pumpAndSettle` does not wait for. On timeout, fails with the text on
/// screen, so an inline error shows in the log.
Future<void> pumpUntil(
  WidgetTester tester,
  bool Function() done,
  String what, {
  int seconds = 15,
}) async {
  for (var i = 0; i < seconds * 10 && !done(); i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  if (done()) {
    await tester.pumpAndSettle();
    return;
  }
  final texts = tester
      .widgetList<Text>(find.byType(Text))
      .map((t) => t.data ?? t.textSpan?.toPlainText())
      .nonNulls
      .join(' | ');
  fail('Timed out waiting for $what. On screen: $texts');
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('create an email account, try a first capture, sign back in', (
    tester,
  ) async {
    expect(
      AppEnvironment.compiled,
      AppEnvironment.emulators,
      reason: 'run with --dart-define=XPENSE_ENV=emulators',
    );
    final app = await bootstrap(environment: AppEnvironment.compiled);
    final container = ProviderContainer(overrides: app.overrides);
    addTearDown(container.dispose);
    final auth = container.read(authRepositoryProvider);
    // A session left by an earlier run would skip onboarding.
    await auth.signOut();

    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const XpenseApp()),
    );
    await tester.pumpAndSettle();
    Uri location() => container.read(routerProvider).state.uri;

    // Welcome.
    expect(location().path, OnboardingRoutes.welcome);
    await pause(tester, 25);
    await tapText(tester, 'Get started');

    // Create account. Apple shows only once Remote Config turns
    // apple_sign_in_enabled on (D-39), so this checks the other two.
    expect(find.text('Continue with Google'), findsOneWidget);
    expect(find.text('Continue with email'), findsOneWidget);
    await pause(tester, 20);
    await tapText(tester, 'Continue with email');

    // The email form, against the emulator.
    final email = 'demo-${DateTime.now().millisecondsSinceEpoch}@example.com';
    await typeInto(tester, 'Email', email);
    await typeInto(tester, 'Password', 'secret12');
    await pause(tester, 6);
    await tapText(tester, 'Create account');
    await pumpUntil(
      tester,
      () => location().path == AppRoutes.householdSetup,
      'household setup after creating the account',
    );
    expect(auth.currentUser?.email, email);

    // Household setup (WP-12), then on to Try it.
    await typeInto(tester, 'Household name', 'Our home');
    await typeInto(tester, 'Your name', 'Ada');
    await tapText(tester, 'Continue');
    final later = find.text('Invite later');
    await pumpUntil(tester, () => later.evaluate().isNotEmpty, 'the invite');
    await tapText(tester, 'Invite later');
    expect(location().path, OnboardingRoutes.tryIt);
    await pause(tester, 20);
    await tapText(tester, 'Type instead');
    final dock = find.byType(EditableText);
    await tester.tap(dock);
    if (_demoPace) {
      const message = '42.80 at Costco for groceries';
      for (var end = 4; end < message.length + 4; end += 4) {
        await tester.enterText(
          dock,
          message.substring(0, end.clamp(0, message.length)),
        );
        await tester.pump(const Duration(milliseconds: 60));
      }
    } else {
      await tester.enterText(dock, '42.80 at Costco for groceries');
    }
    await tester.testTextInput.receiveAction(TextInputAction.send);
    await tester.pumpAndSettle();
    expect(find.text('“42.80 at Costco for groceries”'), findsOneWidget);
    await pause(tester, 20);
    await tapText(tester, 'Go to Home');
    expect(location().path, AppRoutes.home);
    await pause(tester);

    if (_demoPace) return;

    // Sign out, then back in: a wrong password is named inline.
    await auth.signOut();
    await pumpUntil(
      tester,
      () => location().path == OnboardingRoutes.welcome,
      'Welcome after signing out',
    );
    await tapText(tester, 'Get started');
    await tapText(tester, 'Continue with email');
    await tapText(tester, 'I already have an account');
    await typeInto(tester, 'Email', email);
    await typeInto(tester, 'Password', 'wrong-one');
    await tapText(tester, 'Sign in');
    final wrong = find.text("That email and password don't match.");
    await pumpUntil(
      tester,
      () => wrong.evaluate().isNotEmpty,
      'wrong password',
    );

    await typeInto(tester, 'Password', 'secret12');
    await tapText(tester, 'Sign in');
    // A member signing back in goes Home.
    await pumpUntil(
      tester,
      () => location().path == AppRoutes.home,
      'Home after signing in',
    );
    expect(auth.currentUser?.email, email);

    // Creating the same account again is refused under the email field.
    await auth.signOut();
    await pumpUntil(
      tester,
      () => location().path == OnboardingRoutes.welcome,
      'Welcome after signing out',
    );
    await tapText(tester, 'Get started');
    await tapText(tester, 'Continue with email');
    await typeInto(tester, 'Email', email);
    await typeInto(tester, 'Password', 'secret12');
    await tapText(tester, 'Create account');
    final inUse = find.text(
      "There's already an account with this email. Sign in instead.",
    );
    await pumpUntil(tester, () => inUse.evaluate().isNotEmpty, 'email in use');
    await auth.signOut();
  });
}
