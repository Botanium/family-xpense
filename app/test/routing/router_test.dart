import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:xpense_app/app.dart';
import 'package:xpense_app/core/routing/routing.dart';
import 'package:xpense_app/core/ui/ui.dart';

import '../support/test_app.dart';

/// Delivers [link] the way the iOS engine does when another app opens it:
/// `pushRouteInformation` on the navigation channel, with the full URL.
Future<void> openLink(WidgetTester tester, String link) async {
  await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
    SystemChannels.navigation.name,
    SystemChannels.navigation.codec.encodeMethodCall(
      MethodCall('pushRouteInformation', {'location': link}),
    ),
    (_) {},
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('xpense://ask?text= opens Ask with the text prefilled, unsent', (
    tester,
  ) async {
    final container = await pumpXpenseApp(tester, TestServices());

    await openLink(tester, 'xpense://ask?text=lunch%2010000');

    final router = container.read(routerProvider);
    expect(router.state.uri.path, AppRoutes.ask);
    expect(find.text('ASK'), findsOneWidget);
    final field = tester.widget<EditableText>(find.byType(EditableText));
    expect(field.controller.text, 'lunch 10000');
    // Nothing was sent to the agent.
    expect(find.byType(CaptureDock), findsOneWidget);
  });

  testWidgets('Back from a deep-linked Ask with nothing below goes Home', (
    tester,
  ) async {
    final container = await pumpXpenseApp(tester, TestServices());
    await openLink(tester, 'xpense://ask');

    await tester.tap(find.bySemanticsLabel('Back'));
    await tester.pumpAndSettle();
    expect(container.read(routerProvider).state.uri.path, AppRoutes.home);
  });

  testWidgets('entry, loan and join links open their screens', (tester) async {
    final container = await pumpXpenseApp(tester, TestServices());
    final router = container.read(routerProvider);

    await openLink(tester, 'xpense://txn/t1');
    expect(router.state.uri.path, '/entries/t1');
    expect(router.state.pathParameters[AppRoutes.idParam], 't1');
    expect(find.text('ENTRY'), findsOneWidget);

    await openLink(tester, 'xpense://loan/L1');
    expect(router.state.uri.path, '/loans/L1');
    expect(find.text('LOAN'), findsOneWidget);

    await openLink(tester, 'xpense://join?code=abcde-23456');
    expect(router.state.uri.toString(), '/join?code=ABCDE23456');
    expect(find.text('JOIN'), findsOneWidget);
  });

  testWidgets('a link that opens nothing lands on Not found, with a way home', (
    tester,
  ) async {
    final container = await pumpXpenseApp(tester, TestServices());

    await openLink(tester, 'xpense://nowhere');
    expect(find.text('NOT FOUND'), findsOneWidget);

    await tester.tap(find.text('Go to Home'));
    await tester.pumpAndSettle();
    expect(container.read(routerProvider).state.uri.path, AppRoutes.home);
  });

  testWidgets('an unknown in-app path shows Not found, not an error box', (
    tester,
  ) async {
    final container = await pumpXpenseApp(tester, TestServices());

    container.read(routerProvider).go('/no-such-screen');
    await tester.pumpAndSettle();
    expect(find.byType(NotFoundScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Reduce Motion cuts instead of sliding', (tester) async {
    final container = await pumpXpenseApp(tester, TestServices());
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await tester.pump();

    unawaited(container.read(routerProvider).push(AppRoutes.ask));
    await tester.pump();
    // No transition: Ask is fully in place on the first frame.
    expect(find.text('ASK'), findsOneWidget);
    expect(tester.hasRunningAnimations, isFalse);
  });
}
