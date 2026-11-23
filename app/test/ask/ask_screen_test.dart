// The Ask screen (DESIGN_SYSTEM screen 7) and its capture paths, end to end
// through the app with fakes behind every service (stories S3.9 to S3.11).
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xpense_app/app.dart';
import 'package:xpense_app/core/routing/routing.dart';
import 'package:xpense_app/data/rules_repository.dart';
import 'package:xpense_app/features/ask/ask_actions.dart';
import 'package:xpense_app/features/ask/ask_controller.dart';
import 'package:xpense_app/services/agent_client.dart';
import 'package:xpense_app/services/feature_flags.dart';
import 'package:xpense_app/services/on_device_llm/on_device_llm.dart';
import 'package:xpense_app/services/service_failure.dart';
import 'package:xpense_shared/xpense_shared.dart';

import '../support/test_app.dart';

const _fixtures = '../packages/xpense_shared/test/fixtures/surfaces';

List<Map<String, Object?>> _fixture(String name) => (jsonDecode(
  File('$_fixtures/$name.json').readAsStringSync(),
) as List<Object?>).cast<Map<String, Object?>>();

const _costcoRule = ParserRule(
  id: 'merchant_costco',
  kind: RuleKind.merchant,
  pattern: 'costco',
  categoryId: 'groceries',
  accountId: 'acc_chk',
);

DecideResponse _answers({double category = 0.70, double account = 0.95}) =>
    DecideResponse(
      intent: ChoiceAnswer(
        choice: 'expense',
        confidence: 0.97,
        probabilities: {'expense': 0.97},
      ),
      category: ChoiceAnswer(choice: 'groceries', confidence: category),
      account: ChoiceAnswer(choice: 'acc_chk', confidence: account),
    );

Future<ProviderContainer> _openAsk(
  WidgetTester tester,
  TestServices services,
) async {
  tester.view
    ..physicalSize = const Size(390, 1400) * 3
    ..devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  final container = await pumpXpenseApp(tester, services);
  unawaited(container.read(routerProvider).push(AppRoutes.ask));
  await tester.pumpAndSettle();
  return container;
}

Future<void> _type(WidgetTester tester, String text) async {
  await tester.enterText(find.byType(EditableText), text);
  await tester.pump();
}

Future<void> _send(WidgetTester tester, String text) async {
  await _type(tester, text);
  await tester.testTextInput.receiveAction(TextInputAction.send);
  await tester.pumpAndSettle();
}

RouteDecision? _route(ProviderContainer c) =>
    c.read(askControllerProvider).lastRoute;

