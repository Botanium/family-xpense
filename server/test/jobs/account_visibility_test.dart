import 'dart:convert';

import 'package:clock/clock.dart';
import 'package:genkit/genkit.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';
import 'package:xpense_agent/config/server_env.dart';
import 'package:xpense_agent/jobs/account_visibility.dart';
import 'package:xpense_agent/xpense_server.dart';

import '../support/fakes.dart';

const hid = 'h1';
const owner = 'uA';
const partner = 'uB';
const accounts = 'households/$hid/accounts';
const txns = 'households/$hid/transactions';

final now = DateTime.utc(2026, 11, 22, 12);

void main() {
  late FakeDocumentStore docs;
  late AccountVisibilityJob job;

  void seedAccount(
    String id, {
    required List<String> visibleTo,
    String scope = 'personal',
    bool shared = false,
    int rev = 0,
    int synced = 0,
    Map<String, Object?>? sync,
  }) {
    docs.docs['$accounts/$id'] = {
      'name': id,
      'scope': scope,
      if (scope == 'personal') 'ownerUid': owner,
      'sharedWithPartner': shared,
      'visibleTo': visibleTo,
      'visibilityRev': rev,
      'visibilitySyncedRev': synced,
      'visibilitySync': ?sync,
    };
  }

  void seedTxn(
    String id,
    String accountId, {
    required List<String> visibleTo,
    String? to,
  }) {
    docs.docs['$txns/$id'] = {
      'type': to == null ? 'expense' : 'transfer',
      'accountId': accountId,
      'toAccountId': ?to,
      'amountMinor': 100,
      'visibleTo': visibleTo,
      'rev': 3,
    };
  }

  List<String> visibleOf(String path) =>
      (docs.docs[path]!['visibleTo']! as List).cast<String>()..sort();

  setUp(() {
    docs = FakeDocumentStore();
    docs.docs['households/$hid'] = {
      'memberIds': [owner, partner],
    };
    job = AccountVisibilityJob(docs, clock: Clock.fixed(now), pageSize: 2);
  });

  group('sync', () {
    test('sharing an account shows its whole history to the partner', () async {
      seedAccount('chk', visibleTo: [owner, partner], shared: true, rev: 1);
      seedAccount('joint', visibleTo: [owner, partner], scope: 'joint');
      for (var i = 0; i < 5; i++) {
        seedTxn('t$i', 'chk', visibleTo: [owner]);
      }
      seedTxn('in', 'joint', to: 'chk', visibleTo: [owner, partner]);

      final result = await job.sync(hid, 'chk');

      expect(result.outcome, VisibilityOutcome.synced);
      expect(result.rewritten, 5);
      for (var i = 0; i < 5; i++) {
        expect(visibleOf('$txns/t$i'), [owner, partner]);
        expect(docs.docs['$txns/t$i']!['updatedBy'], 'system');
        // A visibility rewrite is not an edit: rev stays.
        expect(docs.docs['$txns/t$i']!['rev'], 3);
      }
      final account = docs.docs['$accounts/chk']!;
      expect(account['visibilitySyncedRev'], 1);
      expect(account['visibilitySync'], isNull);
    });

    test('making it private again hides it, but not a transfer into a '
        'joint account', () async {
      seedAccount('chk', visibleTo: [owner], rev: 2, synced: 1);
      seedAccount('joint', visibleTo: [owner, partner], scope: 'joint');
      seedTxn('own', 'chk', visibleTo: [owner, partner]);
      seedTxn('out', 'chk', to: 'joint', visibleTo: [owner, partner]);

      final result = await job.sync(hid, 'chk');

      expect(result.rewritten, 1);
      expect(visibleOf('$txns/own'), [owner]);
      expect(visibleOf('$txns/out'), [owner, partner]);
      expect(docs.docs['$accounts/chk']!['visibilitySyncedRev'], 2);
    });

    test('pages through the history and records progress', () async {
      seedAccount('chk', visibleTo: [owner, partner], shared: true, rev: 1);
      for (var i = 0; i < 5; i++) {
        seedTxn('t$i', 'chk', visibleTo: [owner]);
      }
      final progress = <Object?>[];
      docs.onPage = (_) async {
        final sync = docs.docs['$accounts/chk']!['visibilitySync'];
        if (sync is Map) progress.add('${sync['done']}/${sync['total']}');
      };

      await job.sync(hid, 'chk');

      // accountId pages of 2, 2, 1, then one empty toAccountId page.
      expect(progress, ['0/5', '2/5', '4/5', '5/5']);
      expect(docs.batches.map((b) => b.length), [2, 2, 1]);
    });

    test(
      'a flip during the run gets another pass with the new state',
      () async {
        seedAccount('chk', visibleTo: [owner, partner], shared: true, rev: 1);
        for (var i = 0; i < 5; i++) {
          seedTxn('t$i', 'chk', visibleTo: [owner]);
        }
        docs.onPage = (page) async {
          if (page != 1) return;
          // The owner turns sharing off again while the first page is done.
          docs.docs['$accounts/chk']!
            ..['visibleTo'] = [owner]
            ..['sharedWithPartner'] = false
            ..['visibilityRev'] = 2;
        };

        final result = await job.sync(hid, 'chk');

        expect(result.passes, 2);
        for (var i = 0; i < 5; i++) {
          expect(visibleOf('$txns/t$i'), [owner], reason: 't$i');
        }
        expect(docs.docs['$accounts/chk']!['visibilitySyncedRev'], 2);
        expect(docs.docs['$accounts/chk']!['visibilitySync'], isNull);
      },
    );

    test('nothing to do when the history matches the rev', () async {
      seedAccount('chk', visibleTo: [owner], rev: 3, synced: 3);
      seedTxn('t', 'chk', visibleTo: [owner]);

      final result = await job.sync(hid, 'chk');

      expect(result.outcome, VisibilityOutcome.upToDate);
      expect(docs.pageReads, 0);
      expect(docs.batches, isEmpty);
    });

    test('a run that holds a live lease makes others return', () async {
      seedAccount(
        'chk',
        visibleTo: [owner, partner],
        rev: 1,
        sync: {
          'runId': 'other',
          'rev': 1,
          'leaseUntil': now.add(const Duration(seconds: 30)),
          'done': 0,
          'total': 4,
        },
      );

      final result = await job.sync(hid, 'chk');

      expect(result.outcome, VisibilityOutcome.busy);
      expect(docs.pageReads, 0);
    });

    test('an expired lease is taken over', () async {
      seedAccount(
        'chk',
        visibleTo: [owner, partner],
        rev: 1,
        sync: {
          'runId': 'crashed',
          'rev': 1,
          'leaseUntil': now.subtract(const Duration(seconds: 1)),
          'done': 2,
          'total': 4,
        },
      );
      seedTxn('t', 'chk', visibleTo: [owner]);

      final result = await job.sync(hid, 'chk');

      expect(result.outcome, VisibilityOutcome.synced);
      expect(visibleOf('$txns/t'), [owner, partner]);
    });

    test('a missing account is reported, not created', () async {
      final result = await job.sync(hid, 'gone');
      expect(result.outcome, VisibilityOutcome.missing);
      expect(docs.docs.containsKey('$accounts/gone'), isFalse);
    });
  });

  group('widenForMembers', () {
    test('joint and shared accounts and their history reach the new member, '
        'private ones do not', () async {
      seedAccount('joint', visibleTo: [owner], scope: 'joint');
      seedAccount('shared', visibleTo: [owner], shared: true);
      seedAccount('private', visibleTo: [owner]);
      seedTxn('j', 'joint', visibleTo: [owner]);
      seedTxn('s', 'shared', visibleTo: [owner]);
      seedTxn('p', 'private', visibleTo: [owner]);

      final widened = await job.widenForMembers(hid);

      expect(widened, 2);
      expect(visibleOf('$accounts/joint'), [owner, partner]);
      expect(visibleOf('$accounts/shared'), [owner, partner]);
      expect(visibleOf('$accounts/private'), [owner]);
      expect(docs.docs['$accounts/joint']!['visibilityRev'], 1);
      expect(docs.docs['$accounts/joint']!['visibilitySyncedRev'], 1);
      expect(visibleOf('$txns/j'), [owner, partner]);
      expect(visibleOf('$txns/s'), [owner, partner]);
      expect(visibleOf('$txns/p'), [owner]);
    });
  });

  group('accountFromEvent', () {
    test('reads the ce-document attribute', () {
      expect(accountFromEvent({'ce-document': 'households/h/accounts/a'}, ''), (
        hid: 'h',
        accountId: 'a',
      ));
    });

    test('reads the subject', () {
      expect(
        accountFromEvent({
          'ce-subject': 'documents/households/h/accounts/a',
        }, '\x0a\x01'),
        (hid: 'h', accountId: 'a'),
      );
    });

    test('reads a JSON body', () {
      final body = jsonEncode({
        'value': {
          'name': 'projects/p/databases/(default)/documents/households/h/accounts/a',
        },
      });
      expect(accountFromEvent({}, body), (hid: 'h', accountId: 'a'));
    });

    test('ignores anything that is not an account', () {
      expect(
        accountFromEvent({
          'ce-document': 'households/h/transactions/t',
        }, '{"document": 4}'),
        isNull,
      );
      expect(accountFromEvent({}, 'not json'), isNull);
    });
  });

  group('the route on the jobs service', () {
    late Genkit ai;
    late Handler handler;

    setUp(() {
      ai = Genkit(isDevEnv: false, promptDir: null);
      handler = XpenseServer.create(
        role: XpenseRole.jobs,
        ai: ai,
        gateway: fakeGateway(documents: docs),
        clock: Clock.fixed(now),
      ).handler;
    });

    tearDown(() => ai.shutdown());

    Future<Response> post(Map<String, String> headers) => Future.value(
      handler(
        Request(
          'POST',
          Uri.parse('http://localhost$accountVisibilityPath'),
          headers: headers,
          body: '',
        ),
      ),
    );

    test('runs the backfill for the event account', () async {
      seedAccount('chk', visibleTo: [owner, partner], shared: true, rev: 1);
      seedTxn('t', 'chk', visibleTo: [owner]);

      final response = await post({'ce-document': '$accounts/chk'});

      expect(response.statusCode, 200);
      expect(jsonDecode(await response.readAsString()), {
        'outcome': 'synced',
        'rewritten': 1,
        'passes': 1,
      });
      expect(visibleOf('$txns/t'), [owner, partner]);
    });

    test('drops an event that names no account', () async {
      final response = await post({'ce-document': 'users/u'});
      expect(response.statusCode, 204);
    });

    test('asks for a retry when Firestore is unavailable', () async {
      docs.failingPaths.add('$accounts/chk');
      final response = await post({'ce-document': '$accounts/chk'});
      expect(response.statusCode, 503);
    });

    test('refuses GET', () async {
      final response = await handler(
        Request('GET', Uri.parse('http://localhost$accountVisibilityPath')),
      );
      expect(response.statusCode, 405);
    });

    test('is not served by the agent role', () async {
      final agent = XpenseServer.create(
        role: XpenseRole.agent,
        ai: ai,
        gateway: fakeGateway(documents: docs),
      ).handler;
      final response = await agent(
        Request('POST', Uri.parse('http://localhost$accountVisibilityPath')),
      );
      expect(response.statusCode, 404);
    });
  });
}
