import 'package:clock/clock.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xpense_app/app.dart';
import 'package:xpense_app/bootstrap.dart';
import 'package:xpense_app/core/ui/ui.dart';
import 'package:xpense_app/services/biometric_lock.dart';
import 'package:xpense_app/services/biometric_lock_fake.dart';
import 'package:xpense_app/services/on_device_llm/on_device_llm_fake.dart';
import 'package:xpense_app/services/settings_store.dart';
import 'package:xpense_app/services/settings_store_fake.dart';

/// A clock tests move by hand.
final class TestClock {
  /// Starts at [start].
  new([DateTime? start]) : now = start ?? DateTime.utc(2026, 11, 22, 9);

  /// The current time.
  DateTime now;

  /// The [Clock] the app reads.
  Clock get clock => Clock(() => now);

  /// Moves time forward by [by].
  void advance(Duration by) => now = now.add(by);
}

/// The fakes behind one test app, for arranging and asserting.
final class TestServices {
  /// Creates fakes; [settings] and [unlock] set the starting state.
  new({
    AppSettings settings = AppSettings.defaults,
    UnlockOutcome unlock = const Unlocked(),
  }) : settingsStore = MemorySettingsStore(settings),
       biometricLock = FakeBiometricLock(outcome: unlock);

  /// Settings, in memory.
  final MemorySettingsStore settingsStore;

  /// Face ID.
  final FakeBiometricLock biometricLock;

  /// The on-device model.
  final FakeOnDeviceLlm onDeviceLlm = FakeOnDeviceLlm();

  /// Time.
  final TestClock clock = TestClock();

  /// Glass at the solid tier, so tests never need the shader.
  final GlassController glass = GlassController(deviceTier: GlassTier.solid);

  /// The composition root's overrides, with these fakes.
  List<Override> get overrides => appOverrides(
    clock: clock.clock,
    settings: settingsStore,
    biometricLock: biometricLock,
    glass: glass,
    onDeviceLlm: onDeviceLlm,
  );

  /// A container wired like the app, disposed with the test.
  ProviderContainer container() =>
      ProviderContainer.test(overrides: overrides, retry: (_, _) => null);
}

/// Pumps the whole app on [services] and settles it. Returns the container
/// so the test can read providers.
Future<ProviderContainer> pumpXpenseApp(
  WidgetTester tester,
  TestServices services,
) async {
  final container = services.container();
  await tester.pumpWidget(
    UncontrolledProviderScope(container: container, child: const XpenseApp()),
  );
  await tester.pumpAndSettle();
  return container;
}
