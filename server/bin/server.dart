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

import 'package:genkit/genkit.dart';
import 'package:http/http.dart' as http_client;
import 'package:logging/logging.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;

import 'package:xpense_agent/admin/emulator_app_check.dart';
import 'package:xpense_agent/admin/firebase_admin_gateway.dart';
import 'package:xpense_agent/admin/firestore_household_source.dart';
import 'package:xpense_agent/catalog/xpense_catalog_loader.dart';
import 'package:xpense_agent/config/runtime_config.dart';
import 'package:xpense_agent/config/server_env.dart';
import 'package:xpense_agent/decide/classifier.dart';
import 'package:xpense_agent/decide/decisions_api.dart';
import 'package:xpense_agent/decide/decisions_classifier.dart';
import 'package:xpense_agent/decide/fallback.dart';
import 'package:xpense_agent/genkit.dart';
import 'package:xpense_agent/runtime/agent.dart';
import 'package:xpense_agent/runtime/firestore_household_reader.dart';
import 'package:xpense_agent/telemetry/otel.dart';
import 'package:xpense_agent/telemetry/structured_log.dart';
import 'package:xpense_agent/telemetry/usage_counters.dart';
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
  final AgentFactory? agent;
  try {
    agent = env.role == XpenseRole.agent
        ? await _agentFactory(env, ai, admin)
        : null;
  } on ServerEnvError catch (e) {
    _log.shout(e.message);
    exitCode = 78; // EX_CONFIG
    return;
  }
  // The day's rate, so `/decide` also finds an entry saved converted.
  final rates = FirestoreHouseholdReader(admin.firestore);
  final server = XpenseServer.create(
    role: env.role,
    ai: ai,
    gateway: admin.gateway,
    projectId: env.projectId,
    agent: agent,
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
            usdIqdOn: (hid, day) async =>
                (await rates.fxRateOn(hid, day))?.usdIqd,
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

/// Builds the agent runtime from the server's classifier, config loader
/// and usage counters.
typedef AgentFactory = XpenseAgentRuntime Function(
  EntryClassifier classifier,
  RuntimeConfigLoader config,
  UsageCounters usage,
);

/// The agent runtime (WP-32).
///
/// - Household data and sessions in Firestore (the emulator locally, the
///   project on Cloud Run); `prepareEntries` classifies through the
///   `/decide` classifier (WP-33).
/// - `XPENSE_AGENT_DATA=demo` (local only): the demo household from memory,
///   in-memory sessions, `config/runtime` defaults and a classifier that
///   answers "unavailable", so the agent runs without any emulator. The
///   `tryCapture` and `tryQuestion` flows act in that household.
/// - Off Cloud Run the strict prompt is used (`a2ui` validate strict, no
///   repair) unless `XPENSE_A2UI=warn`.
Future<AgentFactory> _agentFactory(
  ServerEnv env,
  Genkit ai,
  FirebaseAdminGateway admin,
) async {
  final vars = Platform.environment;
  final demo = demoDataRequested(vars);
  if (demo && env.onCloudRun) {
    throw ServerEnvError('XPENSE_AGENT_DATA=demo is for local runs only');
  }
  final strict = !env.onCloudRun && vars['XPENSE_A2UI']?.trim() != 'warn';
  final catalogJson = await readCatalogJson();
  XpenseAgentRuntime build(
    EntryClassifier classifier,
    RuntimeConfigLoader config,
    UsageCounters usage,
  ) => XpenseAgentRuntime.create(
    ai: ai,
    catalogJson: catalogJson,
    reader: demo
        ? demoHouseholdReader()
        : FirestoreHouseholdReader(admin.firestore),
    classifier: demo ? FakeEntryClassifier() : classifier,
    config: demo ? () async => RuntimeConfig.defaults : config.current,
    sessions: demo
        ? const MemorySessions()
        : FirestoreSessions(admin.firestore),
    strict: strict,
    usage: demo ? null : usage.today,
    onTurn: demo
        ? null
        : (context, stats) => unawaited(
            usage
                .add(context.hid, {
                  UsageCounter.agentTurns: 1,
                  UsageCounter.inputTokens: stats.inputTokens,
                  UsageCounter.outputTokens: stats.outputTokens,
                  UsageCounter.images: stats.images,
                  UsageCounter.audioSeconds: stats.audioSeconds,
                })
                .catchError(
                  (Object e) => _log.warning('usage not recorded', e),
                ),
          ),
  );

  return build;
}
