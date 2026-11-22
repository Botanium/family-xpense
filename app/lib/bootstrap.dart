// The composition root (ARCHITECTURE 3.3): the one place that names
// concrete implementations. Features see only the throwing providers in
// `lib/services/`; this file overrides them.
import 'dart:collection';
import 'dart:io';

import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/misc.dart';

import 'package:xpense_app/app.dart';
import 'package:xpense_app/core/theme/theme.dart';
import 'package:xpense_app/core/ui/ui.dart';
import 'package:xpense_app/data/accounts_repository.dart';
import 'package:xpense_app/data/accounts_repository_fake.dart';
import 'package:xpense_app/data/accounts_repository_firebase.dart';
import 'package:xpense_app/data/auth_repository.dart';
import 'package:xpense_app/data/auth_repository_fake.dart';
import 'package:xpense_app/data/auth_repository_firebase.dart';
import 'package:xpense_app/data/household_repository.dart';
import 'package:xpense_app/data/household_repository_fake.dart';
import 'package:xpense_app/data/household_repository_firebase.dart';
import 'package:xpense_app/services/agent_client.dart';
import 'package:xpense_app/services/agent_client_fake.dart';
import 'package:xpense_app/services/biometric_lock.dart';
import 'package:xpense_app/services/biometric_lock_local_auth.dart';
import 'package:xpense_app/services/clock.dart';
import 'package:xpense_app/services/decisions_client.dart';
import 'package:xpense_app/services/decisions_client_fake.dart';
import 'package:xpense_app/services/feature_flags.dart';
import 'package:xpense_app/services/feature_flags_fake.dart';
import 'package:xpense_app/services/feature_flags_remote_config.dart';
import 'package:xpense_app/services/ocr_engine.dart';
import 'package:xpense_app/services/ocr_engine_fake.dart';
import 'package:xpense_app/services/on_device_llm/on_device_llm.dart';
import 'package:xpense_app/services/on_device_llm/on_device_llm_fake.dart';
import 'package:xpense_app/services/secure_store.dart';
import 'package:xpense_app/services/secure_store_fake.dart';
import 'package:xpense_app/services/settings_store.dart';
import 'package:xpense_app/services/settings_store_prefs.dart';
import 'package:xpense_app/services/speech_capture.dart';
import 'package:xpense_app/services/speech_capture_fake.dart';

/// Which backend a build talks to, from `--dart-define=XPENSE_ENV=…`.
enum AppEnvironment {
  /// No Firebase project: remote services are fakes and nothing signs in.
  /// The default, so the app runs from a clean checkout without config
  /// files.
  fakes,

  /// `xpense-dev`. Needs the Firebase config files from WP-01.
  dev,

  /// `xpense-prod`. Needs the Firebase config files from WP-01.
  prod,

  /// The local Firebase emulator suite and a local server, under the fake
  /// project `demo-xpense`, so nothing reaches a real project (WP-12). No
  /// config file is bundled and App Check is off; the local server runs
  /// with `XPENSE_APP_CHECK=emulator`. Email sign-in only.
  emulators;

  /// The `--dart-define` key that picks the environment.
  static const String defineKey = 'XPENSE_ENV';

  /// The environment this build was compiled for.
  static AppEnvironment get compiled =>
      fromName(const String.fromEnvironment(defineKey));

  /// Parses [name]; anything unknown, including empty, is [fakes].
  static AppEnvironment fromName(String name) =>
      values.asNameMap()[name] ?? fakes;

  /// Whether startup initialises Firebase.
  bool get usesFirebase => this != fakes;

  /// Whether startup activates App Check (a real project only).
  bool get usesAppCheck => this == dev || this == prod;
}

/// The fake project the [AppEnvironment.emulators] build and the local
/// server share (`server/lib/config/server_env.dart`).
const String emulatorProjectId = 'demo-xpense';

/// `--dart-define=XPENSE_AUTH_EMULATOR=host:port` points Firebase Auth at
/// the emulator suite (`firebase/firebase.json`: `127.0.0.1:9099`). Use the
/// IP: on the simulator `localhost` may resolve to IPv6, where the emulator
/// does not listen. Dev builds only; ignored in prod.
const String authEmulatorDefine = String.fromEnvironment(
  'XPENSE_AUTH_EMULATOR',
);

