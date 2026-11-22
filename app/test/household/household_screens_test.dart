// Household setup (screen 3) and joining (WP-12, BACKLOG S1.4, S1.5): one
// test per state, through the whole app and router, on the fakes.
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:xpense_app/app.dart';
import 'package:xpense_app/core/routing/routing.dart';
import 'package:xpense_app/core/ui/ui.dart';
import 'package:xpense_app/data/household_repository.dart';
import 'package:xpense_app/data/household_repository_fake.dart';
import 'package:xpense_app/features/household/invite_share.dart';
import 'package:xpense_shared/xpense_shared.dart';

import '../onboarding/onboarding_screens_test.dart'
    show field, location, tapLabel, usePhone;
import '../routing/router_test.dart' show openLink;
import '../support/test_app.dart';
import '../ui/ui_harness.dart' show loadSignalFonts;

/// What the share sheet was handed, in order.
final List<String> shared = [];

/// Pumps the app for someone signed in with [membership] (no household by
/// default), with the share sheet recorded in [shared].
Future<(ProviderContainer, TestServices)> pumpHousehold(
  WidgetTester tester, {
  Membership membership = const NoHousehold(),
}) async {
  usePhone(tester);
  shared.clear();
  final services = TestServices(membership: membership);
  final container = ProviderContainer.test(
    overrides: [
      ...services.overrides,
      shareTextProvider.overrideWithValue((text) async => shared.add(text)),
    ],
    retry: (_, _) => null,
  );
  await tester.pumpWidget(
    UncontrolledProviderScope(container: container, child: const XpenseApp()),
  );
  await tester.pumpAndSettle();
  return (container, services);
}

XpButton button(WidgetTester tester, String label) => tester.widget<XpButton>(
  find.ancestor(
    of: find.text(label, skipOffstage: false),
    matching: find.byType(XpButton),
  ),
);

XpTextField textField(WidgetTester tester, String label) =>
    tester.widget<XpTextField>(
      find.ancestor(
        of: find.text(label, skipOffstage: false),
        matching: find.byType(XpTextField),
      ),
    );

bool chipSelected(WidgetTester tester, String label) => tester
    .widget<XpChip>(
      find.ancestor(of: find.text(label), matching: find.byType(XpChip)),
    )
    .selected;

/// Fills the form and taps Continue.
Future<void> createHousehold(
  WidgetTester tester, {
  String name = 'Our home',
  String displayName = 'Alex',
}) async {
  await tester.enterText(field('Household name'), name);
  await tester.enterText(field('Your name'), displayName);
  await tapLabel(tester, 'Continue');
}

const String code = 'AB3DE-7GH9K';

