/// The Genkit routes each role serves.
///
/// Later packages add their actions here: the agent (`addAgent` from
/// `lib/runtime/`), `/decide`, `/household/*`, `/account/*` on the public
/// router; `/jobs/*` and `/events/*` on the jobs router. Every public route
/// takes a context provider from [XpenseContextProvider.forRoute], naming the
/// usage counters it consumes.
library;

import 'package:genkit/genkit.dart';
import 'package:genkit/io.dart';

import 'package:xpense_agent/auth/context_provider.dart';
import 'package:xpense_agent/runtime/agent.dart';
import 'package:xpense_agent/telemetry/usage_counters.dart';

/// The version prefix of the public routes (D-32). Tied to the Xpense
/// catalog version: a breaking catalog change ships as `/v2`.
const publicPrefix = '/v1';

/// Public routes for `xpense-agent`, mounted under [publicPrefix].
///
/// `/agent` (WP-32) is the agent turn route plus its `/agent/getSnapshot`
/// and `/agent/abort` companions; it consumes `agentTurns`.
GenkitRouter buildPublicRouter({
  required XpenseContextProvider auth,
  required Flow<String?, Map<String, String>, void, void> ping,
  XpenseAgentRuntime? agent,
}) {
  final router = GenkitRouter()
    ..addAction(ping, path: '/ping', contextProvider: auth.forRoute());
  agent?.mount(
    router,
    path: '/agent',
    contextProvider: auth.forRoute(meters: {UsageCounter.agentTurns}),
  );
  return router;
}

/// Private routes for `xpense-jobs`, mounted at the root. Cloud Run IAM is the
/// gate (only the scheduler and Eventarc service accounts may invoke the
/// service), so no context provider is attached. Empty until the jobs
/// packages add their actions.
GenkitRouter buildJobsRouter() => GenkitRouter();
