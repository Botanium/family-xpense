// Ask end to end (WP-34, stories S3.8 to S3.11): three typed messages, one
// per capture path, against the Firebase emulator suite and a local server
// running the agent and the Decisions proxy, under the fake project
// `demo-xpense`. Not run by CI: it needs a simulator, the emulators, the
// server and the Gemini key.
//
//   cd firebase && firebase emulators:start --project demo-xpense \
//     --only auth,firestore
//   cd server && FIREBASE_AUTH_EMULATOR_HOST=127.0.0.1:9099 \
//     FIRESTORE_EMULATOR_HOST=127.0.0.1:8280 XPENSE_APP_CHECK=emulator \
//     tool/with_gemini_key.sh genkit start -- dart run bin/server.dart
//   cd app && flutter test integration_test/ask_emulator_test.dart \
//     -d <simulator> --dart-define=XPENSE_ENV=emulators
//
// Each run makes a new member in the Auth emulator (emulator admin API,
// never a real project), who creates a household and a "Checking" account
// through the app's own repositories, so the cards use ids the phone read
// from Firestore, not the server's demo household. It teaches one rule (as
// a corrected card would) so the first message resolves on the phone, and
// saves that card through the write path. It prints `XPENSE_MARK <name>` before
// each step, so a script watching the output can take simulator
// screenshots, and `XPENSE_ROUTE` and `XPENSE_TRACE` lines for the PR.
// Add --dart-define=XPENSE_DEMO_PACE=true to slow it down for the demo
// recording (DELEGATION rule 11).
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:xpense_app/app.dart';
import 'package:xpense_app/bootstrap.dart';
import 'package:xpense_app/core/routing/routing.dart';
import 'package:xpense_app/data/accounts_repository.dart';
import 'package:xpense_app/data/auth_repository.dart';
import 'package:xpense_app/data/household_repository.dart';
import 'package:xpense_app/data/rules_repository.dart';
import 'package:xpense_app/features/ask/ask_controller.dart';
import 'package:xpense_app/features/ask/ask_state.dart';
import 'package:xpense_shared/xpense_shared.dart';

import 'onboarding_emulator_test.dart' show pause, pumpUntil;

const bool _demoPace = bool.fromEnvironment('XPENSE_DEMO_PACE');

/// A throwaway emulator password for this run's member.
const String _password = 'emulator-only-1';

/// Creates the Auth emulator account [uid]. The Auth emulator accepts
/// `Bearer owner` for its admin API.
Future<void> _createEmulatorUser(String uid, String email) async {
  final client = HttpClient();
  try {
    final request = await client.postUrl(
      Uri.parse(
        'http://$defaultAuthEmulator/identitytoolkit.googleapis.com/v1/'
        'projects/$emulatorProjectId/accounts',
      ),
    );
    request.headers
      ..contentType = ContentType.json
      ..set(HttpHeaders.authorizationHeader, 'Bearer owner');
    request.write(
      jsonEncode({
        'localId': uid,
        'email': email,
        'password': _password,
        'displayName': 'Rana',
      }),
    );
    final response = await request.close();
    await response.drain<void>();
  } finally {
    client.close(force: true);
  }
}

void _mark(String name) => debugPrint('XPENSE_MARK $name');