void main() {
  testWidgets('opens empty, ready to type, in Smart mode', (tester) async {
    await _openAsk(tester, TestServices());
    expect(find.text('ASK'), findsOneWidget);
    expect(find.text('Smart'), findsOneWidget);
    expect(
      find.text(
        'Tell Xpense what you spent, earned or lent, or ask about your money.',
      ),
      findsOneWidget,
    );
    expect(find.byType(EditableText), findsOneWidget);
  });

  testWidgets('the mode chip says what the message being typed will do', (
    tester,
  ) async {
    final services = TestServices();
    await services.rules.learn(
      const RuleLesson(
        kind: RuleKind.merchant,
        pattern: 'costco',
        categoryId: 'groceries',
        accountId: 'acc_chk',
      ),
    );
    await _openAsk(tester, services);
    await _type(tester, '42.80 at Trader Joes');
    expect(find.text('Smart: classification in cloud'), findsOneWidget);
    await _type(tester, 'Salary 3200 and rent 1400');
    expect(find.text('Cloud'), findsOneWidget);
    await _type(tester, 'Costco 42.80');
    expect(find.text('On-device'), findsOneWidget);
    await _type(tester, '');
    expect(find.text('Smart'), findsOneWidget);
  });

  group('three paths', () {
    testWidgets('L: a message the rules settle never leaves the phone', (
      tester,
    ) async {
      final services = TestServices();
      await services.rules.learn(
        RuleLesson(
          kind: _costcoRule.kind,
          pattern: _costcoRule.pattern,
          categoryId: _costcoRule.categoryId,
          accountId: _costcoRule.accountId,
        ),
      );
      final c = await _openAsk(tester, services);
      await _send(tester, 'Costco 42.80');

      expect(_route(c)?.path, CapturePath.local);
      expect(_route(c)?.reason, RouteReason.resolved);
      expect(services.decisions.requests, isEmpty);
      expect(services.agent.turns, isEmpty);
      expect(find.text('“Costco 42.80”'), findsOneWidget);
      expect(find.text('EXPENSE · GROCERIES'), findsOneWidget);

      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      final saved = services.actions.saved.values.single.single;
      expect(saved.categoryId, 'groceries');
      expect(saved.accountId, 'acc_chk');
      expect(saved.amountMinor, 4280);
    });

    testWidgets('an entry in dinars previews its dollars at the latest rate '
        'without storing a quote', (tester) async {
      final services = TestServices();
      await services.rules.learn(
        const RuleLesson(
          kind: RuleKind.merchant,
          pattern: 'samoon',
          categoryId: 'groceries',
          accountId: 'acc_cash',
        ),
      );
      await _openAsk(tester, services);
      await _send(tester, 'Samoon 10000 dinars');
      // 10,000 / 1,705, shown only.
      expect(find.text('≈ USD 5.87'), findsOneWidget);
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      final saved = services.actions.saved.values.single.single;
      expect(saved.currency, 'IQD');
      expect(saved.fx, isNull);
    });

    testWidgets('D: one uncertain entry asks /decide and shows the policy', (
      tester,
    ) async {
      final services = TestServices();
      services.decisions.result = Ok(_answers());
      final c = await _openAsk(tester, services);
      await _send(tester, 'spent 42.80 dollars at Costco');

      expect(_route(c)?.path, CapturePath.decide);
      expect(_route(c)?.reason, RouteReason.decideRawText);
      final request = services.decisions.requests.single;
      expect(request.text, 'spent 42.80 dollars at Costco');
      expect(request.ask, containsAll(['category', 'account']));
      expect(services.agent.turns, isEmpty);
      expect(find.text('EXPENSE · GROCERIES'), findsOneWidget);
      expect(find.text('GUESSED'), findsOneWidget, reason: 'category 0.70');
    });

    testWidgets('D: an amount with its currency asks about duplicates, and '
        'a likely one shows the warning', (tester) async {
      final services = TestServices();
      services.decisions.result = Ok(
        DecideResponse(
          intent: ChoiceAnswer(
            choice: 'expense',
            confidence: 0.97,
            probabilities: {'expense': 0.97},
          ),
          category: ChoiceAnswer(choice: 'groceries', confidence: 0.95),
          account: ChoiceAnswer(choice: 'acc_chk', confidence: 0.95),
          duplicate: YesNoAnswer(probability: 0.92),
          duplicateOf: 'txn_earlier',
        ),
      );
      await _openAsk(tester, services);
      await _send(tester, 'spent 42.80 dollars at Costco');

      expect(services.decisions.requests.single.ask, contains('duplicate'));
      expect(find.text('Save anyway'), findsOneWidget);
    });

    testWidgets('D: a recurring guess at the configured threshold offers to '
        'repeat once saved', (tester) async {
      // 0.77 is over `recurring_offer` (0.75) but under the old 0.8.
      expect(CaptureThresholds.defaults.recurringOffer, 0.75);
      final services = TestServices();
      services.decisions.result = Ok(
        DecideResponse(
          intent: ChoiceAnswer(
            choice: 'expense',
            confidence: 0.97,
            probabilities: {'expense': 0.97},
          ),
          category: ChoiceAnswer(choice: 'groceries', confidence: 0.95),
          account: ChoiceAnswer(choice: 'acc_chk', confidence: 0.95),
          isRecurring: YesNoAnswer(probability: 0.77),
        ),
      );
      await _openAsk(tester, services);
      await _send(tester, 'spent 42.80 dollars at Costco');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(find.text('Saved.'), findsOneWidget);
      expect(find.text('Make it repeat'), findsOneWidget);
    });

    testWidgets('D: Decisions says it is a question; the agent answers, no '
        'slip', (tester) async {
      final services = TestServices();
      services.decisions.result = Ok(
        DecideResponse(
          intent: ChoiceAnswer(
            choice: 'question',
            confidence: 0.96,
            probabilities: {'question': 0.96},
          ),
        ),
      );
      services.agent.script = [const AgentReply('You spent 42.80 there.')];
      final c = await _openAsk(tester, services);
      await _send(tester, '42.80 dollars at Costco');

      expect(services.decisions.requests, hasLength(1));
      expect(services.agent.turns.single.text, '42.80 dollars at Costco');
      expect(find.text('You spent 42.80 there.'), findsOneWidget);
      expect(find.text('Save'), findsNothing);
      expect(c.read(askControllerProvider).busy, isFalse);
    });

    testWidgets('A: several entries go to the agent; its surface renders', (
      tester,
    ) async {
      final services = TestServices();
      services.agent.script = [
        const AgentReply('I found two things in that.'),
        AgentSurfaceMessages(_fixture('agent_two_entries')),
        const AgentTurnDone(traceId: 'trace-1'),
      ];
      final c = await _openAsk(tester, services);
      await _send(tester, 'Salary came in 3200 and I paid rent 1400');

      expect(_route(c)?.path, CapturePath.agent);
      expect(_route(c)?.reason, RouteReason.complex);
      expect(
        services.agent.turns.single.text,
        'Salary came in 3200 and I paid rent 1400',
      );
      expect(services.decisions.requests, isEmpty);
      expect(find.text('I found two things in that.'), findsOneWidget);
      expect(find.text('Save both'), findsOneWidget);
      expect(c.read(askControllerProvider).traceIds, ['trace-1']);
      expect(services.agent.conversations, hasLength(1));
    });

    testWidgets('a save is reported to the agent with the next turn', (
      tester,
    ) async {
      final services = TestServices();
      services.agent.script = [
        AgentSurfaceMessages(_fixture('agent_two_entries')),
      ];
      await _openAsk(tester, services);
      await _send(tester, 'Salary 3200 and rent 1400');
      await tester.tap(find.text('Save both'));
      await tester.pumpAndSettle();
      services.agent.script = [const AgentReply('Noted.')];
      await _send(tester, 'how much did we spend this month?');

      final second = services.agent.turns[1];
      expect(second.actions, hasLength(1), reason: 'xp.saved, data part');
      expect(jsonEncode(second.actions.single), contains('xp.saved'));
      expect(services.agent.conversations, hasLength(1));
    });
  });

  group('states', () {
    testWidgets('busy: the thread says so and Stop cancels the turn', (
      tester,
    ) async {
      final services = TestServices();
      services.agent
        ..script = [const AgentReply('Looking')]
        ..gate = Completer<void>();
      await _openAsk(tester, services);
      await _type(tester, 'how much did we spend on food?');
      await tester.testTextInput.receiveAction(TextInputAction.send);
      await tester.pump();
      await tester.pump();
      expect(find.text('Working on it…'), findsOneWidget);
      // A message typed meanwhile waits in the field, unsent.
      await _type(tester, 'and on rent?');
      await tester.testTextInput.receiveAction(TextInputAction.send);
      await tester.pump();
      expect(services.agent.turns, hasLength(1));
      expect(find.text('and on rent?'), findsOneWidget);
      await tester.tap(find.text('Stop'));
      await tester.pumpAndSettle();
      expect(services.agent.conversations.single.cancelCalled, isTrue);
      expect(find.text('Working on it…'), findsNothing);
      expect(
        find.text('Something went wrong with this message.'),
        findsNothing,
      );
    });

    testWidgets('busy on path D: Stop ends the wait; a late answer is '
        'dropped', (tester) async {
      final services = TestServices();
      services.decisions
        ..result = Ok(_answers())
        ..gate = Completer<void>();
      final c = await _openAsk(tester, services);
      await _type(tester, 'spent 42.80 dollars at Costco');
      await tester.testTextInput.receiveAction(TextInputAction.send);
      await tester.pump();
      expect(services.decisions.requests, hasLength(1));
      expect(find.text('Working on it…'), findsOneWidget);

      await tester.tap(find.text('Stop'));
      await tester.pump();
      expect(c.read(askControllerProvider).busy, isFalse);
      expect(find.text('Working on it…'), findsNothing);

      services.decisions.gate!.complete();
      await tester.pumpAndSettle();
      expect(find.text('EXPENSE · GROCERIES'), findsNothing);
      expect(c.read(askControllerProvider).busy, isFalse);
    });

    testWidgets('busy on the on-device extraction: Stop ends it; Decisions '
        'is never asked', (tester) async {
      final services = TestServices();
      services.onDeviceLlm
        ..probeResult = const OnDeviceProbe(
          engine: OnDeviceEngine.appleFoundationModels,
        )
        ..gate = Completer<void>();
      services.decisions.result = Ok(_answers());
      final c = await _openAsk(tester, services);
      await _type(tester, 'spent 42.80 dollars at Costco');
      await tester.testTextInput.receiveAction(TextInputAction.send);
      await tester.pump();
      expect(_route(c)?.reason, RouteReason.onDeviceThenDecide);
      expect(find.text('Working on it…'), findsOneWidget);

      await tester.tap(find.text('Stop'));
      await tester.pump();
      expect(c.read(askControllerProvider).busy, isFalse);

      services.onDeviceLlm.gate!.complete();
      await tester.pumpAndSettle();
      expect(services.decisions.requests, isEmpty);
      expect(find.text('EXPENSE · GROCERIES'), findsNothing);
    });

    testWidgets('error: a notice with Retry sends the message again', (
      tester,
    ) async {
      final services = TestServices();
      services.agent.script = [
        const AgentTurnFailed(ServiceError('agent.internal.x')),
      ];
      await _openAsk(tester, services);
      await _send(tester, 'how much did we spend on food?');
      expect(
        find.text('Something went wrong with this message.'),
        findsOneWidget,
      );

      services.agent.script = [const AgentReply('About 180 dollars.')];
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(services.agent.turns, hasLength(2));
      expect(find.text('About 180 dollars.'), findsOneWidget);
      expect(
        find.text('Something went wrong with this message.'),
        findsNothing,
      );
      expect(
        find.text('“how much did we spend on food?”'),
        findsOneWidget,
        reason: 'Retry does not repeat the quote',
      );
    });

    testWidgets('limit: the notice says it resets tomorrow; no Retry', (
      tester,
    ) async {
      final services = TestServices();
      services.agent.script = [const AgentTurnFailed(ServiceRateLimited())];
      await _openAsk(tester, services);
      await _send(tester, 'how much did we spend on food?');
      expect(
        find.text(
          "Today's cloud limit for your household is used up. "
          'It resets tomorrow.',
        ),
        findsOneWidget,
      );
      expect(find.text('Retry'), findsNothing);
    });

    testWidgets('offline: banner, and Finish manually builds the slip here', (
      tester,
    ) async {
      final services = TestServices(
        flags: const FeatureFlags(routerNoModelUsesDecide: false),
      );
      services.agent.script = [const AgentTurnFailed(ServiceOffline())];
      final c = await _openAsk(tester, services);
      await _send(tester, '42.80 at Costco');
      expect(_route(c)?.reason, RouteReason.fallback);
      expect(
        find.text('Offline. Entries are made on this phone.'),
        findsOneWidget,
      );
      expect(
        find.text('No connection. This message needs the cloud.'),
        findsOneWidget,
      );

      await tester.tap(find.text('Finish manually'));
      await tester.pumpAndSettle();
      expect(
        find.text('No connection. This message needs the cloud.'),
        findsNothing,
      );
      expect(find.text('Save'), findsOneWidget);
    });

    testWidgets('offline on path D: the slip is built here, with pickers', (
      tester,
    ) async {
      final services = TestServices();
      services.decisions.result = const Err(ServiceOffline());
      await _openAsk(tester, services);
      await _send(tester, 'spent 42.80 dollars at Costco');
      expect(
        find.text('Offline. Entries are made on this phone.'),
        findsOneWidget,
      );
      expect(find.text('Save'), findsOneWidget);
    });

    testWidgets('limit on path D: the slip, and the limit notice', (
      tester,
    ) async {
      final services = TestServices();
      services.decisions.result = const Err(ServiceRateLimited());
      await _openAsk(tester, services);
      await _send(tester, 'spent 42.80 dollars at Costco');
      expect(find.text('Save'), findsOneWidget);
      expect(find.textContaining("Today's cloud limit"), findsOneWidget);
    });

    testWidgets('On-device mode keeps a question on the phone and says why', (
      tester,
    ) async {
      final services = TestServices();
      await _openAskWithMode(tester, services, CapturePrivacyMode.onDevice);
      await _send(tester, 'how much did we spend on food?');
      expect(services.agent.turns, isEmpty);
      expect(find.textContaining('On-device mode keeps this'), findsOneWidget);
    });
  });

  testWidgets('learning: a corrected guess becomes a rule, and the same '
      'merchant then resolves on path L (S3.11)', (tester) async {
    final services = TestServices();
    services.decisions.result = Ok(_answers());
    final c = await _openAsk(tester, services);
    await _send(tester, 'spent 42.80 dollars at Costco');
    expect(find.text('GUESSED'), findsOneWidget);

    // Correct the guessed category, then save.
    await tester.tap(find.text('EXPENSE · GROCERIES'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('pick_categoryId_household')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    final rule = services.rules.current.single;
    expect(rule.kind, RuleKind.merchant);
    expect(rule.pattern, 'costco');
    expect(rule.categoryId, 'household');
    expect(rule.accountId, 'acc_chk');

    await _send(tester, 'Costco 30');
    expect(_route(c)?.path, CapturePath.local);
    expect(services.decisions.requests, hasLength(1), reason: 'no new call');
    // The first slip now shows its saved line; the new one is local.
    expect(find.text('EXPENSE · HOUSEHOLD'), findsOneWidget);
    expect(find.text('Save'), findsOneWidget);
  });
}

Future<void> _openAskWithMode(
  WidgetTester tester,
  TestServices services,
  CapturePrivacyMode mode,
) async {
  tester.view
    ..physicalSize = const Size(390, 1400) * 3
    ..devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  final container = ProviderContainer.test(
    overrides: [
      ...services.overrides,
      capturePrivacyModeProvider.overrideWithValue(mode),
    ],
    retry: (_, _) => null,
  );
  await tester.pumpWidget(
    UncontrolledProviderScope(container: container, child: const XpenseApp()),
  );
  await tester.pumpAndSettle();
  unawaited(container.read(routerProvider).push(AppRoutes.ask));
  await tester.pumpAndSettle();
}
