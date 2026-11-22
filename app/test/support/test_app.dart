import 'package:clock/clock.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xpense_app/app.dart';
import 'package:xpense_app/bootstrap.dart';
import 'package:xpense_app/core/ui/ui.dart';
import 'package:xpense_app/data/auth_repository_fake.dart';
import 'package:xpense_app/data/household_repository.dart';
import 'package:xpense_app/data/household_repository_fake.dart';
import 'package:xpense_app/services/biometric_lock.dart';
import 'package:xpense_app/services/biometric_lock_fake.dart';
import 'package:xpense_app/services/on_device_llm/on_device_llm_fake.dart';
import 'package:xpense_app/services/settings_store.dart';
import 'package:xpense_app/services/settings_store_fake.dart';
import 'package:xpense_app/services/speech_capture_fake.dart';

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
  /// Creates fakes; [settings], [unlock], [signedIn] and [membership] set
  /// the starting state. Signed in to a household by default, so the app
  /// opens on Home. [onSignIn] is the membership a later sign-in finds:
  /// none, as for someone new.
  factory({
    AppSettings settings = AppSettings.defaults,
    UnlockOutcome unlock = const Unlocked(),
    bool signedIn = true,
    Membership? membership,
    Membership onSignIn = const NoHousehold(),
  }) {
    final auth = FakeAuthRepository(
      signedIn: signedIn ? FakeAuthRepository.providerUser : null,
    );
    return TestServices._(
      settingsStore: MemorySettingsStore(settings),
      biometricLock: FakeBiometricLock(outcome: unlock),
      auth: auth,
      households: FakeHouseholdRepository(
        membership:
            membership ??
            (signedIn
                ? const InHousehold(FakeHouseholdRepository.sampleHousehold)
                : const MembershipUnknown()),
        auth: auth,
        onSignIn: onSignIn,
      ),
    );
  }

  new _({
    required this.settingsStore,
    required this.biometricLock,
    required this.auth,
    required this.households,
  });

  /// Sign-in.
  final FakeAuthRepository auth;

  /// Households: membership, creating, inviting, joining.
  final FakeHouseholdRepository households;

  /// Settings, in memory.
  final MemorySettingsStore settingsStore;

  /// Face ID.
  final FakeBiometricLock biometricLock;

  /// The on-device model.
  final FakeOnDeviceLlm onDeviceLlm = FakeOnDeviceLlm();

  /// Speech to text; with no script, listening fails as unavailable.
  final FakeSpeechCapture speech = FakeSpeechCapture();

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
    authRepository: auth,
    householdRepository: households,
    onDeviceLlm: onDeviceLlm,
    speechCapture: speech,
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