Future<void> _say(WidgetTester tester, String text) async {
  final dock = find.byType(EditableText);
  await tester.tap(dock);
  if (_demoPace) {
    for (var end = 4; end < text.length + 4; end += 4) {
      await tester.enterText(
        dock,
        text.substring(0, end.clamp(0, text.length)),
      );
      await tester.pump(const Duration(milliseconds: 50));
    }
  } else {
    await tester.enterText(dock, text);
  }
  await tester.pump();
  await tester.testTextInput.receiveAction(TextInputAction.send);
  await tester.pump();
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('three typed messages, one per path', (tester) async {
    expect(
      AppEnvironment.compiled,
      AppEnvironment.emulators,
      reason: 'run with --dart-define=XPENSE_ENV=emulators',
    );
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final uid = 'u_ask_$stamp';
    final email = 'ask$stamp@example.com';
    await _createEmulatorUser(uid, email);
    final app = await bootstrap(environment: AppEnvironment.compiled);
    final container = ProviderContainer(overrides: app.overrides);
    addTearDown(container.dispose);
    final auth = container.read(authRepositoryProvider);
    await auth.signOut();
    final signedIn = await auth.signInWithEmail(
      email: email,
      password: _password,
    );
    expect(auth.currentUser?.uid, uid, reason: '$signedIn');
    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const XpenseApp()),
    );
    // A provider nobody listens to is paused (Riverpod 3), so listen.
    final membership = container.listen(membershipProvider, (_, _) {});
    addTearDown(membership.close);
    await pumpUntil(
      tester,
      () => membership.read().value is NoHousehold,
      'the new member to have no household',
    );

    // A new household and account, as the member would make them (WP-12,
    // WP-13).
    final created = await container
        .read(householdRepositoryProvider)
        .create(name: 'Rana', displayName: 'Rana', baseCurrency: Currency.usd);
    expect(created, isA<Ok<String, HouseholdFailure>>(), reason: '$created');
    await pumpUntil(
      tester,
      () => membership.read().value is InHousehold,
      'the new household',
    );
    final account = await container
        .read(accountsRepositoryProvider)
        .create(
          const AccountDraft(
            name: 'Checking',
            kind: AccountKind.bank,
            currency: Currency.usd,
            scope: AccountScope.personal,
            openingBalanceMinor: 250000,
          ),
        );
    final accountId = switch (account) {
      Ok(:final value) => value,
      Err(:final failure) => fail('account not created: $failure'),
    };
    final hid = (created as Ok<String, HouseholdFailure>).value;
    debugPrint('XPENSE_HOUSEHOLD $hid account $accountId');

    // Path L needs a learned rule: the parser never settles a category from
    // a keyword alone (AI_PIPELINE 2). Teach the one a corrected "Trader
    // Joes" card would (story S3.11), through the Firestore rules store.
    final rules = container.read(rulesRepositoryProvider);
    final lesson = RuleLesson(
      kind: RuleKind.merchant,
      pattern: 'Trader Joes',
      categoryId: 'groceries',
      accountId: accountId,
    );
    await rules.learn(lesson);
    await pumpUntil(
      tester,
      () => rules.current.any((r) => r.pattern == rulePattern('Trader Joes')),
      'the learned rule',
    );
    // The same lesson again updates the rule (the Firestore rules allow
    // the member's own update).
    await rules.learn(lesson);

    container.read(routerProvider).go(AppRoutes.home);
    await tester.pumpAndSettle();
    unawaited(container.read(routerProvider).push<void>(AppRoutes.ask));
    await tester.pumpAndSettle();
    await pause(tester);
    _mark('ask_open');

    AskState state() => container.read(askControllerProvider);
    int surfaces() => state().items.whereType<SurfaceItem>().length;

    Future<void> capture(String name, String text, CapturePath path) async {
      final before = surfaces();
      _mark('${name}_typing');
      await _say(tester, text);
      await pumpUntil(
        tester,
        () => !state().busy && surfaces() > before,
        'a card for "$text"',
        seconds: 90,
      );
      final route = state().lastRoute!;
      debugPrint(
        'XPENSE_ROUTE $name path=${route.path.name} '
        'row=${route.reason.row} reason=${route.reason.code}',
      );
      expect(route.path, path);
      await pause(tester, 20);
      _mark('${name}_done');
    }

    // Saves the newest card through the transaction write path (WP-20)
    // into the emulator.
    Future<void> save(String name) async {
      _mark('${name}_save');
      await tester.ensureVisible(find.text('Save').last);
      await tester.tap(find.text('Save').last);
      await pumpUntil(
        tester,
        () => find.text('Saved.').evaluate().isNotEmpty,
        'the "$name" card to save',
        seconds: 30,
      );
      debugPrint('XPENSE_SAVED $name');
      await pause(tester, 20);
      _mark('${name}_saved');
    }

    await capture(
      'local',
      'Spent 25 dollars at Trader Joes',
      CapturePath.local,
    );
    await save('local');
    await capture(
      'decide',
      'Spent 42.80 dollars at Costco',
      CapturePath.decide,
    );
    await capture(
      'agent',
      'Salary came in, 3200, and I paid rent 1400 from checking',
      CapturePath.agent,
    );
    for (final trace in state().traceIds) {
      debugPrint('XPENSE_TRACE agent $trace');
    }
    _mark('end');
    await pause(tester, 20);
  });
}
