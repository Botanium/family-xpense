// The composition root (ARCHITECTURE 3.3): the one place that names
// concrete implementations. Features see only the throwing providers in
// `lib/services/`; this file overrides them.
import 'dart:collection';

import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/misc.dart';

import 'package:xpense_app/app.dart';
import 'package:xpense_app/core/theme/theme.dart';
import 'package:xpense_app/core/ui/ui.dart';
import 'package:xpense_app/data/auth_repository.dart';
import 'package:xpense_app/data/auth_repository_fake.dart';
import 'package:xpense_app/data/auth_repository_firebase.dart';
import 'package:xpense_app/services/agent_client.dart';
import 'package:xpense_app/services/agent_client_fake.dart';
import 'package:xpense_app/services/biometric_lock.dart';
import 'package:xpense_app/services/biometric_lock_local_auth.dart';
import 'package:xpense_app/services/clock.dart';
import 'package:xpense_app/services/decisions_client.dart';
import 'package:xpense_app/services/decisions_client_fake.dart';
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
  prod;

  /// The `--dart-define` key that picks the environment.
  static const String defineKey = 'XPENSE_ENV';

  /// The environment this build was compiled for.
  static AppEnvironment get compiled =>
      fromName(const String.fromEnvironment(defineKey));

  /// Parses [name]; anything unknown, including empty, is [fakes].
  static AppEnvironment fromName(String name) =>
      values.asNameMap()[name] ?? fakes;

  /// Whether startup initialises Firebase and App Check.
  bool get usesFirebase => this != fakes;
}

/// `--dart-define=XPENSE_AUTH_EMULATOR=host:port` points Firebase Auth at
/// the emulator suite (`firebase/firebase.json`: `localhost:9099`). Dev
/// builds only; ignored in prod.
const String authEmulatorDefine = String.fromEnvironment(
  'XPENSE_AUTH_EMULATOR',
);

/// `--dart-define=XPENSE_FAKE_AUTH=signed_out` starts the `fakes`
/// environment signed out, to show onboarding. By default the fake is
/// signed in, so a clean checkout opens on Home.
const String fakeAuthDefine = String.fromEnvironment('XPENSE_FAKE_AUTH');

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
  if (environment.usesFirebase) {
    // The config files come from WP-01; without them this throws, which is
    // the right failure for a dev or prod build.
    await Firebase.initializeApp();
    await FirebaseAppCheck.instance.activate(
      providerApple: kDebugMode
          ? const AppleDebugProvider()
          : const AppleAppAttestWithDeviceCheckFallbackProvider(),
    );
  }

  final auth = await connectAuth(environment);
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
  SecureStore? secureStore,
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
  secureStoreProvider.overrideWithValue(secureStore ?? MemorySecureStore()),
  agentClientProvider.overrideWithValue(agentClient ?? FakeAgentClient()),
  decisionsClientProvider.overrideWithValue(
    decisionsClient ?? FakeDecisionsClient(),
  ),
  onDeviceLlmProvider.overrideWithValue(onDeviceLlm ?? FakeOnDeviceLlm()),
  speechCaptureProvider.overrideWithValue(speechCapture ?? FakeSpeechCapture()),
  ocrEngineProvider.overrideWithValue(ocrEngine ?? FakeOcrEngine()),
];
