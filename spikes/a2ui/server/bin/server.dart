// WP-S1 spike server (throwaway, never merged into server/).
//
// A Genkit Dart agent with the a2ui() middleware and the spike catalog loaded
// from JSON, served over HTTP for the Flutter client in ../client.
//
//   genkit start -- dart run bin/server.dart
//
// Model: when GEMINI_API_KEY is set, gemini-3.5-flash-lite; otherwise a
// scripted model that streams fixed Express text. Either way the text goes
// through the real a2ui() middleware, so the compiled messages are genuine.
//
// Store (SPIKE_STORE): memory (default) | prefix | nested. prefix and nested
// need FIRESTORE_EMULATOR_HOST and GOOGLE_CLOUD_PROJECT.
// ignore_for_file: experimental_member_use
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:genkit/experimental.dart';
import 'package:genkit/experimental_io.dart';
import 'package:genkit/genkit.dart';
import 'package:genkit/io.dart';
import 'package:genkit_a2ui/a2ui.dart';
import 'package:genkit_google_cloud/firestore_session_store.dart';
import 'package:genkit_google_genai/genkit_google_genai.dart';
import 'package:google_cloud_firestore/google_cloud_firestore.dart';

import 'package:wp_s1_server/household_store.dart';
import 'package:wp_s1_server/scripted_model.dart';

const catalogLookupId = 'xpense-spike';

Future<void> main() async {
  final hasKey = (Platform.environment['GEMINI_API_KEY'] ?? '').isNotEmpty;
  final ai = Genkit(plugins: [if (hasKey) googleAI(), A2uiPlugin()]);

  // 1. Catalog from JSON, registered before any turn.
  await loadCatalog(
    ai,
    id: catalogLookupId,
    file: '../catalog/spike_catalog.json',
  );

  // 2. Scripted model, used when there is no key.
  final scripted = defineScriptedModel(ai);

  // 3. Q6: a generate middleware that reads the request context.
  final householdContext = ai.defineGenerateMiddleware<void>(
    name: 'householdContext',
    create: (config, ctx) => HouseholdContextMiddleware(),
  );

  final store = _storeFromEnv();
  stdout.writeln(
    '[spike] store: ${store.runtimeType}, model: '
    '${hasKey ? 'gemini' : 'scripted'}',
  );

  final agent = ai.defineAgent(
    name: 'spikeAgent',
    model: hasKey
        ? googleAI.gemini('gemini-3.5-flash-lite')
        : modelRef(scripted.name),
    system:
        'You are the Family Xpense spike agent. Render money entries with '
        'EntryList bound to \$/drafts. Keep prose to one short sentence.',
    use: [
      householdContext(),
      a2ui(catalog: catalogLookupId, validate: 'strict', repair: false),
    ],
    store: store,
  );

  // A flow wrapper so `genkit flow:run` and the genkit MCP can drive one turn
  // in process and produce a trace (agents themselves are not flows).
  ai.defineFlow(
    name: 'trySpikeAgent',
    fn: (String message, _) async {
      final res = await agent.chat().send(
        text: message,
        context: {'hid': 'hh_demo', 'uid': 'u_owner', 'householdName': 'Demo'},
      );
      return jsonEncode(res.message?.toJson());
    },
  );

  final router = GenkitRouter()
    ..addAgent(
      agent,
      path: '/api/spikeAgent',
      // The real server verifies the ID token here (WP-04). The spike reads
      // two headers so the household-scoped paths can be exercised.
      contextProvider: (req) async => {
        'hid': req.headers['x-spike-hid'] ?? 'hh_demo',
        'uid': req.headers['x-spike-uid'] ?? 'u_owner',
        'householdName': req.headers['x-spike-household-name'] ?? 'Demo',
      },
    );
  final port = int.parse(Platform.environment['PORT'] ?? '8080');
  await router.serve(port: port, cors: const CorsOptions());
  stdout.writeln('[spike] serving on :$port/api/spikeAgent');
}

SessionStore _storeFromEnv() {
  final mode = Platform.environment['SPIKE_STORE'] ?? 'memory';
  Firestore db() => Firestore(
    settings: Settings(projectId: Platform.environment['GOOGLE_CLOUD_PROJECT']),
  );
  return switch (mode) {
    // D-11 as written: top-level collections, per-household per-member prefix.
    'prefix' => FirestoreSessionStore(
      db: db(),
      collection: 'agentSessions',
      snapshotPathPrefix: (ctx) => '${ctx?['hid']}_${ctx?['uid']}',
    ),
    // Nested under households/{hid}: one store per household.
    'nested' => HouseholdSessionStore(db()),
    _ => InMemorySessionStore(),
  };
}

/// Injects a per-household system block from the request context.
class HouseholdContextMiddleware extends GenerateMiddleware {
  @override
  Future<ModelResponse> model(
    ModelRequest request,
    ActionFnArg<ModelResponseChunk, ModelRequest, void> ctx,
    Future<ModelResponse> Function(
      ModelRequest request,
      ActionFnArg<ModelResponseChunk, ModelRequest, void> ctx,
    )
    next,
  ) {
    final c = ctx.context ?? const {};
    stdout.writeln('[householdContext] ctx.context keys: ${c.keys.toList()}');
    final block =
        '<<<household\nhid: ${c['hid']}\nmember: ${c['uid']}\n'
        'name: ${c['householdName']}\nbaseCurrency: USD\nhousehold>>>';
    final messages = [...request.messages];
    final i = messages.indexWhere((m) => m.role == Role.system);
    if (i >= 0) {
      messages[i] = Message(
        role: Role.system,
        content: [
          ...messages[i].content,
          TextPart(text: '\n\n$block'),
        ],
        metadata: messages[i].metadata,
      );
    } else {
      messages.insert(
        0,
        Message(
          role: Role.system,
          content: [TextPart(text: block)],
        ),
      );
    }
    return next(
      ModelRequest(
        messages: messages,
        config: request.config,
        tools: request.tools,
        toolChoice: request.toolChoice,
        output: request.output,
        docs: request.docs,
      ),
      ctx,
    );
  }
}