/// `--dart-define=XPENSE_FIRESTORE_EMULATOR=host:port` points Firestore at
/// the emulator suite (`firebase/firebase.json`: `127.0.0.1:8280`). Dev
/// builds only, and implied there by [authEmulatorDefine]; the `emulators`
/// environment uses it by default.
const String firestoreEmulatorDefine = String.fromEnvironment(
  'XPENSE_FIRESTORE_EMULATOR',
);

/// `--dart-define=XPENSE_SERVER_URL=https://…` is the base address of the
/// `xpense-agent` service (ARCHITECTURE 4.1). Without it, invites and joins
/// report the server as unavailable; the `emulators` environment defaults
/// to a server on this Mac.
const String serverUrlDefine = String.fromEnvironment('XPENSE_SERVER_URL');

/// The Auth emulator, Firestore emulator and server of the `emulators`
/// environment when no define overrides them: the ports of
/// `firebase/firebase.json` and the server's default port.
const String defaultAuthEmulator = '127.0.0.1:9099';

/// See [defaultAuthEmulator].
const String defaultFirestoreEmulator = '127.0.0.1:8280';

/// See [defaultAuthEmulator].
const String defaultLocalServer = 'http://127.0.0.1:8080/';

/// `--dart-define=XPENSE_FAKE_AUTH=signed_out` starts the `fakes`
/// environment signed out, to show onboarding. By default the fake is
/// signed in, so a clean checkout opens on Home.
const String fakeAuthDefine = String.fromEnvironment('XPENSE_FAKE_AUTH');

/// `--dart-define=XPENSE_FAKE_HOUSEHOLD=none` starts the `fakes`
/// environment signed in but without a household, to show household setup.
const String fakeHouseholdDefine = String.fromEnvironment(
  'XPENSE_FAKE_HOUSEHOLD',
);

String _or(String value, String fallback) => value.isEmpty ? fallback : value;

/// The feature flags for [environment]: Remote Config in dev and prod, the
/// local defaults (all off) in `fakes` and `emulators` (Remote Config has
/// no emulator, and the demo project has none).
Future<FeatureFlagSource> connectFeatureFlags(
  AppEnvironment environment,
) async => switch (environment) {
  AppEnvironment.dev ||
  AppEnvironment.prod => await RemoteConfigFeatureFlags.open(),
  AppEnvironment.fakes || AppEnvironment.emulators => FakeFeatureFlags(),
};

/// Which App Check provider iOS uses.
enum AppleAppCheck {
  /// The debug provider; its token is registered per developer in the
  /// console (ENVIRONMENTS 3.8).
  debug,

  /// App Attest, with DeviceCheck before iOS 14.
  appAttest,
}

/// App Attest only in a release build on a device; the debug provider on
/// the simulator and in debug and profile builds. App Attest needs the
/// paid Apple Developer Program, which the team does not have yet
/// (DECISIONS D-39), and never works on the simulator.
AppleAppCheck appleAppCheckFor({
  required bool releaseBuild,
  required bool simulator,
}) =>
    releaseBuild && !simulator ? AppleAppCheck.appAttest : AppleAppCheck.debug;

/// Whether this process runs in the iOS Simulator, which sets
/// `SIMULATOR_UDID` in every app's environment.
bool get runningOnSimulator =>
    Platform.environment.containsKey('SIMULATOR_UDID');

/// The auth repository for [environment].
Future<AuthRepository> connectAuth(AppEnvironment environment) async =>
    switch (environment) {
      AppEnvironment.fakes => FakeAuthRepository(
        signedIn: fakeAuthDefine == 'signed_out'
            ? null
            : FakeAuthRepository.providerUser,
      ),
      AppEnvironment.dev => await FirebaseAuthRepository.connect(
        emulator: authEmulatorDefine,
      ),
      AppEnvironment.prod => await FirebaseAuthRepository.connect(),
      AppEnvironment.emulators => await FirebaseAuthRepository.connect(
        emulator: _or(authEmulatorDefine, defaultAuthEmulator),
      ),
    };

