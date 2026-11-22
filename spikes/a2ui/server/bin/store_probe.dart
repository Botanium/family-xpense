// WP-S1 spike (throwaway). Q6: where FirestoreSessionStore writes, with the
// D-11 prefix layout and with a households/{hid}/... nested layout. Runs two
// turns per layout in process against the Firestore emulator, resumes the
// session by id, checks that another household cannot read it, and lists the
// document paths that were written.
//
//   FIRESTORE_EMULATOR_HOST=127.0.0.1:8086 GOOGLE_CLOUD_PROJECT=xpense-dev \
//     dart run bin/store_probe.dart
// ignore_for_file: experimental_member_use
import 'dart:io';

import 'package:genkit/experimental.dart';
import 'package:genkit/genkit.dart' hide DocumentData;
import 'package:genkit_a2ui/a2ui.dart';
import 'package:genkit_google_cloud/firestore_session_store.dart';
import 'package:google_cloud_firestore/google_cloud_firestore.dart';
import 'package:wp_s1_server/household_store.dart';
import 'package:wp_s1_server/scripted_model.dart';

Future<void> main() async {
  if (Platform.environment['FIRESTORE_EMULATOR_HOST'] == null) {
    stderr.writeln(
      'Set FIRESTORE_EMULATOR_HOST; this probe never runs on a '
      'real project.',
    );
    exit(2);
  }
  final db = Firestore(
    settings: Settings(projectId: Platform.environment['GOOGLE_CLOUD_PROJECT']),
  );
  final ai = Genkit(plugins: [A2uiPlugin()]);
  await loadCatalog(
    ai,
    id: 'xpense-spike',
    file: '../catalog/spike_catalog.json',
  );
  final model = defineScriptedModel(ai);

  final layouts = <String, SessionStore>{
    'prefix': FirestoreSessionStore(
      db: db,
      collection: 'agentSessions',
      snapshotPathPrefix: (ctx) => '${ctx?['hid']}_${ctx?['uid']}',
    ),
    'nested': HouseholdSessionStore(db),
  };

  for (final MapEntry(key: name, value: store) in layouts.entries) {
    final agent = ai.defineAgent(
      name: 'probe_$name',
      model: modelRef(model.name),
      use: [a2ui(catalog: 'xpense-spike', validate: 'strict', repair: false)],
      store: store,
    );
    const ctxA = {'hid': 'hh_alpha', 'uid': 'u_owner'};
    const ctxB = {'hid': 'hh_beta', 'uid': 'u_owner'};

    final chat = agent.chat();
    final r1 = await chat.send(text: 'salary and rent', context: ctxA);
    final r2 = await chat.send(text: 'and Alex borrowed 300', context: ctxA);
    stdout.writeln(
      '[$name] session ${chat.sessionId} '
      'snapshots ${r1.snapshotId} -> ${r2.snapshotId}',
    );

    // Resume the same session from the store by id (a new chat object).
    final resumedOk = await store.getSnapshot(
      sessionId: chat.sessionId,
      context: ctxA,
    );
    stdout.writeln(
      '[$name] same household reads it back: '
      '${resumedOk != null} (${resumedOk?.state?.messages?.length} messages)',
    );

    final bySnap = await store.getSnapshot(
      snapshotId: r2.snapshotId,
      context: ctxA,
    );
    stdout.writeln(
      '[$name] by latest snapshotId: '
      '${bySnap?.state?.messages?.length} messages; by session id: '
      'snapshot ${resumedOk?.snapshotId}',
    );

    // Another household with the same session id must not see it.
    final other = await store.getSnapshot(
      sessionId: chat.sessionId,
      context: ctxB,
    );
    stdout.writeln('[$name] other household reads it: ${other != null}');
  }

  stdout.writeln('\nDocuments written:');
  Future<void> walk(
    CollectionReference<DocumentData> col,
    String indent,
  ) async {
    final docs = await col.listDocuments();
    for (final d in docs) {
      stdout.writeln('$indent${d.path}');
      for (final sub in await d.listCollections()) {
        await walk(sub, '$indent  ');
      }
    }
  }

  for (final col in await db.listCollections()) {
    await walk(col, '  ');
  }
}
