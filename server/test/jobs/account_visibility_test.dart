import 'dart:convert';

import 'dart:math';

import 'package:clock/clock.dart';
import 'package:genkit/genkit.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';
import 'package:xpense_agent/admin/admin_gateway.dart';
import 'package:xpense_agent/config/server_env.dart';
import 'package:xpense_agent/household/household_failure.dart';
import 'package:xpense_agent/household/household_service.dart';
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
    List<String>? applied,
    Map<String, Object?>? sync,
  }) {
    docs.docs['$accounts/$id'] = {
      'name': id,
      'scope': scope,
      if (scope == 'personal') 'ownerUid': owner,
      'sharedWithPartner': shared,
      'visibleTo': visibleTo,
      'visibilityAppliedTo': ?applied,
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
      seedAccount(
        'chk',
        visibleTo: [owner, partner],
        shared: true,
        applied: [owner],
      );
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
      expect(account['visibilityAppliedTo'], [owner, partner]);
      expect(account['visibilitySync'], isNull);
    });

    test('making it private again hides it, but not a transfer into a '
        'joint account', () async {
      seedAccount('chk', visibleTo: [owner], applied: [owner, partner]);
      seedAccount('joint', visibleTo: [owner, partner], scope: 'joint');
      seedTxn('own', 'chk', visibleTo: [owner, partner]);
      seedTxn('out', 'chk', to: 'joint', visibleTo: [owner, partner]);

      final result = await job.sync(hid, 'chk');

      expect(result.rewritten, 1);
      expect(visibleOf('$txns/own'), [owner]);
      expect(visibleOf('$txns/out'), [owner, partner]);
      expect(docs.docs['$accounts/chk']!['visibilityAppliedTo'], [owner]);
    });

    test('pages through the history and records progress', () async {
      seedAccount(
        'chk',
        visibleTo: [owner, partner],
        shared: true,
        applied: [owner],
      );
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
      for (var i = 0; i < 5; i++) {
        expect(visibleOf('$txns/t$i'), [owner, partner]);
      }
    });

    test(
      'a flip during the run gets another pass with the new state',
      () async {
        seedAccount(
          'chk',
          visibleTo: [owner, partner],
          shared: true,
          applied: [owner],
        );
        for (var i = 0; i < 5; i++) {
          seedTxn('t$i', 'chk', visibleTo: [owner]);
        }
        docs.onPage = (page) async {
          if (page != 1) return;
          // The owner turns sharing off again while the first page is done.
          docs.docs['$accounts/chk']!
            ..['visibleTo'] = [owner]
            ..['sharedWithPartner'] = false;
        };

        final result = await job.sync(hid, 'chk');

        expect(result.passes, 2);
        for (var i = 0; i < 5; i++) {
          expect(visibleOf('$txns/t$i'), [owner], reason: 't$i');
        }
        expect(docs.docs['$accounts/chk']!['visibilityAppliedTo'], [owner]);
        expect(docs.docs['$accounts/chk']!['visibilitySync'], isNull);
      },
    );

    test('nothing to do when the history matches the account', () async {
      seedAccount('chk', visibleTo: [owner], applied: [owner]);
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
        applied: [owner],
        sync: {
          'runId': 'other',
          'target': [owner, partner],
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
        applied: [owner],
        sync: {
          'runId': 'crashed',
          'target': [owner, partner],
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

    test(
      'revoking sharing: the partner keeps nothing of the history',
      () async {
        seedAccount(
          'chk',
          visibleTo: [owner, partner],
          shared: true,
          applied: [owner],
        );
        for (var i = 0; i < 3; i++) {
          seedTxn('t$i', 'chk', visibleTo: [owner]);
        }
        await job.sync(hid, 'chk');
        int partnerSees() => [
          for (final e in docs.docs.entries)
            if (e.key.startsWith('$txns/') &&
                (e.value['visibleTo']! as List).contains(partner))
              e.key,
        ].length;
        expect(partnerSees(), 3);

        // The owner turns sharing off (the phone writes only these two).
        docs.docs['$accounts/chk']!
          ..['sharedWithPartner'] = false
          ..['visibleTo'] = [owner];
        final result = await job.sync(hid, 'chk');

        expect(result.outcome, VisibilityOutcome.synced);
        expect(partnerSees(), 0);
        expect(docs.docs['$accounts/chk']!['visibilityAppliedTo'], [owner]);
      },
    );

    test('phone-writable counters and a forged lease cannot stop a revoke '
        '(security review, PR #33)', () async {
      seedAccount(
        'chk',
        visibleTo: [owner],
        applied: [owner, partner],
        sync: {
          'runId': 'forged',
          'target': [owner, partner],
          'leaseUntil': DateTime.utc(9999),
          'done': 0,
          'total': 0,
        },
      );
      // The old design's markers, set as high as a partner could.
      docs.docs['$accounts/chk']!
        ..['visibilityRev'] = 0
        ..['visibilitySyncedRev'] = 9007199254740991;
      seedTxn('t', 'chk', visibleTo: [owner, partner]);

      final result = await job.sync(hid, 'chk');

      expect(result.outcome, VisibilityOutcome.synced);
      expect(visibleOf('$txns/t'), [owner]);
    });

    test('a run whose lease was taken over writes no more history '
        '(Codex review, PR #33)', () async {
      seedAccount(
        'chk',
        visibleTo: [owner, partner],
        shared: true,
        applied: [owner],
      );
      for (var i = 0; i < 5; i++) {
        seedTxn('t$i', 'chk', visibleTo: [owner]);
      }
      docs.onPage = (page) async {
        if (page != 1) return;
        // This run stalled past its lease; another run took the account
        // over (for the owner's newer, private setting) before this run's
        // second page is written.
        docs.docs['$accounts/chk']!['visibilitySync'] = {
          'runId': 'newer',
          'target': [owner],
          'leaseUntil': now.add(const Duration(seconds: 60)),
          'done': 0,
          'total': 5,
        };
      };

      final result = await job.sync(hid, 'chk');

      expect(result.outcome, VisibilityOutcome.busy);
      // The first page was written under the lease; nothing after it.
      expect(visibleOf('$txns/t0'), [owner, partner]);
      expect(visibleOf('$txns/t1'), [owner, partner]);
      for (var i = 2; i < 5; i++) {
        expect(visibleOf('$txns/t$i'), [owner], reason: 't$i');
      }
      // The newer run's lease and the record of what was applied are left
      // alone.
      final account = docs.docs['$accounts/chk']!;
      expect((account['visibilitySync']! as Map)['runId'], 'newer');
      expect(account['visibilityAppliedTo'], [owner]);
    });

    test(
      'a run that loses its lease just before finishing records nothing',
      () async {
        seedAccount(
          'chk',
          visibleTo: [owner, partner],
          shared: true,
          applied: [owner],
        );
        seedTxn('t0', 'chk', visibleTo: [owner]);
        // One page of one: the next page read is the empty toAccountId page,
        // after which the run finishes.
        docs.onPage = (page) async {
          if (page != 1) return;
          docs.docs['$accounts/chk']!['visibilitySync'] = {
            'runId': 'newer',
            'target': [owner, partner],
            'leaseUntil': now.add(const Duration(seconds: 60)),
          };
        };

        final result = await job.sync(hid, 'chk');

        expect(result.outcome, VisibilityOutcome.busy);
        final account = docs.docs['$accounts/chk']!;
        expect(account['visibilityAppliedTo'], [owner]);
        expect((account['visibilitySync']! as Map)['runId'], 'newer');
      },
    );

    test('a missing account is reported, not created', () async {
      final result = await job.sync(hid, 'gone');
      expect(result.outcome, VisibilityOutcome.missing);
      expect(docs.docs.containsKey('$accounts/gone'), isFalse);
    });
  });

  group('joining widens joint and shared accounts', () {
    late HouseholdService households;

    setUp(() {
      // A household of one, as before the partner joins.
      docs.seedMember(uid: owner, hid: hid);
      households = HouseholdService(
        docs,
        clock: Clock.fixed(now),
        random: Random(7),
        onJoin: job.prepareJoinWidening,
      );
    });

    Future<void> join() async {
      final invite = await households.createInvite(uid: owner, hid: hid);
      await households.join(
        uid: partner,
        code: invite.code,
        displayName: 'Sam',
      );
    }

    test(
      'in the join transaction itself, with nothing run afterwards',
      () async {
        seedAccount(
          'joint',
          visibleTo: [owner],
          scope: 'joint',
          applied: [owner],
        );
        seedAccount(
          'shared',
          visibleTo: [owner],
          shared: true,
          applied: [owner],
        );
        seedAccount('private', visibleTo: [owner], applied: [owner]);

        await join();

        // Committed with the join: no after-join hook needed (Codex review).
        expect(visibleOf('$accounts/joint'), [owner, partner]);
        expect(visibleOf('$accounts/shared'), [owner, partner]);
        expect(visibleOf('$accounts/private'), [owner]);
        // visibleTo is now ahead of what the history was rewritten for, so
        // the account event rewrites it.
        expect(docs.docs['$accounts/joint']!['visibilityAppliedTo'], [owner]);
      },
    );

    test('a failed join widens nothing', () async {
      seedAccount('joint', visibleTo: [owner], scope: 'joint');
      final invite = await households.createInvite(uid: owner, hid: hid);
      // Already a member of another household: the join is refused.
      docs.docs['households/h9'] = {
        'memberIds': [partner],
      };

      await expectLater(
        households.join(uid: partner, code: invite.code, displayName: 'Sam'),
        throwsA(isA<HouseholdRejection>()),
      );
      expect(visibleOf('$accounts/joint'), [owner]);
    });

    test('syncAfterJoin then brings the history along', () async {
      seedAccount(
        'joint',
        visibleTo: [owner],
        scope: 'joint',
        applied: [owner],
      );
      seedAccount('private', visibleTo: [owner], applied: [owner]);
      seedTxn('j', 'joint', visibleTo: [owner]);
      seedTxn('p', 'private', visibleTo: [owner]);

      await join();
      final synced = await job.syncAfterJoin(hid);

      expect(synced, 1);
      expect(visibleOf('$txns/j'), [owner, partner]);
      expect(visibleOf('$txns/p'), [owner]);
      expect(docs.docs['$accounts/joint']!['visibilityAppliedTo'], [
        owner,
        partner,
      ]);
    });
  });

  group('a run that fails', () {
    test('releases its lease, so the retried delivery does the work', () async {
      seedAccount(
        'chk',
        visibleTo: [owner, partner],
        shared: true,
        applied: [owner],
      );
      for (var i = 0; i < 5; i++) {
        seedTxn('t$i', 'chk', visibleTo: [owner]);
      }
      docs.onPage = (page) async {
        if (page == 1) throw const GatewayUnavailable('pageWhereEquals');
      };

      await expectLater(
        job.sync(hid, 'chk'),
        throwsA(isA<GatewayUnavailable>()),
      );
      final account = docs.docs['$accounts/chk']!;
      expect(account['visibilitySync'], isNull);
      // Unknown history: the record is dropped so the work stays pending.
      expect(account['visibilityAppliedTo'], isNull);

      // Eventarc retries at once, well inside the old lease.
      docs.onPage = null;
      final retry = await job.sync(hid, 'chk');
      expect(retry.outcome, VisibilityOutcome.synced);
      for (var i = 0; i < 5; i++) {
        expect(visibleOf('$txns/t$i'), [owner, partner]);
      }
    });
  });

  group('a failed run after a flip back', () {
    test(
      'still repairs the pages it already shared (Codex review, PR #33)',
      () async {
        seedAccount(
          'chk',
          visibleTo: [owner, partner],
          shared: true,
          applied: [owner],
        );
        for (var i = 0; i < 5; i++) {
          seedTxn('t$i', 'chk', visibleTo: [owner]);
        }
        docs.onPage = (page) async {
          if (page != 1) return;
          // The first page is shared; then the owner turns sharing off again
          // and the next page read fails.
          docs.docs['$accounts/chk']!
            ..['visibleTo'] = [owner]
            ..['sharedWithPartner'] = false;
          throw const GatewayUnavailable('pageWhereEquals');
        };

        await expectLater(
          job.sync(hid, 'chk'),
          throwsA(isA<GatewayUnavailable>()),
        );
        expect(visibleOf('$txns/t0'), [owner, partner], reason: 'half done');

        // visibleTo is back to what was applied before the run, yet the
        // retry must not take that for "up to date".
        docs.onPage = null;
        final retry = await job.sync(hid, 'chk');

        expect(retry.outcome, VisibilityOutcome.synced);
        for (var i = 0; i < 5; i++) {
          expect(visibleOf('$txns/t$i'), [owner], reason: 't$i');
        }
        expect(docs.docs['$accounts/chk']!['visibilityAppliedTo'], [owner]);
      },
    );
  });

  group('a transfer between two accounts whose sharing changes at once', () {
    test("is never committed with the other account's stale visibility "
        '(Codex review, PR #33)', () async {
      // A was shared and is being made private; B is private and is about
      // to be shared. Transfer x runs from A to B.
      seedAccount('a', visibleTo: [owner], applied: [owner, partner]);
      seedAccount('b', visibleTo: [owner], applied: [owner]);
      seedTxn('x', 'a', to: 'b', visibleTo: [owner, partner]);
      var fired = false;
      docs.onTransaction = () async {
        // After A's run has read its page (and B as private), before it
        // commits: B gets shared and B's run finishes.
        if (fired || docs.pageReads != 1) return;
        fired = true;
        docs.docs['$accounts/b']!
          ..['visibleTo'] = [owner, partner]
          ..['sharedWithPartner'] = true
          ..['visibilityAppliedTo'] = [owner, partner];
      };

      final result = await job.sync(hid, 'a');

      expect(fired, isTrue);
      expect(result.outcome, VisibilityOutcome.synced);
      // B is shared, so the transfer into it stays visible to the partner.
      expect(visibleOf('$txns/x'), [owner, partner]);
    });

    test('gives up with 503 when the other account never settles', () async {
      seedAccount('a', visibleTo: [owner], applied: [owner, partner]);
      seedAccount('b', visibleTo: [owner], applied: [owner]);
      seedTxn('x', 'a', to: 'b', visibleTo: [owner, partner]);
      var flips = 0;
      docs.onTransaction = () async {
        if (docs.pageReads != 1) return;
        final b = docs.docs['$accounts/b']!;
        b['visibleTo'] = (flips++).isEven ? [owner, partner] : [owner];
      };

      await expectLater(job.sync(hid, 'a'), throwsA(isA<GatewayUnavailable>()));
      // Nothing half written, and the repair stays pending.
      expect(visibleOf('$txns/x'), [owner, partner]);
      expect(docs.docs['$accounts/a']!['visibilityAppliedTo'], isNull);
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
      seedAccount(
        'chk',
        visibleTo: [owner, partner],
        shared: true,
        applied: [owner],
      );
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

    test('hands a busy delivery back for a later retry', () async {
      seedAccount(
        'chk',
        visibleTo: [owner, partner],
        applied: [owner],
        sync: {
          'runId': 'other',
          'target': [owner, partner],
          'leaseUntil': now.add(const Duration(seconds: 30)),
          'done': 0,
          'total': 4,
        },
      );

      final response = await post({'ce-document': '$accounts/chk'});

      // Not 200: an acknowledged busy delivery could be lost for good if
      // the run holding the lease has died (Codex review, PR #33).
      expect(response.statusCode, 429);
      expect(response.headers['retry-after'], '30');
    });

    test('a failed run answers 503 and its retry finishes the work', () async {
      seedAccount(
        'chk',
        visibleTo: [owner, partner],
        shared: true,
        applied: [owner],
      );
      seedTxn('t', 'chk', visibleTo: [owner]);
      docs.onPage = (_) async =>
          throw const GatewayUnavailable('pageWhereEquals');

      final failed = await post({'ce-document': '$accounts/chk'});
      expect(failed.statusCode, 503);

      docs.onPage = null;
      final retried = await post({'ce-document': '$accounts/chk'});
      expect(retried.statusCode, 200);
      expect(visibleOf('$txns/t'), [owner, partner]);
    });

    test('reads a binary protobuf body without failing', () async {
      seedAccount(
        'chk',
        visibleTo: [owner, partner],
        shared: true,
        applied: [owner],
      );
      seedTxn('t', 'chk', visibleTo: [owner]);

      // Eventarc sends Firestore events as protobuf; these bytes are not
      // valid UTF-8 (Codex review, PR #41).
      final response = await handler(
        Request(
          'POST',
          Uri.parse('http://localhost$accountVisibilityPath'),
          headers: {
            'ce-document': '$accounts/chk',
            'content-type': 'application/protobuf',
          },
          body: <int>[0x0a, 0xff, 0xfe, 0x80, 0x12, 0xc3, 0x28],
        ),
      );

      expect(response.statusCode, 200);
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