/// The household repository for [environment], following [auth]. In
/// `fakes`, a signed-in person starts in a household (so the app opens on
/// Home) unless [fakeHouseholdDefine] says `none`; signing in later finds
/// no household, as for someone new.
HouseholdRepository connectHouseholds(
  AppEnvironment environment, {
  required AuthRepository auth,
}) => switch (environment) {
  AppEnvironment.fakes => FakeHouseholdRepository(
    membership: auth.currentUser == null
        ? const MembershipUnknown()
        : fakeHouseholdDefine == 'none'
        ? const NoHousehold()
        : const InHousehold(FakeHouseholdRepository.sampleHousehold),
    auth: auth,
  ),
  // A dev build on the Auth emulator also uses the Firestore emulator, so
  // emulator sign-ins never meet the real dev database.
  AppEnvironment.dev => FirebaseHouseholdRepository.connect(
    appCheckToken: FirebaseAppCheck.instance.getToken,
    serverUrl: usableServerUrl(serverUrlDefine),
    emulator: authEmulatorDefine.isEmpty
        ? firestoreEmulatorDefine
        : _or(firestoreEmulatorDefine, defaultFirestoreEmulator),
  ),
  AppEnvironment.prod => FirebaseHouseholdRepository.connect(
    appCheckToken: FirebaseAppCheck.instance.getToken,
    serverUrl: usableServerUrl(serverUrlDefine),
  ),
  // App Check cannot be emulated; the local server accepts any non-empty
  // token (XPENSE_APP_CHECK=emulator), so the request shape stays the same.
  AppEnvironment.emulators => FirebaseHouseholdRepository.connect(
    appCheckToken: () async => 'emulator',
    serverUrl: usableServerUrl(_or(serverUrlDefine, defaultLocalServer)),
    emulator: _or(firestoreEmulatorDefine, defaultFirestoreEmulator),
  ),
};

/// The accounts repository for [environment], following [households]. In
/// `fakes` it holds the artboards' household (WP-13).
AccountsRepository connectAccounts(
  AppEnvironment environment, {
  required HouseholdRepository households,
}) => switch (environment) {
  AppEnvironment.fakes => FakeAccountsRepository.sample(),
  // Firestore is already pointed at the emulator by connectHouseholds.
  AppEnvironment.dev || AppEnvironment.prod || AppEnvironment.emulators =>
    FirebaseAccountsRepository.connect(households: households),
};

/// The crash sink the two error handlers write to.
///
/// It keeps the last [capacity] errors in memory and prints them in debug
/// builds. It cannot throw. Crashlytics joins here once Firebase exists
/// (WP-83); this sink stays first so a crash before Firebase is not lost.
final class ErrorLog {
  /// Creates a log that keeps the last [capacity] entries.
  new({this.capacity = 50});

  /// How many entries are kept.
  final int capacity;

  final Queue<String> _entries = Queue();

  /// The kept entries, oldest first.
  List<String> get entries => List.unmodifiable(_entries);

  /// Records [error] with its [stack].
  void record(Object error, StackTrace? stack) {
    final entry = '${unwrapProviderException(error)}\n${stack ?? ''}';
    _entries.addLast(entry);
    while (_entries.length > capacity) {
      _entries.removeFirst();
    }
    if (kDebugMode) debugPrint(entry);
  }
}

/// Returns the error a Riverpod provider threw, instead of the
/// `ProviderException` wrapper Riverpod 3 rethrows it in.
Object unwrapProviderException(Object error) {
  var current = error;
  while (current is ProviderException) {
    current = current.exception;
  }
  return current;
}

/// Installs the two global error handlers (no zone). Call first in `main`,
/// before anything that can throw.
void installErrorHandlers(ErrorLog log) {
  // Errors inside Flutter's build, layout and paint callbacks.
  FlutterError.onError = (details) {
    try {
      FlutterError.presentError(details);
      log.record(details.exception, details.stack);
    } on Object catch (_) {
      // An error handler must never throw: that would recurse into itself.
    }
  };
  // Uncaught asynchronous errors outside the framework's callbacks.
  PlatformDispatcher.instance.onError = (error, stack) {
    try {
      log.record(error, stack);
    } on Object catch (_) {
      // An error handler must never throw: that would recurse into itself.
    }
    // Always handled: returning false hands the error to the embedder,
    // which may end the process.
    return true;
  };
}

