/// `xpenseAgent`: the Genkit agent of step 5 (AI_PIPELINE 8).
///
/// The only file that imports `package:genkit/experimental*.dart` (the
/// Agents API is experimental) and `genkit_google_cloud`. It wires:
/// - the Xpense catalog (trimmed agent view, `lib/catalog/`);
/// - the middleware, in order `householdContext` → `outputGuard` →
///   `a2ui(catalog: 'xpense')` → `retry` (declared in the `.prompt` file);
/// - the tools (`lib/tools/`);
/// - `definePromptAgent` over `prompts/xpense_agent.prompt` (production) or
///   `prompts/xpense_agent.strict.prompt` (development and CI);
/// - `FirestoreSessionStore` with the per-member prefix `{hid}_{uid}`
///   (D-11), or an in-memory store for local demo runs;
/// - the route `/v1/agent` and the throwaway flows `tryCapture` and
///   `tryQuestion`.
// The experimental Agents API is accepted here and nowhere else.
// ignore_for_file: experimental_member_use
library;

import 'dart:convert';

import 'package:clock/clock.dart';
import 'package:genkit/experimental.dart';
import 'package:genkit/experimental_io.dart';
import 'package:genkit/genkit.dart';
import 'package:genkit/io.dart';
import 'package:genkit_google_cloud/firestore_session_store.dart';
import 'package:google_cloud_firestore/google_cloud_firestore.dart' as fs;
import 'package:logging/logging.dart';

import 'package:xpense_agent/auth/xpense_context.dart';
import 'package:xpense_agent/catalog/xpense_catalog_loader.dart';
import 'package:xpense_agent/config/runtime_config.dart';
import 'package:xpense_agent/decide/classifier.dart';
import 'package:xpense_agent/runtime/demo_household.dart';
import 'package:xpense_agent/runtime/household_context.dart';
import 'package:xpense_agent/safety/draft_guard.dart' show a2uiMime;
import 'package:xpense_agent/safety/output_guard.dart';
import 'package:xpense_agent/tools/household_reader.dart';
import 'package:xpense_agent/tools/household_snapshot.dart';
import 'package:xpense_agent/tools/local_day.dart';
import 'package:xpense_agent/tools/tool_deps.dart';
import 'package:xpense_agent/tools/xpense_tools.dart';

final _log = Logger('xpense.runtime.agent');

/// Top-level session collection (D-11). Companion collections
/// `agentSessions-pointers` and `agentSessions-shards` are derived by the
/// store.
const agentSessionsCollection = 'agentSessions';

/// The prompt behind the agent.
const agentPromptName = 'xpense_agent';

/// The per-member session prefix: `{hid}_{uid}` (D-11). Throws when the
/// context lacks ids, so a session can never be written under a shared
/// prefix.
String sessionPrefix(Map<String, dynamic>? context) {
  final c = XpenseContext.of(context);
  return '${c.hid}_${c.uid}';
}

/// Where agent sessions are kept.
sealed class AgentSessions {
  const new();
}

/// `FirestoreSessionStore` on [db] (production, emulator).
final class FirestoreSessions extends AgentSessions {
  /// Creates the setting.
  const new(this.db);

  /// The Firestore client.
  final fs.Firestore db;
}

/// In memory (tests and `XPENSE_AGENT_DATA=demo` local runs).
final class MemorySessions extends AgentSessions {
  /// Creates the setting.
  const new();
}

/// In-memory sessions kept apart per `{hid}_{uid}`, like the Firestore
/// layout: `InMemorySessionStore` alone ignores the context, so one member
/// could load another's snapshot by id.
final class TenantMemorySessionStore implements SessionStore {
  final _stores = <String, InMemorySessionStore>{};

  InMemorySessionStore _for(Map<String, dynamic>? context) =>
      _stores.putIfAbsent(sessionPrefix(context), InMemorySessionStore.new);

  @override
  Future<SessionSnapshot?> getSnapshot({
    String? snapshotId,
    String? sessionId,
    Map<String, dynamic>? context,
  }) => _for(
    context,
  ).getSnapshot(snapshotId: snapshotId, sessionId: sessionId, context: context);

  @override
  Future<String?> saveSnapshot(
    String? snapshotId,
    SnapshotMutator mutator, {
    Map<String, dynamic>? context,
  }) => _for(context).saveSnapshot(snapshotId, mutator, context: context);
}

/// The assembled agent and its collaborators.
final class XpenseAgentRuntime {
  new _({
    required this.agent,
    required this.deps,
    required this.strict,
    required this.tryCapture,
    required this.tryQuestion,
  });

