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
import 'package:logging/logging.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;

import 'package:xpense_agent/admin/emulator_app_check.dart';
import 'package:xpense_agent/admin/firebase_admin_gateway.dart';
import 'package:xpense_agent/config/runtime_config.dart';
import 'package:xpense_agent/config/server_env.dart';
import 'package:xpense_agent/decide/classifier.dart';
import 'package:xpense_agent/genkit.dart';
import 'package:xpense_agent/runtime/agent.dart';
import 'package:xpense_agent/runtime/firestore_household_reader.dart';
import 'package:xpense_agent/telemetry/otel.dart';
import 'package:xpense_agent/telemetry/structured_log.dart';
import 'package:xpense_agent/telemetry/usage_counters.dart';
import 'package:xpense_agent/xpense_server.dart';

final _log = Logger('xpense.main');

late final Genkit _ai;

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
  _ai = ai;
  final admin = FirebaseAdminGateway.initialize(
    projectId: env.projectId,
    appCheckOverride: env.appCheckMode == AppCheckMode.emulator
        ? EmulatorAppCheckVerifier()
        : null,
  );
  final agent = env.role == XpenseRole.agent
      ? await _createAgent(env, admin)
      : null;
  final server = XpenseServer.create(
    role: env.role,
    ai: ai,
    gateway: admin.gateway,
    projectId: env.projectId,
    agent: agent,
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

/// Builds the agent runtime (WP-32).
///
/// - `XPENSE_AGENT_DATA=demo` (local only): the demo household from memory
///   and in-memory sessions, so the agent runs without the Firestore
///   emulator. The `tryCapture` and `tryQuestion` flows act in it.
/// - Otherwise: household data and sessions in Firestore (the emulator
///   locally, the project on Cloud Run).
/// - Off Cloud Run the strict prompt is used (`a2ui` validate strict, no
///   repair) unless `XPENSE_A2UI=warn`.
///
/// Classification goes through WP-33's `EntryClassifier`; until the real
/// classifier is merged it is the fake, which answers "unavailable", so
/// drafts ask for what the words leave open.
Future<XpenseAgentRuntime> _createAgent(
  ServerEnv env,
  FirebaseAdminGateway admin,
) async {
  final vars = Platform.environment;
  final demo = demoDataRequested(vars);
  if (demo && env.onCloudRun) {
    throw ServerEnvError('XPENSE_AGENT_DATA=demo is for local runs only');
  }
  final strict = !env.onCloudRun && vars['XPENSE_A2UI']?.trim() != 'warn';
  final config = RuntimeConfigLoader(admin.gateway.documents);
  final usage = UsageCounters(admin.gateway.documents);
  return await XpenseAgentRuntime.create(
    ai: _ai,
    reader: demo
        ? demoHouseholdReader()
        : FirestoreHouseholdReader(admin.firestore),
    classifier: FakeEntryClassifier(),
    config: demo ? () async => RuntimeConfig.defaults : config.current,
    sessions: demo
        ? const MemorySessions()
        : FirestoreSessions(admin.firestore),
    strict: strict,
    onTurn: demo
        ? null
        : (context, result) => unawaited(
            usage
                .add(context.hid, {
                  UsageCounter.agentTurns: 1,
                  UsageCounter.inputTokens: result.usage?.inputTokens ?? 0,
                  UsageCounter.outputTokens: result.usage?.outputTokens ?? 0,
                })
                .catchError(
                  (Object e) => _log.warning('usage not recorded', e),
                ),
          ),
  );
}
