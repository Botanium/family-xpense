/// `POST /events/account-visibility`: rewrites `visibleTo` on an account's
/// transactions after its sharing changed (DATA_MODEL 4; BACKLOG S1.8).
///
/// Eventarc calls it whenever a document under `households/*/accounts/*` is
/// updated. The handler does not trust the event's payload: it takes the
/// account's path from the CloudEvent and reads the account itself, so the
/// trigger may send protobuf or JSON and a late or repeated event is
/// harmless.
///
/// Account fields (DATA_MODEL 2.4, added by WP-13):
///
/// - `visibilityRev` (int): the phone adds 1 whenever it changes the
///   account's `visibleTo` (the sharing switch); the server does the same
///   when a partner joins.
/// - `visibilitySyncedRev` (int, server only): the last rev whose history
///   rewrite finished. The app shows "Sharing…" while `visibilityRev` is
///   ahead of it.
/// - `visibilitySync` (map, server only, null when done): the running
///   rewrite, `{runId, rev, leaseUntil, done, total}`. `done` of `total`
///   is the progress line on screen 11.
///
/// Every event also fires for the job's own progress writes. A run holds a
/// short lease on the account, so those events find it busy and return at
/// once; a run that sees the rev move under it starts another pass with the
/// new state, and only finishes, in a transaction, when the rev it rewrote
/// for is still the account's rev.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:clock/clock.dart';
import 'package:logging/logging.dart';
import 'package:meta/meta.dart';
import 'package:shelf/shelf.dart';

import 'package:xpense_agent/admin/admin_gateway.dart';

final _log = Logger('xpense.jobs.account_visibility');

/// The route path, on the jobs service.
const accountVisibilityPath = '/events/account-visibility';

/// What one call of [AccountVisibilityJob.sync] did.
enum VisibilityOutcome {
  /// The history now matches the account; [VisibilityResult.rewritten]
  /// transactions changed.
  synced,

  /// Nothing to do: the account's history was already rewritten for its
  /// current rev.
  upToDate,

  /// Another run holds the account's lease and will finish the work.
  busy,

  /// No such account.
  missing,
}

/// The result of [AccountVisibilityJob.sync].
@immutable
final class VisibilityResult {
  /// Creates a result.
  const new(this.outcome, {this.rewritten = 0, this.passes = 0});

  /// What happened.
  final VisibilityOutcome outcome;

  /// Transactions whose `visibleTo` changed.
  final int rewritten;

  /// Full passes over the account's history (more than one when the
  /// sharing changed again during the run).
  final int passes;

  /// The JSON answer of the route.
  Map<String, Object?> toJson() => {
    'outcome': outcome.name,
    'rewritten': rewritten,
    'passes': passes,
  };

  @override
  String toString() => 'VisibilityResult(${toJson()})';
}

/// Rewrites `visibleTo` on transactions to match their accounts.
final class AccountVisibilityJob {
  /// Creates the job over [_store]. [pageSize] is the number of
  /// transactions per page and batch (DATA_MODEL 4: 400); [lease] is how
  /// long a run may go without a progress write before another run may
  /// take the account over.
  new(
    this._store, {
    Clock? clock,
    Random? random,
    this.pageSize = 400,
    this.lease = const Duration(seconds: 90),
  }) : _clock = clock ?? const Clock(),
       _random = random ?? Random.secure();

  final DocumentStore _store;
  final Clock _clock;
  final Random _random;

  /// Transactions per page and per batch.
  final int pageSize;

  /// How long a run's claim on an account lasts without a progress write.
  final Duration lease;

  /// The transaction fields that name an account.
  static const _accountFields = ['accountId', 'toAccountId'];

  /// Brings the history of `households/[hid]/accounts/[accountId]` in line
  /// with the account's `visibleTo`.
  Future<VisibilityResult> sync(String hid, String accountId) async {
    final accountPath = 'households/$hid/accounts/$accountId';
    final runId = _newRunId();
    final claim = await _claim(accountPath, runId);
    if (claim is! int) return VisibilityResult(claim as VisibilityOutcome);

    var rev = claim;
    var rewritten = 0;
    var passes = 0;
    while (true) {
      passes++;
      final pass = await _pass(hid, accountPath, runId, rev);
      if (pass == null) {
        // Another run took the lease over (this one stalled past it).
        return VisibilityResult(
          VisibilityOutcome.busy,
          rewritten: rewritten,
          passes: passes,
        );
      }
      rewritten += pass;
      final next = await _finish(accountPath, runId, rev);
      if (next == null) break;
      rev = next;
    }
    _log.info({
      'message': 'visibility synced',
      'account': accountId,
      'rewritten': rewritten,
      'passes': passes,
    });
    return VisibilityResult(
      VisibilityOutcome.synced,
      rewritten: rewritten,
      passes: passes,
    );
  }

