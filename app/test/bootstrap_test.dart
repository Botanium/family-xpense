import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:xpense_app/app.dart';
import 'package:xpense_app/bootstrap.dart';
import 'package:xpense_app/core/routing/routing.dart';
import 'package:xpense_app/services/agent_client.dart';
import 'package:xpense_app/services/biometric_lock.dart';
import 'package:xpense_app/services/clock.dart';
import 'package:xpense_app/services/decisions_client.dart';
import 'package:xpense_app/services/feature_flags.dart';
import 'package:xpense_app/services/ocr_engine.dart';
import 'package:xpense_app/services/on_device_llm/on_device_llm.dart';
import 'package:xpense_app/services/secure_store.dart';
import 'package:xpense_app/services/settings_store.dart';
import 'package:xpense_app/services/speech_capture.dart';

import 'support/test_app.dart';

void main() {
  group('App Check provider (D-39)', () {
    test('App Attest only in a release build on a device', () {
      expect(
        appleAppCheckFor(releaseBuild: true, simulator: false),
        AppleAppCheck.appAttest,
      );
    });

    test('the debug provider on the simulator and outside release', () {
      for (final (release, simulator) in [
        (true, true),
        (false, true),
        (false, false),
      ]) {
        expect(
          appleAppCheckFor(releaseBuild: release, simulator: simulator),
          AppleAppCheck.debug,
          reason: 'release: $release, simulator: $simulator',
        );
      }
    });

    test('a test run is not the simulator', () {
      expect(runningOnSimulator, isFalse);
    });
  });

  group('feature flags', () {
    test('fakes start at the shipped defaults: Apple sign-in off', () async {
      final flags = await connectFeatureFlags(AppEnvironment.fakes);
      expect(flags.current, FeatureFlags.defaults);
      expect(flags.current.appleSignInEnabled, isFalse);
      expect(FeatureFlags.remoteDefaults, {'apple_sign_in_enabled': false});
    });
  });

  group('AppEnvironment', () {
    test('defaults to fakes, which needs no Firebase', () {
      expect(AppEnvironment.fromName(''), AppEnvironment.fakes);
      expect(AppEnvironment.fromName('staging'), AppEnvironment.fakes);
      expect(AppEnvironment.compiled, AppEnvironment.fakes);
      expect(AppEnvironment.fakes.usesFirebase, isFalse);
    });

    test('dev and prod initialise Firebase', () {
      expect(AppEnvironment.fromName('dev'), AppEnvironment.dev);
      expect(AppEnvironment.fromName('prod'), AppEnvironment.prod);
      expect(AppEnvironment.dev.usesFirebase, isTrue);
      expect(AppEnvironment.prod.usesFirebase, isTrue);
    });
  });

  group('ErrorLog', () {
    test('keeps the last entries only', () {
      final log = ErrorLog(capacity: 2)
        ..record('a', null)
        ..record('b', null)
        ..record('c', null);
      expect(log.entries.map((e) => e.split('\n').first), ['b', 'c']);
    });

    test('records the cause, not the ProviderException wrapper', () {
      final failing = Provider<int>((ref) => throw StateError('disk'));
      final container = ProviderContainer.test(retry: (_, _) => null);
      Object? caught;
      try {
        container.read(failing);
      } on Object catch (error) {
        caught = error;
      }
      expect(unwrapProviderException(caught!), isA<StateError>());
      final log = ErrorLog()..record(caught, null);
      expect(log.entries.single, startsWith('Bad state: disk'));
    });
  });

  group('installErrorHandlers', () {
    late FlutterExceptionHandler? flutterBefore;
    late ErrorCallback? platformBefore;

    setUp(() {
      flutterBefore = FlutterError.onError;
      platformBefore = PlatformDispatcher.instance.onError;
    });

    tearDown(() {
      FlutterError.onError = flutterBefore;
      PlatformDispatcher.instance.onError = platformBefore;
    });

    test('uncaught async errors are recorded and always handled', () {
      final log = ErrorLog();
      installErrorHandlers(log);
      final handled = PlatformDispatcher.instance.onError!(
        StateError('async'),
        StackTrace.empty,
      );
      expect(handled, isTrue);
      expect(log.entries.single, startsWith('Bad state: async'));
    });

    test('framework errors are recorded', () {
      final log = ErrorLog();
      installErrorHandlers(log);
      FlutterError.onError!(
        FlutterErrorDetails(exception: StateError('build'), silent: true),
      );
      expect(log.entries.single, startsWith('Bad state: build'));
    });
  });

  group('composition root', () {
    test('every service seam throws until it is wired', () {
      final container = ProviderContainer.test(retry: (_, _) => null);
      for (final provider in <ProviderListenable<Object?>>[
        clockProvider,
        settingsStoreProvider,
        biometricLockProvider,
        secureStoreProvider,
        agentClientProvider,
        decisionsClientProvider,
        onDeviceLlmProvider,
        speechCaptureProvider,
        ocrEngineProvider,
        glassControllerProvider,
      ]) {
        expect(() => container.read(provider), throwsA(anything));
      }
    });

    test('appOverrides wires every seam', () {
      final container = TestServices().container();
      expect(container.read(clockProvider), isNotNull);
      expect(container.read(settingsStoreProvider), isNotNull);
      expect(container.read(biometricLockProvider), isNotNull);
      expect(container.read(secureStoreProvider), isNotNull);
      expect(container.read(agentClientProvider), isNotNull);
      expect(container.read(decisionsClientProvider), isNotNull);
      expect(container.read(onDeviceLlmProvider), isNotNull);
      expect(container.read(speechCaptureProvider), isNotNull);
      expect(container.read(ocrEngineProvider), isNotNull);
      expect(container.read(glassControllerProvider), isNotNull);
    });
  });

  group('settings restore', () {
    test('stored values decode; anything unknown falls back', () {
      expect(
        SettingsKeys.decode(appearance: 'dark', faceIdLock: true),
        const AppSettings(appearance: AppearanceMode.dark, faceIdLock: true),
      );
      expect(SettingsKeys.decode(), AppSettings.defaults);
      expect(SettingsKeys.decode(appearance: 'sepia'), AppSettings.defaults);
    });

    for (final (appearance, brightness) in [
      (AppearanceMode.dark, Brightness.dark),
      (AppearanceMode.light, Brightness.light),
    ]) {
      testWidgets('the first frame already paints ${appearance.name}', (
        tester,
      ) async {
        final services = TestServices(
          settings: AppSettings(appearance: appearance),
        );
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: services.container(),
            child: const XpenseApp(),
          ),
        );
        // One frame only: no settling, no second build.
        final context = tester.element(find.byType(AppShell));
        expect(Theme.of(context).brightness, brightness);
      });
    }

    testWidgets('System follows the phone', (tester) async {
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
      await pumpXpenseApp(tester, TestServices());
      final context = tester.element(find.byType(AppShell));
      expect(Theme.of(context).brightness, Brightness.dark);
    });
  });
}
