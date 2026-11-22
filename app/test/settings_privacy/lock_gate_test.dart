import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xpense_app/core/ui/ui.dart';
import 'package:xpense_app/features/settings_privacy/lock/app_lock_controller.dart';
import 'package:xpense_app/services/biometric_lock.dart';
import 'package:xpense_app/services/settings_store.dart';

import '../support/test_app.dart';

const _on = AppSettings(faceIdLock: true);

void main() {
  testWidgets('a cold start with the lock on covers the app and asks once', (
    tester,
  ) async {
    final services = TestServices(
      settings: _on,
      unlock: const UnlockCancelled(),
    );
    final semantics = tester.ensureSemantics();
    await pumpXpenseApp(tester, services);

    expect(find.byType(LockOverlay), findsOneWidget);
    expect(services.biometricLock.reasons, ['Unlock Xpense']);
    // VoiceOver hears the lock, not the money behind it.
    expect(find.bySemanticsLabel('Xpense is locked'), findsOneWidget);
    expect(find.bySemanticsLabel('Unlock with Face ID'), findsOneWidget);
    expect(find.bySemanticsLabel('Activity'), findsNothing);
    semantics.dispose();
  });

  testWidgets('content under the lock cannot be tapped', (tester) async {
    final services = TestServices(
      settings: _on,
      unlock: const UnlockCancelled(),
    );
    final container = await pumpXpenseApp(tester, services);

    await tester.tap(find.byType(AskButton), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(find.text('ASK'), findsNothing);
    expect(container.read(appLockControllerProvider).locked, isTrue);
  });

  testWidgets('Unlock with Face ID opens the app', (tester) async {
    final services = TestServices(
      settings: _on,
      unlock: const UnlockCancelled(),
    );
    await pumpXpenseApp(tester, services);

    services.biometricLock.outcome = const Unlocked();
    await tester.tap(find.text('Unlock with Face ID'));
    await tester.pumpAndSettle();
    expect(find.byType(LockOverlay), findsNothing);
    expect(find.text('HOME'), findsOneWidget);
  });

  testWidgets('a lockout shows a notice under the button', (tester) async {
    final services = TestServices(
      settings: _on,
      unlock: const UnlockLockedOut(),
    );
    await pumpXpenseApp(tester, services);

    expect(find.text('Too many attempts. Try again later.'), findsOneWidget);
  });

  testWidgets('after a minute in the background the lock returns', (
    tester,
  ) async {
    final services = TestServices(settings: _on);
    await pumpXpenseApp(tester, services);
    expect(find.byType(LockOverlay), findsNothing);

    services.biometricLock.outcome = const UnlockCancelled();
    [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
    ].forEach(tester.binding.handleAppLifecycleStateChanged);
    await tester.pump();
    services.clock.advance(
      const Duration(seconds: LockPolicy.backgroundGraceSeconds),
    );
    [
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ].forEach(tester.binding.handleAppLifecycleStateChanged);
    await tester.pumpAndSettle();

    expect(find.byType(LockOverlay), findsOneWidget);
    expect(services.biometricLock.reasons, hasLength(2));
  });

  testWidgets('the app switcher sees a cover, not the content', (tester) async {
    final services = TestServices(settings: _on);
    await pumpXpenseApp(tester, services);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    expect(find.byType(BackdropFilter), findsOneWidget);
    expect(find.byType(LockOverlay), findsNothing);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(find.byType(BackdropFilter), findsNothing);
  });

  testWidgets('with the lock off nothing covers the app', (tester) async {
    final services = TestServices();
    await pumpXpenseApp(tester, services);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    expect(find.byType(LockOverlay), findsNothing);
    expect(find.byType(BackdropFilter), findsNothing);
    expect(services.biometricLock.reasons, isEmpty);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
  });

  testWidgets('while the prompt is up the button does nothing', (tester) async {
    final services = TestServices(settings: _on)
      ..biometricLock.gate = Completer<void>();
    await pumpXpenseApp(tester, services);
    await tester.tap(find.text('Unlock with Face ID'));
    await tester.pump();
    expect(services.biometricLock.reasons, hasLength(1));
    services.biometricLock.gate!.complete();
    await tester.pumpAndSettle();
    expect(find.byType(LockOverlay), findsNothing);
  });
}