  /// After a partner joins [hid]: every joint account, and every personal
  /// account its owner shares, becomes visible to all members, and its
  /// history follows. Returns the accounts it widened.
  Future<int> widenForMembers(String hid) async {
    final household = await _store.read('households/$hid');
    final members = _stringList(household?['memberIds'])..sort();
    if (members.isEmpty) return 0;
    final accounts = 'households/$hid/accounts';
    final candidates = {
      for (final doc in [
        ...await _store.pageWhereEquals(accounts, 'scope', 'joint', limit: 500),
        ...await _store.pageWhereEquals(
          accounts,
          'sharedWithPartner',
          true,
          limit: 500,
        ),
      ])
        doc.path: doc.data,
    };
    final widened = <String>[];
    for (final MapEntry(key: path, value: data) in candidates.entries) {
      if (_sameSet(_stringList(data['visibleTo']), members)) continue;
      await _store.transaction((tx) async {
        final fresh = await tx.read(path);
        if (fresh == null) return;
        final isJoint = fresh['scope'] == 'joint';
        if (!isJoint && fresh['sharedWithPartner'] != true) return;
        if (_sameSet(_stringList(fresh['visibleTo']), members)) return;
        tx.write(path, {
          'visibleTo': members,
          'visibilityRev': _int(fresh['visibilityRev']) + 1,
          'updatedAt': _clock.now().toUtc(),
          'updatedBy': 'system',
        }, merge: true);
      });
      widened.add(path.split('/').last);
    }
    // Eventarc would start these too; running them here makes the partner's
    // first look complete without waiting for the trigger.
    for (final id in widened) {
      await sync(hid, id);
    }
    return widened.length;
  }

  // ------------------------------------------------------------- the run

  /// Claims the account for [runId]. Returns the rev to rewrite for, or the
  /// outcome when there is nothing for this run to do.
  Future<Object> _claim(String accountPath, String runId) =>
      _store.transaction<Object>((tx) async {
        final account = await tx.read(accountPath);
        if (account == null) return VisibilityOutcome.missing;
        final rev = _int(account['visibilityRev']);
        final synced = _int(account['visibilitySyncedRev']);
        final running = _map(account['visibilitySync']);
        final now = _clock.now().toUtc();
        if (running != null && _leaseLive(running, now)) {
          return VisibilityOutcome.busy;
        }
        // Rev 0 is an account whose sharing never changed: its history was
        // written with the right visibleTo, unless a run left work behind.
        if (rev <= synced && running == null) return VisibilityOutcome.upToDate;
        tx.write(accountPath, {
          'visibilitySync': _syncMap(runId, rev, now, done: 0, total: null),
        }, merge: true);
        return rev;
      });

  /// One pass over the history for [rev]. Returns the transactions changed,
  /// or null when the lease was lost.
  Future<int?> _pass(
    String hid,
    String accountPath,
    String runId,
    int rev,
  ) async {
    final transactions = 'households/$hid/transactions';
    final accountId = accountPath.split('/').last;
    var total = 0;
    for (final field in _accountFields) {
      total += await _store.countWhereEquals(transactions, field, accountId);
    }
    var done = 0;
    var rewritten = 0;
    if (!await _progress(accountPath, runId, rev, done, total)) return null;

    for (final field in _accountFields) {
      String? after;
      while (true) {
        final page = await _store.pageWhereEquals(
          transactions,
          field,
          accountId,
          limit: pageSize,
          startAfterId: after,
        );
        if (page.isEmpty) break;
        // Fresh account state for every page: a flip during the run is
        // picked up by the next page and by the next pass.
        final visibleTo = <String, List<String>?>{};
        Future<List<String>?> visibilityOf(String id) async {
          if (visibleTo.containsKey(id)) return visibleTo[id];
          final doc = await _store.read('households/$hid/accounts/$id');
          return visibleTo[id] = doc == null
              ? null
              : _stringList(doc['visibleTo']);
        }

        final writes = <DocumentWrite>[];
        final now = _clock.now().toUtc();
        for (final doc in page) {
          final desired = <String>{};
          for (final f in _accountFields) {
            final id = doc.data[f];
            if (id is! String || id.isEmpty) continue;
            final v = await visibilityOf(id);
            if (v != null) desired.addAll(v);
          }
          if (desired.isEmpty) continue; // accounts gone: leave it alone
          final current = _stringList(doc.data['visibleTo']);
          if (_sameSet(current, desired)) continue;
          writes.add(
            DocumentWrite(doc.path, {
              'visibleTo': desired.toList()..sort(),
              'updatedAt': now,
              'updatedBy': 'system',
            }, merge: true),
          );
        }
        await _store.writeAll(writes);
        rewritten += writes.length;
        done += page.length;
        if (!await _progress(accountPath, runId, rev, done, total)) {
          return null;
        }
        if (page.length < pageSize) break;
        after = page.last.path.split('/').last;
      }
    }
    return rewritten;
  }