void main() {
  setUpAll(loadSignalFonts);

  group('Household setup (screen 3)', () {
    testWidgets('signed in without a household, setup opens; USD is chosen', (
      tester,
    ) async {
      final (container, _) = await pumpHousehold(tester);

      expect(location(container).path, AppRoutes.householdSetup);
      expect(find.text('HOUSEHOLD'), findsOneWidget);
      expect(find.bySemanticsLabel('Step 2 of 4'), findsOneWidget);
      expect(find.text('Set up your household'), findsOneWidget);
      expect(find.text('Household name'), findsOneWidget);
      expect(find.text('Your name'), findsOneWidget);
      expect(chipSelected(tester, 'USD'), isTrue);
      expect(chipSelected(tester, 'IQD'), isFalse);
      expect(
        find.text(
          "Household totals and reports add up in this currency. It can't "
          'be changed later.',
        ),
        findsOneWidget,
      );
      expect(find.text('Shared'), findsOneWidget);
      expect(find.text('Joint money, goals'), findsOneWidget);
      expect(find.text('Private'), findsOneWidget);
      expect(find.text('Your own accounts'), findsOneWidget);
      expect(find.text('I have an invite', skipOffstage: false), findsOne);
      // No invite before the household exists, and nothing to go back to.
      expect(find.text('Invite your partner'), findsNothing);
      expect(find.bySemanticsLabel('Back'), findsNothing);
      // The sign-in method's name is offered as the display name.
      expect(
        tester.widget<EditableText>(field('Your name')).controller.text,
        'You',
      );
    });

    testWidgets('the rest of the app stays closed until there is one', (
      tester,
    ) async {
      final (container, _) = await pumpHousehold(tester);
      for (final target in [AppRoutes.accounts, AppRoutes.tryIt, '/ask']) {
        container.read(routerProvider).go(target);
        await tester.pumpAndSettle();
        expect(location(container).path, AppRoutes.householdSetup);
      }
    });

    testWidgets('empty and over-long names are named under their field', (
      tester,
    ) async {
      final (_, services) = await pumpHousehold(tester);
      await tester.enterText(field('Your name'), '   ');
      await tapLabel(tester, 'Continue');

      expect(find.text('Give your household a name.'), findsOneWidget);
      expect(find.text('Add the name your partner will see.'), findsOneWidget);
      expect(services.households.calls, isEmpty);

      await tester.enterText(field('Household name'), 'x' * 41);
      await tester.pump();
      // Editing the field clears its message until the next try.
      expect(find.text('Give your household a name.'), findsNothing);
      await tester.enterText(field('Your name'), 'Alex');
      await tapLabel(tester, 'Continue');
      expect(find.text('Use 40 characters or fewer.'), findsOneWidget);
      expect(services.households.calls, isEmpty);
    });

    testWidgets('while creating: Setting up…, the form locked', (tester) async {
      final (_, services) = await pumpHousehold(tester);
      final hold = services.households.holdNext['create'] = Completer<void>();
      await tester.enterText(field('Household name'), 'Our home');
      await tester.tap(find.text('Continue'));
      await tester.pump();

      expect(find.text('Setting up…'), findsOneWidget);
      expect(button(tester, 'Setting up…').onPressed, isNull);
      expect(textField(tester, 'Household name').enabled, isFalse);
      expect(button(tester, 'I have an invite').onPressed, isNull);

      hold.complete();
      await tester.pumpAndSettle();
      expect(find.text(code), findsOneWidget);
    });

    testWidgets('creates the household in IQD, then shows the invite code', (
      tester,
    ) async {
      final (_, services) = await pumpHousehold(tester);
      await tapLabel(tester, 'IQD');
      expect(chipSelected(tester, 'IQD'), isTrue);
      await createHousehold(tester, name: '  Our home ');

      expect(services.households.lastCreate, (
        name: 'Our home',
        displayName: 'Alex',
        baseCurrency: Currency.iqd,
      ));
      expect(services.households.calls, ['create', 'createInvite']);
      expect(find.text('Invite your partner'), findsOneWidget);
      expect(find.text(code), findsOneWidget);
      expect(
        find.bySemanticsLabel('Invite code A B 3 D E 7 G H 9 K'),
        findsOneWidget,
      );
      expect(
        find.text('Works once, for 7 days. A new code replaces this one.'),
        findsOneWidget,
      );
      // The form is now read-only, as on the artboard.
      expect(textField(tester, 'Household name').enabled, isFalse);
      expect(textField(tester, 'Your name').enabled, isFalse);
      expect(
        tester
            .widget<ChoiceChips<Currency>>(find.byType(ChoiceChips<Currency>))
            .onSelected,
        isNull,
      );
      expect(find.text('Continue', skipOffstage: false), findsOneWidget);
      expect(find.text('Invite later').hitTestable(), findsOneWidget);
      expect(find.text('I have an invite', skipOffstage: false), findsNothing);
    });

    testWidgets('while the code is made: a spinner', (tester) async {
      final (_, services) = await pumpHousehold(tester);
      final hold = services.households.holdNext['createInvite'] =
          Completer<void>();
      await tester.enterText(field('Household name'), 'Our home');
      await tester.tap(find.text('Continue'));
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }

      expect(find.bySemanticsLabel('Making an invite code'), findsOneWidget);
      expect(find.text(code), findsNothing);
      hold.complete();
      await tester.pumpAndSettle();
      expect(find.text(code), findsOneWidget);
    });

    testWidgets('Share hands the code and link to the share sheet', (
      tester,
    ) async {
      await pumpHousehold(tester);
      await createHousehold(tester);
      await tapLabel(tester, 'Share');

      expect(shared, hasLength(1));
      expect(shared.single, contains(code));
      expect(shared.single, contains('xpense://join?code=AB3DE7GH9K'));
      expect(shared.single, contains('works once, for 7 days'));
      // Once shared, "Invite later" no longer applies; Continue stays put.
      expect(find.text('Invite later').hitTestable(), findsNothing);
      // Hidden from VoiceOver too.
      expect(find.semantics.byLabel('Invite later'), findsNothing);
    });

    testWidgets('Continue goes on to Try it, and Back returns to the code', (
      tester,
    ) async {
      final (container, _) = await pumpHousehold(tester);
      await createHousehold(tester);
      await tapLabel(tester, 'Continue');

      expect(location(container).path, AppRoutes.tryIt);
      expect(find.text('TRY IT'), findsOneWidget);
      await tester.tap(find.bySemanticsLabel('Back'));
      await tester.pumpAndSettle();
      expect(location(container).path, AppRoutes.householdSetup);
      expect(find.text(code), findsOneWidget);
    });

    testWidgets('Invite later goes on to Try it too', (tester) async {
      final (container, _) = await pumpHousehold(tester);
      await createHousehold(tester);
      await tapLabel(tester, 'Invite later');
      expect(location(container).path, AppRoutes.tryIt);
    });

    testWidgets('no code: the reason in place of it, and Try again', (
      tester,
    ) async {
      final (_, services) = await pumpHousehold(tester);
      services.households.failNext['createInvite'] = const HouseholdOffline();
      await createHousehold(tester);

      expect(
        find.text("You're offline. Connect to get an invite code."),
        findsOneWidget,
      );
      expect(find.text(code), findsNothing);
      // Moving on without a code is still possible.
      expect(button(tester, 'Continue').onPressed, isNotNull);

      await tapLabel(tester, 'Try again');
      expect(services.households.calls, [
        'create',
        'createInvite',
        'createInvite',
      ]);
      expect(find.text(code), findsOneWidget);
    });

    testWidgets('each invite failure has its words', (tester) async {
      final (_, services) = await pumpHousehold(tester);
      final cases = [
        (
          const HouseholdServiceUnavailable(),
          "Invites aren't available right now. Try again later.",
        ),
        (
          const HouseholdRateLimited(),
          'Too many new codes. Wait an hour, then try again.',
        ),
        (
          const HouseholdNotAllowed(),
          'Your sign-in has expired. Sign out and sign in again.',
        ),
        (const HouseholdUnknown('x'), "Couldn't make an invite code."),
      ];
      services.households.failNext['createInvite'] = cases.first.$1;
      await createHousehold(tester);
      for (final (index, (failure, words)) in cases.indexed) {
        if (index > 0) {
          services.households.failNext['createInvite'] = failure;
          await tapLabel(tester, 'Try again');
        }
        expect(find.text(words), findsOneWidget, reason: failure.code);
        expect(find.text(code), findsNothing);
      }
    });

    testWidgets('creating offline: a banner, and Try again creates', (
      tester,
    ) async {
      final (container, services) = await pumpHousehold(tester);
      services.households.failNext['create'] = const HouseholdOffline();
      await createHousehold(tester);

      expect(find.byType(OfflineBanner), findsOneWidget);
      expect(
        find.text("You're offline. Setting up needs a connection."),
        findsOneWidget,
      );
      expect(textField(tester, 'Household name').enabled, isTrue);

      await tapLabel(tester, 'Try again');
      expect(services.households.calls, ['create', 'create', 'createInvite']);
      expect(find.byType(OfflineBanner), findsNothing);
      expect(find.text(code), findsOneWidget);
      expect(location(container).path, AppRoutes.householdSetup);
    });

    testWidgets('a refused write is named under the form', (tester) async {
      final (_, services) = await pumpHousehold(tester);
      services.households.failNext['create'] = const HouseholdNotAllowed();
      await createHousehold(tester);
      expect(
        find.text('Your sign-in has expired. Sign out and sign in again.'),
        findsOneWidget,
      );
      expect(find.text('Invite your partner'), findsNothing);
    });

    testWidgets('the partner joining replaces the code', (tester) async {
      final (_, services) = await pumpHousehold(tester);
      await createHousehold(tester);
      expect(find.text(code), findsOneWidget);

      services.households.setMembership(
        const InHousehold(
          HouseholdSummary(
            id: 'fake-new-household',
            name: 'Our home',
            baseCurrency: Currency.usd,
            memberCount: 2,
            myDisplayName: 'Alex',
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text(code), findsNothing);
      expect(find.text('Your partner has joined.'), findsOneWidget);
      expect(find.text('Invite later').hitTestable(), findsNothing);
    });

    testWidgets('opened again after creating: straight to the invite', (
      tester,
    ) async {
      final (container, services) = await pumpHousehold(
        tester,
        membership: const InHousehold(FakeHouseholdRepository.sampleHousehold),
      );
      expect(location(container).path, AppRoutes.home);
      container.read(routerProvider).go(AppRoutes.householdSetup);
      await tester.pumpAndSettle();

      expect(services.households.calls, ['createInvite']);
      expect(find.text(code), findsOneWidget);
      expect(
        tester.widget<EditableText>(field('Household name')).controller.text,
        'Our home',
      );
      expect(textField(tester, 'Household name').enabled, isFalse);
    });

    testWidgets('"I have an invite" opens the join screen; Back returns', (
      tester,
    ) async {
      final (container, _) = await pumpHousehold(tester);
      await tapLabel(tester, 'I have an invite');
      expect(location(container).path, AppRoutes.join);
      expect(find.text('JOIN'), findsOneWidget);

      await tester.tap(find.bySemanticsLabel('Back'));
      await tester.pumpAndSettle();
      expect(location(container).path, AppRoutes.householdSetup);
    });
  });

  group('Join', () {
    testWidgets('an xpense://join link fills in the code', (tester) async {
      final (container, _) = await pumpHousehold(tester);
      await openLink(tester, 'xpense://join?code=ab3de-7gh9k');

      expect(location(container).toString(), '/join?code=AB3DE7GH9K');
      expect(find.text('JOIN'), findsOneWidget);
      expect(find.bySemanticsLabel('Step 2 of 4'), findsOneWidget);
      expect(find.text("Join your partner's household"), findsOneWidget);
      expect(
        tester.widget<EditableText>(field('Invite code')).controller.text,
        code,
      );
      expect(
        find.text('Set up a household instead', skipOffstage: false),
        findsOneWidget,
      );
    });

    testWidgets('empty and malformed codes are named under the field', (
      tester,
    ) async {
      final (container, services) = await pumpHousehold(tester);
      container.read(routerProvider).go(AppRoutes.join);
      await tester.pumpAndSettle();
      await tester.enterText(field('Your name'), '');
      await tapLabel(tester, 'Join household');

      expect(find.text('Enter the code from your partner.'), findsOneWidget);
      expect(find.text('Add the name your partner will see.'), findsOneWidget);

      await tester.enterText(field('Invite code'), 'AB3DE-7GH9');
      await tester.enterText(field('Your name'), 'Sam');
      await tapLabel(tester, 'Join household');
      expect(find.text('Codes have 10 letters and numbers.'), findsOneWidget);
      expect(services.households.calls, isEmpty);
    });

    testWidgets('while joining: Joining…, the form locked', (tester) async {
      final (_, services) = await pumpHousehold(tester);
      await openLink(tester, 'xpense://join?code=AB3DE7GH9K');
      final hold = services.households.holdNext['join'] = Completer<void>();
      await tester.tap(find.text('Join household'));
      await tester.pump();

      expect(find.text('Joining…'), findsOneWidget);
      expect(button(tester, 'Joining…').onPressed, isNull);
      expect(textField(tester, 'Invite code').enabled, isFalse);

      hold.complete();
      await tester.pumpAndSettle();
      expect(find.text("Welcome to Sam's home"), findsOneWidget);
    });

    testWidgets('each refusal has its words', (tester) async {
      final (_, services) = await pumpHousehold(tester);
      await openLink(tester, 'xpense://join?code=AB3DE7GH9K');
      for (final (failure, words) in [
        (
          const InviteInvalid(),
          "That code doesn't match an invite. Check it with your partner.",
        ),
        (
          const InviteExpired(),
          'That invite has expired. Ask your partner for a new code.',
        ),
        (
          const InviteUsed(),
          'That invite was already used. Ask your partner for a new code.',
        ),
        (const HouseholdFull(), 'That household already has two people.'),
        (
          const AlreadyInHousehold(),
          "You're already in a household. Each person can be in one.",
        ),
        (
          const HouseholdRateLimited(),
          'Too many tries. Wait an hour, then try again.',
        ),
        (
          const HouseholdNotAllowed(),
          'Your sign-in has expired. Sign out and sign in again.',
        ),
        (
          const HouseholdServiceUnavailable(),
          "Invites aren't available right now. Try again later.",
        ),
        (const HouseholdUnknown('x'), 'Something went wrong. Try again.'),
      ]) {
        services.households.nextFailure = failure;
        await tapLabel(tester, 'Join household');
        expect(find.text(words), findsOneWidget, reason: failure.code);
      }
      expect(find.byType(OfflineBanner), findsNothing);
    });

    testWidgets('a wrong code is refused by the server, not the phone', (
      tester,
    ) async {
      final (_, services) = await pumpHousehold(tester);
      await openLink(tester, 'xpense://join?code=ZZZZZZZZZZ');
      await tapLabel(tester, 'Join household');
      expect(services.households.calls, ['join']);
      expect(
        find.text(
          "That code doesn't match an invite. Check it with your partner.",
        ),
        findsOneWidget,
      );
      // Editing the code clears the message.
      await tester.enterText(field('Invite code'), code);
      await tester.pump();
      expect(
        find.text(
          "That code doesn't match an invite. Check it with your partner.",
        ),
        findsNothing,
      );
    });

    testWidgets('offline: a banner, and Try again joins', (tester) async {
      final (_, services) = await pumpHousehold(tester);
      await openLink(tester, 'xpense://join?code=AB3DE7GH9K');
      services.households.nextFailure = const HouseholdOffline();
      await tapLabel(tester, 'Join household');

      expect(find.byType(OfflineBanner), findsOneWidget);
      expect(
        find.text("You're offline. Joining needs a connection."),
        findsOneWidget,
      );
      await tapLabel(tester, 'Try again');
      expect(services.households.calls, ['join', 'join']);
      expect(find.text("Welcome to Sam's home"), findsOneWidget);
    });

    testWidgets('joined: a welcome, then Continue goes on to Try it', (
      tester,
    ) async {
      final (container, services) = await pumpHousehold(tester);
      await openLink(tester, 'xpense://join?code=ab3de-7gh9k');
      await tester.enterText(field('Your name'), ' Sam ');
      await tapLabel(tester, 'Join household');

      expect(services.households.lastJoin, (
        code: 'AB3DE7GH9K',
        displayName: 'Sam',
      ));
      expect(find.text("Welcome to Sam's home"), findsOneWidget);
      expect(
        find.text(
          'You and your partner now share joint money and goals. Your own '
          'accounts stay yours.',
        ),
        findsOneWidget,
      );
      // The gate does not move a new member off the welcome.
      expect(location(container).path, AppRoutes.join);
      expect(find.bySemanticsLabel('Back'), findsNothing);

      await tapLabel(tester, 'Continue');
      expect(location(container).path, AppRoutes.tryIt);
    });

    testWidgets('"Set up a household instead" opens setup', (tester) async {
      final (container, _) = await pumpHousehold(tester);
      await openLink(tester, 'xpense://join?code=AB3DE7GH9K');
      await tapLabel(tester, 'Set up a household instead');
      expect(location(container).path, AppRoutes.householdSetup);
    });

    testWidgets('a member following a link sees no setup way out', (
      tester,
    ) async {
      final (container, _) = await pumpHousehold(
        tester,
        membership: const InHousehold(FakeHouseholdRepository.sampleHousehold),
      );
      await openLink(tester, 'xpense://join?code=AB3DE7GH9K');
      expect(location(container).path, AppRoutes.join);
      expect(
        find.text('Set up a household instead', skipOffstage: false),
        findsNothing,
      );
    });
  });

  group('both screens', () {
    for (final brightness in Brightness.values) {
      testWidgets('build at 2x text in ${brightness.name} without overflow', (
        tester,
      ) async {
        tester.platformDispatcher
          ..textScaleFactorTestValue = 2
          ..platformBrightnessTestValue = brightness;
        addTearDown(tester.platformDispatcher.clearAllTestValues);
        await pumpHousehold(tester);
        expect(find.text('Household name', skipOffstage: false), findsOne);

        await createHousehold(tester);
        expect(find.text(code, skipOffstage: false), findsOneWidget);

        await openLink(tester, 'xpense://join?code=AB3DE7GH9K');
        expect(find.text('Invite code', skipOffstage: false), findsOne);
      });
    }
  });
}