/// Everything `runApp` needs, built by [bootstrap].
final class Bootstrapped {
  /// Creates the result.
  const new({required this.overrides});

  /// Provider overrides for the root `ProviderScope`.
  final List<Override> overrides;
}

/// Builds the real dependencies, in the startup order of ARCHITECTURE 3.3:
/// Firebase, App Check, then settings, theme and glass restore, all before
/// the first frame. Post-frame work is started by `XpenseApp`.
Future<Bootstrapped> bootstrap({required AppEnvironment environment}) async {
  if (environment == AppEnvironment.emulators) {
    // No config file is bundled (copy_firebase_config.sh copies none), so
    // the default app is made here with demo options.
    await Firebase.initializeApp(
      name: defaultFirebaseAppName,
      demoProjectId: emulatorProjectId,
    );
  } else if (environment.usesFirebase) {
    // The config files come from WP-01; without them this throws, which is
    // the right failure for a dev or prod build.
    await Firebase.initializeApp();
  }
  if (environment.usesAppCheck) {
    await FirebaseAppCheck.instance.activate(
      providerApple: switch (appleAppCheckFor(
        releaseBuild: kReleaseMode,
        simulator: runningOnSimulator,
      )) {
        AppleAppCheck.debug => const AppleDebugProvider(),
        AppleAppCheck.appAttest =>
          const AppleAppAttestWithDeviceCheckFallbackProvider(),
      },
    );
  }

  final auth = await connectAuth(environment);
  final households = connectHouseholds(environment, auth: auth);
  final accounts = connectAccounts(environment, households: households);
  final flags = await connectFeatureFlags(environment);
  registerFontLicenses();
  final settings = await PrefsSettingsStore.open();
  await GlassSetup.initialize();
  final glass = await GlassController.start();
  GlassFrameBudget(glass).attach();

  return Bootstrapped(
    overrides: appOverrides(
      clock: const Clock(),
      settings: settings,
      biometricLock: LocalAuthBiometricLock(),
      glass: glass,
      authRepository: auth,
      householdRepository: households,
      accountsRepository: accounts,
      featureFlags: flags,
    ),
  );
}

/// The overrides that wire every service seam.
///
/// [bootstrap] passes the real phone-local services; tests pass fakes.
/// Remote and AI services stay fakes until their packages land: the agent
/// (WP-34), Decisions (WP-33), speech (WP-40), OCR (WP-41), the on-device
/// model (WP-70) and the Keychain store (first package with a secret).
List<Override> appOverrides({
  required Clock clock,
  required SettingsStore settings,
  required BiometricLock biometricLock,
  required GlassController glass,
  required AuthRepository authRepository,
  required HouseholdRepository householdRepository,
  required AccountsRepository accountsRepository,
  SecureStore? secureStore,
  FeatureFlagSource? featureFlags,
  AgentClient? agentClient,
  DecisionsClient? decisionsClient,
  OnDeviceLlm? onDeviceLlm,
  SpeechCapture? speechCapture,
  OcrEngine? ocrEngine,
}) => [
  clockProvider.overrideWithValue(clock),
  settingsStoreProvider.overrideWithValue(settings),
  biometricLockProvider.overrideWithValue(biometricLock),
  glassControllerProvider.overrideWithValue(glass),
  authRepositoryProvider.overrideWithValue(authRepository),
  householdRepositoryProvider.overrideWithValue(householdRepository),
  accountsRepositoryProvider.overrideWithValue(accountsRepository),
  secureStoreProvider.overrideWithValue(secureStore ?? MemorySecureStore()),
  featureFlagSourceProvider.overrideWithValue(
    featureFlags ?? FakeFeatureFlags(),
  ),
  agentClientProvider.overrideWithValue(agentClient ?? FakeAgentClient()),
  decisionsClientProvider.overrideWithValue(
    decisionsClient ?? FakeDecisionsClient(),
  ),
  onDeviceLlmProvider.overrideWithValue(onDeviceLlm ?? FakeOnDeviceLlm()),
  speechCaptureProvider.overrideWithValue(speechCapture ?? FakeSpeechCapture()),
  ocrEngineProvider.overrideWithValue(ocrEngine ?? FakeOcrEngine()),
];
