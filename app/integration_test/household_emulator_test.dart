// Two phones, one household (WP-12, BACKLOG S1.4, S1.5), against the
// Firebase emulator suite and a local server, under the fake project
// `demo-xpense`. Not run by CI: it needs two simulators, the emulators and
// the server.
//
//   cd firebase && firebase emulators:start --project demo-xpense \
//     --only auth,firestore
//   cd server && FIREBASE_AUTH_EMULATOR_HOST=127.0.0.1:9099 \
//     FIRESTORE_EMULATOR_HOST=127.0.0.1:8280 XPENSE_APP_CHECK=emulator \
//     dart run bin/server.dart
//
// Phone 1 creates the household, prints `XPENSE_INVITE_CODE=…` and waits
// for the partner; phone 2 joins with that code:
//
//   cd app && flutter test integration_test/household_emulator_test.dart \
//     -d <phone 1> --dart-define=XPENSE_ENV=emulators \
//     --dart-define=XPENSE_HOUSEHOLD_ROLE=owner
//   cd app && flutter test integration_test/household_emulator_test.dart \
//     -d <phone 2> --dart-define=XPENSE_ENV=emulators \
//     --dart-define=XPENSE_HOUSEHOLD_ROLE=partner \
//     --dart-define=XPENSE_INVITE_CODE=<the code>
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
import 'package:xpense_app/data/auth_repository.dart';
import 'package:xpense_app/data/household_repository.dart';
import 'package:xpense_app/features/onboarding/onboarding_gate.dart';

import 'onboarding_emulator_test.dart' show pause, pumpUntil, tapText, typeInto;

const String _role = String.fromEnvironment('XPENSE_HOUSEHOLD_ROLE');
const String _inviteCode = String.fromEnvironment('XPENSE_INVITE_CODE');

final RegExp _shownCode = RegExp(r'^[0-9A-Z]{5}-[0-9A-Z]{5}$');

/// Boots the app as configured, signed out, and returns its container.
Future<ProviderContainer> startSignedOut(WidgetTester tester) async {
  expect(
    AppEnvironment.compiled,
    AppEnvironment.emulators,
    reason: 'run with --dart-define=XPENSE_ENV=emulators',
  );
  final app = await bootstrap(environment: AppEnvironment.compiled);
  final container = ProviderContainer(overrides: app.overrides);
  addTearDown(container.dispose);
  // A session left by an earlier run would skip onboarding.
  await container.read(authRepositoryProvider).signOut();
  await tester.pumpWidget(
    UncontrolledProviderScope(container: container, child: const XpenseApp()),
  );
  await tester.pumpAndSettle();
  return container;
}

/// Creates an email account from the Create account screen.
Future<void> signUp(WidgetTester tester, String who) async {
  await tapText(tester, 'Continue with email');
  final email = '$who-${DateTime.now().millisecondsSinceEpoch}@example.com';
  await typeInto(tester, 'Email', email);
  await typeInto(tester, 'Password', 'secret12');
  await pause(tester, 4);
  await tapText(tester, 'Create account');
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('owner: create the household and wait for the partner', (
    tester,
  ) async {
    final container = await startSignedOut(tester);
    Uri location() => container.read(routerProvider).state.uri;
    final households = container.read(householdRepositoryProvider);

    await pause(tester);
    await tapText(tester, 'Get started');
    await signUp(tester, 'owner');
    await pumpUntil(
      tester,
      () => location().path == AppRoutes.householdSetup,
      'household setup after creating the account',
    );

    // Screen 3: name, display name, USD preselected.
    await pause(tester, 8);
    await typeInto(tester, 'Household name', 'Our home');
    await typeInto(tester, 'Your name', 'Alex');
    await pause(tester, 6);
    await tapText(tester, 'Continue');

    // The founding batch passed the rules, and the server made a code.
    final code = find.byWidgetPredicate(
      (w) => w is Text && _shownCode.hasMatch(w.data ?? ''),
    );
    await pumpUntil(tester, () => code.evaluate().isNotEmpty, 'invite code');
    final shown = tester.widget<Text>(code).data!;
    final membership = households.current;
    expect(membership, isA<InHousehold>());
    expect((membership as InHousehold).household.memberCount, 1);
    expect(membership.household.name, 'Our home');
    // Read by the partner's run (see the header).
    debugPrint('XPENSE_INVITE_CODE=${shown.replaceAll('-', '')}');

    // The partner joins on the other phone; the code gives way at once.
    await pumpUntil(
      tester,
      () => find.text('Your partner has joined.').evaluate().isNotEmpty,
      'the partner to join',
      seconds: 600,
    );
    expect((households.current as InHousehold).household.memberCount, 2);
    await pause(tester, 20);
    await tapText(tester, 'Continue');
    expect(location().path, OnboardingRoutes.tryIt);
    await pause(tester);
  }, skip: _role != 'owner');

  testWidgets('partner: join with the code', (tester) async {
    expect(_inviteCode, isNotEmpty, reason: 'pass XPENSE_INVITE_CODE');
    final container = await startSignedOut(tester);
    Uri location() => container.read(routerProvider).state.uri;

    await pause(tester);
    await tapText(tester, 'I have an invite from my partner');
    await signUp(tester, 'partner');
    await pumpUntil(
      tester,
      () => location().path == AppRoutes.join,
      'the join screen after creating the account',
    );

    await pause(tester, 8);
    await typeInto(tester, 'Invite code', _inviteCode);
    await typeInto(tester, 'Your name', 'Sam');
    await pause(tester, 6);
    await tapText(tester, 'Join household');
    await pumpUntil(
      tester,
      () => find.text('Welcome to Our home').evaluate().isNotEmpty,
      'the welcome after joining',
    );
    await pumpUntil(
      tester,
      () => container.read(householdRepositoryProvider).current is InHousehold,
      'membership',
    );
    final household =
        (container.read(householdRepositoryProvider).current as InHousehold)
            .household;
    expect(household.memberCount, 2);
    expect(household.myDisplayName, 'Sam');

    await pause(tester, 20);
    await tapText(tester, 'Continue');
    expect(location().path, OnboardingRoutes.tryIt);
    await pause(tester);
  }, skip: _role != 'partner');
}
