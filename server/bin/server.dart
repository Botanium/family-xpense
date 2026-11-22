/// Family Xpense server: one image, two Cloud Run services (D-17).
///
///     XPENSE_ROLE=agent|jobs dart run bin/server.dart
///     genkit start -- dart run bin/server.dart        # with the Developer UI
///
/// See `server/README.md` for the environment variables and local runs, and
/// `server/DEPLOY.md` for Cloud Run.
library;

import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http_client;
import 'package:logging/logging.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;

import 'package:xpense_agent/admin/emulator_app_check.dart';
import 'package:xpense_agent/admin/firebase_admin_gateway.dart';
import 'package:xpense_agent/admin/firestore_household_source.dart';
import 'package:xpense_agent/config/server_env.dart';
import 'package:xpense_agent/decide/decisions_api.dart';
import 'package:xpense_agent/decide/decisions_classifier.dart';
import 'package:xpense_agent/decide/fallback.dart';
import 'package:xpense_agent/genkit.dart';
import 'package:xpense_agent/telemetry/otel.dart';
import 'package:xpense_agent/telemetry/structured_log.dart';
import 'package:xpense_agent/xpense_server.dart';

final _log = Logger('xpense.main');

Future<void> main() async {
  Logger.root.level = Level.INFO;
  Logger.root.onRecord.listen((r) => stdout.writeln(formatLogRecord(r)));

  final ServerEnv env;
  try {
    env = ServerEnv.fromEnvironment(Platform.environment);
  } on ServerEnvError catch (e) {
    _log.shout(e.message);
    exitCode = 78; // EX_CONFIG
    return;
  }

  // Telemetry before Genkit, so the instrumentation wraps every action.
  final telemetry = await startTelemetry(
    otlpEndpoint: env.otlpEndpoint,
    serviceName: env.serviceName,
    serviceVersion: env.serviceVersion,
  );
  final ai = createGenkit(withGoogleAI: env.hasGeminiKey);
  final admin = FirebaseAdminGateway.initialize(
    projectId: env.projectId,
    appCheckOverride: env.appCheckMode == AppCheckMode.emulator
        ? EmulatorAppCheckVerifier()
        : null,
  );
  // `/decide` (WP-33): the Decisions API needs the key itself, over REST.
  // Cloud Run resolves the secret to `latest` when the instance starts.
  final geminiKey =
      Platform.environment['GEMINI_API_KEY'] ??
      Platform.environment['GOOGLE_API_KEY'];
  final server = XpenseServer.create(
    role: env.role,
    ai: ai,
    gateway: admin.gateway,
    projectId: env.projectId,
    classifier: geminiKey == null || geminiKey.isEmpty
        ? null
        : (config, usage) => DecisionsClassifier(
            api: DecisionsApi(
              http: http_client.Client(),
              keys: FixedApiKey(geminiKey),
            ),
            households: FirestoreHouseholdSource(admin.firestore),
            config: config,
            usage: usage,
            fallback: GenkitFallbackClassifier(ai),
          ),
  );

  final http = await shelf_io.serve(
    server.handler,
    InternetAddress.anyIPv4,
    env.port,
    poweredByHeader: null,
  );
  _log.info({
    'message': 'listening on :${http.port}',
    'role': env.role.name,
    'project': env.projectId,
    'appCheck': env.appCheckMode.name,
    'gemini': env.hasGeminiKey,
  });

  // Cloud Run sends SIGTERM and allows 10 s before SIGKILL.
  var stopping = false;
  Future<void> stop(ProcessSignal signal) async {
    if (stopping) return;
    stopping = true;
    _log.info('stopping on $signal');
    await http.close();
    await admin.gateway.close();
    await ai.shutdown();
    await telemetry.shutdown();
    exit(0);
  }

  ProcessSignal.sigterm.watch().listen(stop);
  ProcessSignal.sigint.watch().listen(stop);
}
