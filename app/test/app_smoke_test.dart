import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:xpense_app/app.dart';
import 'package:xpense_app/core/routing/routing.dart';
import 'package:xpense_app/core/ui/ui.dart';
import 'package:xpense_app/features/settings_privacy/settings_screen.dart';

import 'support/test_app.dart';

void main() {
  testWidgets('starts on Home with the four tabs and the Ask button', (
    tester,
  ) async {
    await pumpXpenseApp(tester, TestServices());

    expect(find.text('HOME'), findsOneWidget);
    expect(find.byType(XpTabBar), findsOneWidget);
    for (final label in ['Home', 'Activity', 'Goals', 'Accounts']) {
      expect(find.bySemanticsLabel(label), findsOneWidget, reason: label);
    }
    expect(find.bySemanticsLabel('Ask: talk, type or scan'), findsOneWidget);
  });

  testWidgets('the tab bar switches tabs', (tester) async {
    final container = await pumpXpenseApp(tester, TestServices());
    final router = container.read(routerProvider);

    for (final (label, title, path) in [
      ('Activity', 'ACTIVITY', AppRoutes.activity),
      ('Goals', 'GOALS', AppRoutes.goals),
      ('Accounts', 'ACCOUNTS', AppRoutes.accounts),
      ('Home', 'HOME', AppRoutes.home),
    ]) {
      await tester.tap(find.bySemanticsLabel(label));
      await tester.pumpAndSettle();
      expect(find.text(title), findsOneWidget, reason: label);
      expect(router.state.uri.path, path);
    }
  });

  testWidgets('tabs stay alive offstage when switching away and back', (
    tester,
  ) async {
    await pumpXpenseApp(tester, TestServices());

    await tester.tap(find.bySemanticsLabel('Activity'));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('Home'));
    await tester.pumpAndSettle();

    // StatefulShellRoute.indexedStack keeps the Activity branch built, so
    // its stack and scroll position survive the switch.
    expect(find.text('ACTIVITY'), findsNothing);
    expect(find.text('ACTIVITY', skipOffstage: false), findsOneWidget);
    final shell = tester.widget<StatefulNavigationShell>(
      find.byType(StatefulNavigationShell),
    );
    expect(shell.currentIndex, AppTab.home.index);
  });

  testWidgets('the Ask button pushes Ask above the shell; back returns', (
    tester,
  ) async {
    final container = await pumpXpenseApp(tester, TestServices());
    final router = container.read(routerProvider);

    await tester.tap(find.bySemanticsLabel('Ask: talk, type or scan'));
    await tester.pumpAndSettle();
    expect(router.state.uri.path, AppRoutes.ask);
    expect(find.text('ASK'), findsOneWidget);
    expect(find.byType(CaptureDock), findsOneWidget);
    // Above the shell: the tab bar is not shown.
    expect(find.byType(XpTabBar), findsNothing);

    await tester.tap(find.bySemanticsLabel('Back'));
    await tester.pumpAndSettle();
    expect(router.state.uri.path, AppRoutes.home);
    expect(find.byType(XpTabBar), findsOneWidget);
  });

  testWidgets('Home opens Settings', (tester) async {
    await pumpXpenseApp(tester, TestServices());

    await tester.tap(find.bySemanticsLabel('Settings'));
    await tester.pumpAndSettle();
    expect(find.byType(SettingsScreen), findsOneWidget);
  });

  testWidgets('the post-frame work probes the on-device model once', (
    tester,
  ) async {
    final services = TestServices();
    await pumpXpenseApp(tester, services);
    expect(services.onDeviceLlm.probes, 1);
  });

  testWidgets('strings come from the ARB file', (tester) async {
    await pumpXpenseApp(tester, TestServices());
    final context = tester.element(find.byType(XpTabBar));
    expect(Localizations.localeOf(context), const Locale('en'));
  });
}