  /// Builds the runtime on [ai].
  ///
  /// [strict] selects `xpense_agent.strict.prompt` (`validate: 'strict',
  /// repair: false`). [modelName] maps `config/runtime` model ids to
  /// registered models (tests register a scripted model). [onTurn] observes
  /// each finished turn (usage counters).
  static Future<XpenseAgentRuntime> create({
    required Genkit ai,
    required HouseholdReader reader,
    required EntryClassifier classifier,
    required Future<RuntimeConfig> Function() config,
    required AgentSessions sessions,
    bool strict = true,
    ModelNamer modelName = googleAiModel,
    Clock clock = const Clock(),
    void Function(XpenseContext context, GenerateResult<dynamic> result)?
    onTurn,
  }) async {
    await registerXpenseCatalog(ai);
    final snapshots = HouseholdSnapshots(reader, clock: clock);
    final deps = ToolDeps(
      reader: reader,
      snapshots: snapshots,
      classifier: classifier,
      thresholds: () async => (await config()).confidence,
      turnText: () =>
          conversationTexts(ai.currentSession<dynamic>()?.getMessages()),
      clock: clock,
    );
    defineHouseholdContext(
      ai,
      snapshots: snapshots,
      config: config,
      modelName: modelName,
      clock: clock,
      onTurn: onTurn,
    );
    defineOutputGuard(ai);
    defineXpenseTools(ai, deps);

    final store = switch (sessions) {
      FirestoreSessions(:final db) => FirestoreSessionStore(
        db: db,
        collection: agentSessionsCollection,
        snapshotPathPrefix: sessionPrefix,
      ) as SessionStore,
      MemorySessions() => TenantMemorySessionStore(),
    };
    final agent = ai.definePromptAgent<void>(
      promptName: strict ? '$agentPromptName.strict' : agentPromptName,
      store: store,
    );
    _log.info({
      'message': 'agent ready',
      'prompt': strict ? '$agentPromptName.strict' : agentPromptName,
      'sessions': sessions.runtimeType.toString(),
    });

    final tryCapture = _defineTryFlow(ai, agent, 'tryCapture');
    final tryQuestion = _defineTryFlow(ai, agent, 'tryQuestion');
    return XpenseAgentRuntime._(
      agent: agent,
      deps: deps,
      strict: strict,
      tryCapture: tryCapture,
      tryQuestion: tryQuestion,
    );
  }

  /// The agent action.
  final Agent<void> agent;

  /// The tools' collaborators.
  final ToolDeps deps;

  /// Whether the strict (development) prompt is in use.
  final bool strict;

  /// Throwaway flow: one capture turn as the demo member.
  final Flow<String, Map<String, dynamic>, void, void> tryCapture;

  /// Throwaway flow: one question turn as the demo member.
  final Flow<String, Map<String, dynamic>, void, void> tryQuestion;

  /// Mounts the agent on [router] at [path] (plus its `/getSnapshot` and
  /// `/abort` companions) behind [contextProvider].
  void mount(
    GenkitRouter router, {
    required String path,
    required ContextProvider contextProvider,
  }) => router.addAgent(agent, path: path, contextProvider: contextProvider);

  /// Runs one turn in process as the member in [context] (flows, tests).
  Future<Map<String, dynamic>> runTurn(
    String text, {
    required Map<String, dynamic> context,
    String? snapshotId,
  }) async {
    final chat = snapshotId == null
        ? agent.chat()
        : await agent.loadChat(snapshotId: snapshotId, context: context);
    final res = await chat.send(text: text, context: context);
    return turnSummary(res.message, snapshotId: res.snapshotId);
  }
}

/// Throwaway flows so the agent can be driven with `genkit flow:run`
/// (agents are not flows). They act as the demo member of the demo
/// household; with Firestore data they need that household seeded.
Flow<String, Map<String, dynamic>, void, void> _defineTryFlow(
  Genkit ai,
  Agent<void> agent,
  String name,
) => ai.defineFlow(
  name: name,
  inputSchema: .string(),
  outputSchema: .map(.string(), .dynamicSchema()),
  fn: (text, _) async {
    final res = await agent.chat().send(text: text, context: demoContext);
    return turnSummary(res.message, snapshotId: res.snapshotId);
  },
);

/// A compact view of a turn's reply: prose, tool calls and the A2UI
/// messages.
Map<String, dynamic> turnSummary(Message? message, {String? snapshotId}) {
  final parts = message?.content ?? const <Part>[];
  return {
    'snapshotId': ?snapshotId,
    'text': [
      for (final p in parts)
        if (p.text case final t? when t.trim().isNotEmpty) t.trim(),
    ].join('\n'),
    'a2ui': [
      for (final p in parts)
        if (p.metadata?['mimeType'] == a2uiMime)
          ...?(p.data?['messages'] as List?),
    ],
  };
}

/// The user texts of a conversation, oldest first: text parts, plus the
/// context of A2UI actions (a typed answer travels there).
List<String> conversationTexts(List<Message>? messages) => [
  for (final m in messages ?? const <Message>[])
    if (m.role == Role.user)
      for (final p in m.content)
        if (p.text case final t? when t.isNotEmpty)
          t
        else if (p.metadata?['mimeType'] == a2uiMime && p.data != null)
          jsonEncode(p.data),
];

/// The demo-data setting for local runs: `XPENSE_AGENT_DATA=demo` serves
/// the demo household from memory, with in-memory sessions.
bool demoDataRequested(Map<String, String> env) =>
    env['XPENSE_AGENT_DATA']?.trim() == 'demo';

/// A reader of the demo household, dated around today in Baghdad.
HouseholdReader demoHouseholdReader({Clock clock = const Clock()}) =>
    demoReader(localToday(clock, 'Asia/Baghdad').iso);
