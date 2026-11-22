import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xpense_app/features/settings_privacy/lock/app_lock_controller.dart';
import 'package:xpense_app/services/biometric_lock.dart';
import 'package:xpense_app/services/settings_store.dart';

import '../support/test_app.dart';

const _on = AppSettings(faceIdLock: true);
const _grace = Duration(seconds: LockPolicy.backgroundGraceSeconds);

void main() {
  group('with the lock off', () {
    test('the app starts open and never locks or covers', () {
      final services = TestServices();
      final container = services.container();
      final lock = container.read(appLockControllerProvider.notifier);

      expect(container.read(appLockControllerProvider), const AppLockState());
      lock
        ..onLifecycle(AppLifecycleState.inactive)
        ..onLifecycle(AppLifecycleState.hidden)
        ..onLifecycle(AppLifecycleState.paused);
      services.clock.advance(const Duration(hours: 1));
      lock.onLifecycle(AppLifecycleState.resumed);
      expect(container.read(appLockControllerProvider), const AppLockState());
    });
  });

  group('with the lock on', () {
    late TestServices services;
    late AppLockController lock;
    late AppLockState Function() read;

    setUp(() {
      services = TestServices(settings: _on);
      final container = services.container();
      lock = container.read(appLockControllerProvider.notifier);
      read = () => container.read(appLockControllerProvider);
    });

    void background() => lock
      ..onLifecycle(AppLifecycleState.inactive)
      ..onLifecycle(AppLifecycleState.hidden)
      ..onLifecycle(AppLifecycleState.paused);

    void foreground() => lock
      ..onLifecycle(AppLifecycleState.hidden)
      ..onLifecycle(AppLifecycleState.inactive)
      ..onLifecycle(AppLifecycleState.resumed);

    Future<void> unlock() async {
      lock.unlock(reason: 'Unlock Xpense');
      await pumpEventQueue();
    }

    test('a cold start is locked and asks for Face ID once', () {
      expect(read().locked, isTrue);
      expect(read().promptRequest, 1);
    });

    test('Face ID opens the app; the reason is passed to iOS', () async {
      await unlock();
      expect(read(), const AppLockState(promptRequest: 1));
      expect(services.biometricLock.reasons, ['Unlock Xpense']);
    });

    test('while the prompt is up the app is authenticating, once', () async {
      services.biometricLock.gate = Completer<void>();
      lock
        ..unlock(reason: 'r')
        ..unlock(reason: 'r');
      expect(read().authenticating, isTrue);
      services.biometricLock.gate!.complete();
      await pumpEventQueue();
      expect(services.biometricLock.reasons, hasLength(1));
      expect(read().locked, isFalse);
    });

    test('cancelling keeps it locked without a notice', () async {
      services.biometricLock.outcome = const UnlockCancelled();
      await unlock();
      expect(read(), const AppLockState(locked: true, promptRequest: 1));
    });

    test('lockout and failure keep it locked with a notice', () async {
      services.biometricLock.outcome = const UnlockLockedOut();
      await unlock();
      expect(read().notice, LockNotice.lockedOut);
      services.biometricLock.outcome = const UnlockFailed();
      await unlock();
      expect(read().notice, LockNotice.failed);
      expect(read().locked, isTrue);
    });

    test('a phone without a passcode is not locked out of its data', () async {
      services.biometricLock.outcome = const UnlockUnavailable();
      await unlock();
      expect(read().locked, isFalse);
    });

    test('the app switcher covers the open app; returning uncovers', () async {
      await unlock();
      lock.onLifecycle(AppLifecycleState.inactive);
      expect(read().obscured, isTrue);
      expect(read().locked, isFalse);
      lock.onLifecycle(AppLifecycleState.resumed);
      expect(read().obscured, isFalse);
    });

    test('under a minute in the background stays open', () async {
      await unlock();
      background();
      services.clock.advance(_grace - const Duration(seconds: 1));
      foreground();
      expect(read(), const AppLockState(promptRequest: 1));
    });

    test('a minute or more in the background locks and asks again', () async {
      await unlock();
      background();
      services.clock.advance(_grace);
      foreground();
      expect(read(), const AppLockState(locked: true, promptRequest: 2));
    });

    test(
      'the Face ID prompt itself does not ask again after a cancel',
      () async {
        services.biometricLock.outcome = const UnlockCancelled();
        await unlock();
        // The prompt made the app inactive; dismissing it makes it active.
        lock
          ..onLifecycle(AppLifecycleState.inactive)
          ..onLifecycle(AppLifecycleState.resumed);
        expect(read().promptRequest, 1);
      },
    );

    test(
      'returning to a still-locked app from the background asks again',
      () async {
        // The cold-start request was answered, and cancelled.
        services.biometricLock.outcome = const UnlockCancelled();
        await unlock();
        background();
        foreground();
        expect(read().promptRequest, 2);
      },
    );

    test('a cold-start request no prompt answered is renewed on resume', () {
      // The first frame came before the app was active, so nothing asked.
      lock.onLifecycle(AppLifecycleState.resumed);
      expect(read().promptRequest, 2);
      lock.promptIfRequested(reason: 'r');
      expect(read().authenticating, isTrue);
      lock.promptIfRequested(reason: 'r');
      expect(services.biometricLock.reasons, hasLength(1));
    });

    test('turning the lock off opens the app at once', () async {
      final container = services.container();
      final notifier = container.read(appLockControllerProvider.notifier);
      expect(container.read(appLockControllerProvider).locked, isTrue);
      await container
          .read(appSettingsProvider.notifier)
          .save(AppSettings.defaults);
      expect(container.read(appLockControllerProvider).locked, isFalse);
      notifier.onLifecycle(AppLifecycleState.inactive);
      expect(container.read(appLockControllerProvider).obscured, isFalse);
    });
  });
}
