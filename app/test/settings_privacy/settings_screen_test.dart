import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:xpense_app/app.dart';
import 'package:xpense_app/core/routing/routing.dart';
import 'package:xpense_app/core/ui/ui.dart';
import 'package:xpense_app/services/biometric_lock.dart';
import 'package:xpense_app/services/settings_store.dart';

import '../support/test_app.dart';

Future<void> openSettings(WidgetTester tester, TestServices services) async {
  final container = await pumpXpenseApp(tester, services);
  unawaited(container.read(routerProvider).push(AppRoutes.settings));
  await tester.pumpAndSettle();
}

Brightness brightnessOf(WidgetTester tester) =>
    Theme.of(tester.element(find.byType(XpTopBar).last)).brightness;

void main() {
  testWidgets('appearance chips switch the theme and persist the choice', (
    tester,
  ) async {
    final services = TestServices();
    await openSettings(tester, services);
    expect(brightnessOf(tester), Brightness.light);

    await tester.tap(find.text('Dark'));
    await tester.pumpAndSettle();
    expect(brightnessOf(tester), Brightness.dark);
    expect(services.settingsStore.current.appearance, AppearanceMode.dark);

    await tester.tap(find.text('Light'));
    await tester.pumpAndSettle();
    expect(brightnessOf(tester), Brightness.light);
    expect(services.settingsStore.saves, 2);
  });

  testWidgets('a failed save leaves the theme as stored', (tester) async {
    final services = TestServices();
    await openSettings(tester, services);
    services.settingsStore.failWith = Exception('disk full');

    await tester.tap(find.text('Dark'));
    await tester.pumpAndSettle();
    expect(brightnessOf(tester), Brightness.light);
    expect(tester.takeException(), isA<Exception>());
  });

  testWidgets('turning the lock on asks for Face ID first', (tester) async {
    final services = TestServices();
    await openSettings(tester, services);

    await tester.tap(find.byType(XpSwitch));
    await tester.pumpAndSettle();
    expect(services.biometricLock.reasons, ['Turn on the lock for Xpense']);
    expect(services.settingsStore.current.faceIdLock, isTrue);
    final toggle = tester.widget<XpSwitch>(find.byType(XpSwitch));
    expect(toggle.value, isTrue);
  });

  testWidgets('a cancelled prompt leaves the lock off', (tester) async {
    final services = TestServices(unlock: const UnlockCancelled());
    await openSettings(tester, services);

    await tester.tap(find.byType(XpSwitch));
    await tester.pumpAndSettle();
    expect(services.settingsStore.current.faceIdLock, isFalse);
    expect(services.settingsStore.saves, 0);
  });

  testWidgets('a phone without a passcode explains why the lock stays off', (
    tester,
  ) async {
    final services = TestServices(unlock: const UnlockUnavailable());
    await openSettings(tester, services);

    await tester.tap(find.byType(XpSwitch));
    await tester.pumpAndSettle();
    expect(
      find.text('Set a passcode on this iPhone to use the lock.'),
      findsOneWidget,
    );
    expect(services.settingsStore.current.faceIdLock, isFalse);
  });

  testWidgets('turning the lock off needs no prompt', (tester) async {
    final services = TestServices(
      settings: const AppSettings(faceIdLock: true),
    );
    final container = await pumpXpenseApp(tester, services);
    // Through the cold-start lock first.
    expect(services.biometricLock.reasons, hasLength(1));
    unawaited(container.read(routerProvider).push(AppRoutes.settings));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(XpSwitch));
    await tester.pumpAndSettle();
    expect(services.settingsStore.current.faceIdLock, isFalse);
    expect(services.biometricLock.reasons, hasLength(1));
  });

  testWidgets('debug builds link the component gallery', (tester) async {
    await openSettings(tester, TestServices());
    expect(find.text('Component gallery'), findsOneWidget);
  });
}
