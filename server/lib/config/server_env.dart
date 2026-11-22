/// Process settings from environment variables, checked once at startup.
library;

import 'package:meta/meta.dart';

/// Which routes this instance serves (D-17: one image, two services).
enum XpenseRole {
  /// `xpense-agent`: public, token-verified routes under `/v1`.
  agent,

  /// `xpense-jobs`: IAM-private `/jobs/*` and `/events/*`.
  jobs;

  /// Parses `XPENSE_ROLE`.
  static XpenseRole? tryParse(String? value) => switch (value?.trim()) {
    'agent' => agent,
    'jobs' => jobs,
    _ => null,
  };
}

/// How App Check tokens are verified.
enum AppCheckMode {
  /// Verified with the App Check public keys for the project. Always on
  /// Cloud Run.
  enforce,

  /// Any non-empty token is accepted. App Check cannot be emulated, so this
  /// exists for local runs against the Auth emulator only.
  emulator,
}

/// The settings the server reads from its environment.
@immutable
final class ServerEnv {
  /// Creates settings directly (tests).
  const new({
    required this.role,
    required this.port,
    required this.projectId,
    required this.onCloudRun,
    required this.appCheckMode,
    required this.hasGeminiKey,
    this.otlpEndpoint,
    this.serviceName = 'xpense-agent',
    this.serviceVersion = 'dev',
  });

  /// Reads and validates [env] (usually `Platform.environment`).
  ///
  /// Throws [ServerEnvError] when the settings are unsafe or incomplete:
  /// - `XPENSE_ROLE` must be `agent` or `jobs` (required on Cloud Run;
  ///   `agent` locally).
  /// - On Cloud Run (`K_SERVICE` set) the project must be given explicitly
  ///   in `GOOGLE_CLOUD_PROJECT`, and App Check is always enforced.
  /// - Off Cloud Run the project must be a `demo-` project (default
  ///   `demo-xpense`), which the Firebase emulators treat as fake, so a local
  ///   run can never reach a real project.
  factory fromEnvironment(Map<String, String> env) {
    String? read(String key) {
      final value = env[key]?.trim();
      return value == null || value.isEmpty ? null : value;
    }

    final onCloudRun = read('K_SERVICE') != null;
    final roleText = read('XPENSE_ROLE');
    final role =
        XpenseRole.tryParse(roleText) ??
        (roleText == null && !onCloudRun ? XpenseRole.agent : null);
    if (role == null) {
      throw ServerEnvError(
        'XPENSE_ROLE must be "agent" or "jobs" (got ${roleText ?? 'nothing'})',
      );
    }

    final projectId =
        read('GOOGLE_CLOUD_PROJECT') ??
        read('GCLOUD_PROJECT') ??
        (onCloudRun ? null : 'demo-xpense');
    if (projectId == null) {
      throw ServerEnvError(
        'GOOGLE_CLOUD_PROJECT must be set on Cloud Run (see server/DEPLOY.md)',
      );
    }
    if (!onCloudRun && !projectId.startsWith('demo-')) {
      throw ServerEnvError(
        'Local runs must use a demo- project with the emulators '
        '(got "$projectId"). Real projects are reached only from Cloud Run.',
      );
    }

    final appCheckText = read('XPENSE_APP_CHECK') ?? 'enforce';
    final appCheckMode = switch (appCheckText) {
      'enforce' => AppCheckMode.enforce,
      'emulator' => AppCheckMode.emulator,
      _ => throw ServerEnvError(
        'XPENSE_APP_CHECK must be "enforce" or "emulator" '
        '(got "$appCheckText")',
      ),
    };
    if (appCheckMode == AppCheckMode.emulator &&
        (onCloudRun || read('FIREBASE_AUTH_EMULATOR_HOST') == null)) {
      throw ServerEnvError(
        'XPENSE_APP_CHECK=emulator is allowed only off Cloud Run with '
        'FIREBASE_AUTH_EMULATOR_HOST set',
      );
    }

    final portText = read('PORT') ?? '8080';
    final port = int.tryParse(portText);
    if (port == null || port < 0 || port > 65535) {
      throw ServerEnvError('PORT must be a port number (got "$portText")');
    }

    return ServerEnv(
      role: role,
      port: port,
      projectId: projectId,
      onCloudRun: onCloudRun,
      appCheckMode: appCheckMode,
      hasGeminiKey:
          read('GEMINI_API_KEY') != null || read('GOOGLE_API_KEY') != null,
      otlpEndpoint: read('OTEL_EXPORTER_OTLP_ENDPOINT'),
      serviceName: read('K_SERVICE') ?? 'xpense-${role.name}',
      serviceVersion: read('K_REVISION') ?? 'dev',
    );
  }

  /// The routes to mount.
  final XpenseRole role;

  /// The port to listen on (`PORT`, set by Cloud Run; 8080 locally).
  final int port;

  /// The Firebase / Google Cloud project id.
  final String projectId;

  /// Whether the process runs on Cloud Run.
  final bool onCloudRun;

  /// App Check verification mode.
  final AppCheckMode appCheckMode;

  /// Whether a Gemini API key is present.
  final bool hasGeminiKey;

  /// OTLP endpoint for telemetry export, if any.
  final String? otlpEndpoint;

  /// Service name for telemetry.
  final String serviceName;

  /// Service version (Cloud Run revision) for telemetry.
  final String serviceVersion;
}

/// Unsafe or incomplete environment; the server refuses to start.
final class ServerEnvError implements Exception {
  /// Creates the error.
  new(this.message);

  /// What is wrong.
  final String message;

  @override
  String toString() => 'ServerEnvError: $message';
}
