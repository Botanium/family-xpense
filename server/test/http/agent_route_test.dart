// `/v1/agent` over real HTTP: the context provider in front of the agent,
// driven by Genkit's own `remoteAgent` client, with a scripted model.
// ignore_for_file: experimental_member_use
import 'dart:io';

import 'package:clock/clock.dart';
import 'package:genkit/experimental_client.dart';
import 'package:genkit/genkit.dart';
import 'package:genkit_a2ui/a2ui.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:test/test.dart';
import 'package:xpense_agent/catalog/xpense_catalog_loader.dart';
import 'package:xpense_agent/config/runtime_config.dart';
import 'package:xpense_agent/config/server_env.dart';
import 'package:xpense_agent/decide/classifier.dart';
import 'package:xpense_agent/runtime/agent.dart';
import 'package:xpense_agent/runtime/demo_household.dart';
import 'package:xpense_agent/telemetry/usage_counters.dart';
import 'package:xpense_agent/xpense_server.dart';

import '../runtime/scripted_model.dart';
import '../support/fakes.dart';
import '../tools/support.dart';

void main() {
  late Genkit ai;
  late HttpServer http;
  late FakeDocumentStore docs;
  late Script script;

  setUp(() async {
    ai = Genkit(isDevEnv: false, plugins: [A2uiPlugin()], promptDir: 'prompts');
    script = Script(entries: salaryRent, render: scriptedCapture);
    defineScripted(ai, 'test/lite', script);
    docs = FakeDocumentStore()
      ..seedMember(uid: demoUid, hid: demoHid)
      ..seedMember(uid: 'u_other', hid: 'hh_other');
    final catalogJson = await readCatalogJson();
    XpenseAgentRuntime agent(
      EntryClassifier classifier,
      RuntimeConfigLoader config,
      UsageCounters usage,
    ) => XpenseAgentRuntime.create(
      ai: ai,
      catalogJson: catalogJson,
      reader: demoReader('2026-11-22'),
      classifier: FakeEntryClassifier(),
      config: () async => RuntimeConfig.fromDocument(const {
        'models': {'agent': 'lite', 'escalation': 'lite'},
      }),
      sessions: const MemorySessions(),
      modelName: (id) => 'test/$id',
      clock: fixedClock,
    );
    final server = XpenseServer.create(
      role: XpenseRole.agent,
      ai: ai,
      gateway: fakeGateway(documents: docs),
      clock: Clock.fixed(DateTime.utc(2026, 11, 22)),
      agent: agent,
    );
    http = await shelf_io.serve(
      server.handler,
      InternetAddress.loopbackIPv4,
      0,
    );
  });

  tearDown(() async {
    await http.close(force: true);
    await ai.shutdown();
  });

  String url() => 'http://127.0.0.1:${http.port}/v1/agent';

  test('a verified member gets one surface for their household', () async {
    final client = remoteAgent<void>(
      url: url(),
      headers: () => headersFor(demoUid),
    );
    addTearDown(client.close);
    final chat = client.chat();
    final res = await chat.send(
      text: 'Salary came in 3200 and I paid rent 1400',
    );
    final parts = res.message?.content ?? const <Part>[];
    final a2ui = [
      for (final p in parts)
        if (p.metadata?['mimeType'] == 'application/a2ui+json') p,
    ];
    expect(a2ui, hasLength(1));
    expect(res.snapshotId, isNotNull);
    // The household came from the verified token, not from the client.
    final system = script.requests.first.messages.first.content
        .map((p) => p.text ?? '')
        .join();
    expect(system, contains('acc_chk | Checking'));
  });

  test('no token, no turn', () async {
    final client = remoteAgent<void>(url: url());
    addTearDown(client.close);
    await expectLater(
      client.chat().send(text: 'hi'),
      throwsA(
        isA<AgentError<dynamic>>().having(
          (e) => '$e',
          'error',
          contains('missing_id_token'),
        ),
      ),
    );
    expect(script.requests, isEmpty);
  });

  test("another household's member cannot read a snapshot", () async {
    final owner = remoteAgent<void>(
      url: url(),
      headers: () => headersFor(demoUid),
    );
    addTearDown(owner.close);
    final res = await owner.chat().send(text: 'Salary came in 3200');
    final intruder = remoteAgent<void>(
      url: url(),
      headers: () => headersFor('u_other'),
    );
    addTearDown(intruder.close);
    await expectLater(
      intruder.loadChat(snapshotId: res.snapshotId),
      throwsA(anything),
    );
  });
}
