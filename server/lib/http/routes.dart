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
import 'package:xpense_agent/decide/decide_flow.dart';
import 'package:xpense_agent/household/household_flows.dart';
import 'package:xpense_agent/telemetry/usage_counters.dart';

/// The version prefix of the public routes (D-32). Tied to the Xpense
/// catalog version: a breaking catalog change ships as `/v2`.
const publicPrefix = '/v1';

/// Public routes for `xpense-agent`, mounted under [publicPrefix].
///
/// The household routes do no AI work, so they consume no usage counters and
/// admit On-device members; `/household/join` is open to a signed-in user
/// without a household, which is who joins (WP-12).
GenkitRouter buildPublicRouter({
  required XpenseContextProvider auth,
  required Flow<String?, Map<String, String>, void, void> ping,
  required DecideFlow decide,
  required HouseholdFlow householdInvite,
  required HouseholdFlow householdJoin,
}) => GenkitRouter()
  ..addAction(ping, path: '/ping', contextProvider: auth.forRoute())
  // The Decisions proxy (WP-33): refused at the daily `decisions` limit.
  ..addAction(
    decide,
    path: '/decide',
    contextProvider: auth.forRoute(meters: {UsageCounter.decisions}),
  )
  ..addAction(
    householdInvite,
    path: '/household/invite',
    contextProvider: auth.forRoute(allowOnDevice: true),
  )
  ..addAction(
    householdJoin,
    path: '/household/join',
    contextProvider: auth.forSignedInUser(),
  );

/// Private routes for `xpense-jobs`, mounted at the root. Cloud Run IAM is the
/// gate (only the scheduler and Eventarc service accounts may invoke the
/// service), so no context provider is attached. Empty until the jobs
/// packages add their actions.
GenkitRouter buildJobsRouter() => GenkitRouter();