  /// Writes progress and renews the lease. Returns false when another run
  /// holds the account now.
  Future<bool> _progress(
    String accountPath,
    String runId,
    int rev,
    int done,
    int total,
  ) => _store.transaction((tx) async {
    final account = await tx.read(accountPath);
    if (account == null) return false;
    final running = _map(account['visibilitySync']);
    if (running == null || running['runId'] != runId) return false;
    tx.write(accountPath, {
      'visibilitySync': _syncMap(
        runId,
        rev,
        _clock.now().toUtc(),
        done: done,
        total: total < done ? done : total,
      ),
    }, merge: true);
    return true;
  });

  /// Marks [rev] done when it is still the account's rev and releases the
  /// lease. Returns null when finished, or the newer rev to rewrite for.
  Future<int?> _finish(String accountPath, String runId, int rev) =>
      _store.transaction((tx) async {
        final account = await tx.read(accountPath);
        if (account == null) return null;
        final current = _int(account['visibilityRev']);
        final now = _clock.now().toUtc();
        if (current != rev) {
          tx.write(accountPath, {
            'visibilitySync': _syncMap(
              runId,
              current,
              now,
              done: 0,
              total: null,
            ),
          }, merge: true);
          return current;
        }
        // A whole-document write (safe inside the transaction): a merge
        // write does not clear a map field set to null.
        tx.write(accountPath, {
          ...account,
          'visibilitySyncedRev': rev,
          'visibilitySync': null,
        });
        return null;
      });

  Map<String, Object?> _syncMap(
    String runId,
    int rev,
    DateTime now, {
    required int done,
    required int? total,
  }) => {
    'runId': runId,
    'rev': rev,
    'leaseUntil': now.add(lease),
    'done': done,
    'total': total,
  };

  bool _leaseLive(Map<String, Object?> running, DateTime now) {
    final until = running['leaseUntil'];
    return until is DateTime && until.isAfter(now);
  }

  String _newRunId() => List.generate(
    8,
    (_) => _random.nextInt(256),
  ).map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}

// ------------------------------------------------------------------ route

/// The Shelf handler for [accountVisibilityPath].
///
/// Answers 200 with the [VisibilityResult], 204 for an event that names no
/// account (dropped: a retry would not help), 405 for a non-POST, and 503
/// when Firestore is unavailable, so Eventarc retries.
Handler accountVisibilityHandler(AccountVisibilityJob job) => (request) async {
  if (request.method != 'POST') {
    return Response(405, headers: {'allow': 'POST'});
  }
  final body = await request.readAsString();
  final target = accountFromEvent(request.headers, body);
  if (target == null) {
    _log.warning({
      'message': 'event names no account',
      'type': request.headers['ce-type'],
    });
    return Response(204);
  }
  try {
    final result = await job.sync(target.hid, target.accountId);
    return Response.ok(
      jsonEncode(result.toJson()),
      headers: {'content-type': 'application/json'},
    );
  } on GatewayUnavailable catch (e) {
    _log.warning('backend unavailable (${e.operation})', e.cause);
    return Response(503, body: 'unavailable');
  }
};

final _accountPath = RegExp(
  r'(?:^|/documents/)households/([^/]+)/accounts/([^/]+)$',
);

/// The account an Eventarc Firestore event is about, from the CloudEvent's
/// `document` attribute (`ce-document`), its `subject`
/// (`documents/households/…`), or a JSON body's `value.name` or
/// `document`. Null when none names an account.
({String hid, String accountId})? accountFromEvent(
  Map<String, String> headers,
  String body,
) {
  final candidates = <String?>[headers['ce-document'], headers['ce-subject']];
  if (body.isNotEmpty && body.trimLeft().startsWith('{')) {
    try {
      if (jsonDecode(body) case final Map<String, Object?> json) {
        String? text(Object? v) => v is String ? v : null;
        candidates
          ..add(text(json['document']))
          ..add(text(_map(json['value'])?['name']))
          ..add(text(_map(json['oldValue'])?['name']));
      }
    } on FormatException {
      // Protobuf or garbage: the headers decide.
    }
  }
  for (final raw in candidates) {
    if (raw == null) continue;
    final path = raw.startsWith('documents/')
        ? raw.substring('documents/'.length)
        : raw;
    final match = _accountPath.firstMatch(path);
    if (match != null) {
      return (hid: match.group(1)!, accountId: match.group(2)!);
    }
  }
  return null;
}

// ---------------------------------------------------------------- helpers

int _int(Object? value) => value is int ? value : 0;

Map<String, Object?>? _map(Object? value) =>
    value is Map<String, Object?> ? value : null;

List<String> _stringList(Object? value) =>
    value is List ? value.whereType<String>().toList() : <String>[];

bool _sameSet(Iterable<String> a, Iterable<String> b) {
  final sa = a.toSet();
  final sb = b.toSet();
  return sa.length == sb.length && sa.containsAll(sb);
}
