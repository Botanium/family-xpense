import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xpense_app/features/settings_privacy/settings_view_model.dart';
import 'package:xpense_app/services/settings_store.dart';

import '../support/test_app.dart';

const _both = AppSettings(appearance: AppearanceMode.dark, faceIdLock: true);

/// Two settings changed while the first is still being saved must both
/// survive: each change applies to the latest settings, not to a snapshot
/// taken before the other save finished (PR #13 review).
void main() {
  late TestServices services;
  late ProviderContainer container;
  late SettingsViewModel settings;

  setUp(() {
    services = TestServices();
    services.settingsStore.gate = Completer<void>();
    container = services.container()
      ..listen(settingsViewModelProvider, (_, _) {});
    settings = container.read(settingsViewModelProvider.notifier);
  });

  Future<void> releaseSaves() async {
    services.settingsStore.gate!.complete();
    await pumpEventQueue();
  }

  test(
    'turning the lock on, then changing appearance mid-save, keeps both',
    () async {
      settings.setFaceIdLock(on: true, reason: 'r');
      await pumpEventQueue(); // Face ID confirmed; the save waits at the gate.
      settings.setAppearance(AppearanceMode.dark);
      await pumpEventQueue();
      await releaseSaves();

      expect(container.read(appSettingsProvider), _both);
      expect(services.settingsStore.current, _both);
    },
  );

  test(
    'changing appearance, then turning the lock on mid-save, keeps both',
    () async {
      settings.setAppearance(AppearanceMode.dark);
      await pumpEventQueue();
      settings.setFaceIdLock(on: true, reason: 'r');
      await pumpEventQueue();
      await releaseSaves();

      expect(container.read(appSettingsProvider), _both);
      expect(services.settingsStore.current, _both);
    },
  );

  test(
    'a failed save leaves its change unpublished and later ones run',
    () async {
      final controller = container.read(appSettingsProvider.notifier);
      services.settingsStore.failWith = Exception('disk full');
      final failing = controller.update(
        (s) => s.copyWith(appearance: AppearanceMode.dark),
      );
      final failed = expectLater(failing, throwsException);
      await releaseSaves();
      await failed;
      expect(container.read(appSettingsProvider), AppSettings.defaults);

      services.settingsStore.failWith = null;
      await controller.update((s) => s.copyWith(faceIdLock: true));
      expect(
        container.read(appSettingsProvider),
        const AppSettings(faceIdLock: true),
      );
    },
  );
}
