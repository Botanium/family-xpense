/// Composition root: wires the gateway, the context provider, the flows and
/// the routes into one request handler. `bin/server.dart` supplies the real
/// gateway and Genkit instance; tests supply fakes.
library;

import 'package:clock/clock.dart';
import 'package:genkit/genkit.dart';
import 'package:shelf/shelf.dart';

import 'package:xpense_agent/admin/admin_gateway.dart';
import 'package:xpense_agent/auth/context_provider.dart';
import 'package:xpense_agent/auth/member_directory.dart';
import 'package:xpense_agent/config/runtime_config.dart';
import 'package:xpense_agent/config/server_env.dart';
import 'package:xpense_agent/decide/classifier.dart';
import 'package:xpense_agent/decide/decide_flow.dart';
import 'package:xpense_agent/flows/ping.dart';
import 'package:xpense_agent/http/routes.dart';
import 'package:xpense_agent/http/server_app.dart';
import 'package:xpense_agent/telemetry/usage_counters.dart';

/// The assembled service.
final class XpenseServer {
  new _({
    required this.handler,
    required this.auth,
    required this.members,
    required this.config,
    required this.usage,
    required this.classifier,
  });

  /// Builds the service for [role] on [ai] and [gateway].
  ///
  /// [classifier] builds the `/decide` classifier from the config loader and
  /// the usage counters; without it (tests, a server with no Gemini key)
  /// `/decide` answers `{unavailable: true}`.
  factory create({
    required XpenseRole role,
    required Genkit ai,
    required AdminGateway gateway,
    String? projectId,
    Clock? clock,
    EntryClassifier Function(RuntimeConfigLoader config, UsageCounters usage)?
    classifier,
  }) {
    final members = MemberDirectory(gateway.documents, clock: clock);
    final config = RuntimeConfigLoader(gateway.documents, clock: clock);
    final usage = UsageCounters(gateway.documents, clock: clock);
    final auth = XpenseContextProvider(
      gateway: gateway,
      members: members,
      config: config,
      usage: usage,
    );
    // Flows are defined for both roles so the Developer UI lists the same
    // actions; only the agent role mounts the public router.
    final ping = definePingFlow(ai);
    final entryClassifier =
        classifier?.call(config, usage) ?? FakeEntryClassifier();
    final decide = defineDecideFlow(ai, entryClassifier);
    final handler = buildHandler(
      role: role,
      public: buildPublicRouter(auth: auth, ping: ping, decide: decide),
      jobs: buildJobsRouter(),
      projectId: projectId,
    );
    return XpenseServer._(
      handler: handler,
      auth: auth,
      members: members,
      config: config,
      usage: usage,
      classifier: entryClassifier,
    );
  }

  /// The Shelf handler to serve.
  final Handler handler;

  /// The context provider (for routes added by later packages).
  final XpenseContextProvider auth;

  /// The member directory and its cache.
  final MemberDirectory members;

  /// The `config/runtime` loader.
  final RuntimeConfigLoader config;

  /// The usage counters.
  final UsageCounters usage;

  /// The `/decide` classifier, for the agent's `prepareEntries` (WP-32).
  final EntryClassifier classifier;
}
