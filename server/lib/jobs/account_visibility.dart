/// `POST /events/account-visibility`: rewrites `visibleTo` on an account's
/// transactions after its sharing changed (DATA_MODEL 4; BACKLOG S1.8).
///
/// Eventarc calls it whenever a document under `households/*/accounts/*` is
/// updated. The handler does not trust the event's payload: it takes the
/// account's path from the CloudEvent and reads the account itself, so the
/// trigger may send protobuf or JSON and a late or repeated event is
/// harmless.
///
/// Account fields (DATA_MODEL 2.4, added by WP-13), both written only by
/// the server (the rules refuse them from the phone):
///
/// - `visibilityAppliedTo` (string list): the `visibleTo` the account's
///   history was last rewritten for. The job works whenever the account's
///   actual `visibleTo` differs from it (or it is missing), so the decision
///   rests on the account's own state, never on a counter the phone could
///   move (security review, PR #33). The app shows "Sharing…" while the two
///   differ.
/// - `visibilitySync` (map, null when done): the running rewrite,
///   `{runId, target, leaseUntil, done, total}`. `done` of `total` is the
///   progress line on screen 11.
///
/// Every event also fires for the job's own progress writes. A run holds a
/// short lease on the account, so those events find it busy and are handed
/// back unacknowledged (429), to be delivered again later. A run rewrites
/// for the `visibleTo` it read when it started, and finishes, in a
/// transaction, only when that is still the account's `visibleTo`;
/// otherwise it starts another pass for the new one. A run that fails
/// releases its lease and its delivery gets a 503, so no sharing change
/// waits on a lease nobody holds.
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
  /// current `visibleTo`.
  upToDate,

  /// Another run holds the account's lease and will finish the work.
  busy,

  /// No such account, or one with no readers.
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
    if (claim is! List<String>) {
      return VisibilityResult(claim as VisibilityOutcome);
    }

    var target = claim;
    var rewritten = 0;
    var passes = 0;
    try {
      while (true) {
        passes++;
        final pass = await _pass(hid, accountPath, runId, target);
        if (pass == null) {
          // Another run took the lease over (this one stalled past it).
          return VisibilityResult(
            VisibilityOutcome.busy,
            rewritten: rewritten,
            passes: passes,
          );
        }
        rewritten += pass;
        final List<String>? next;
        try {
          next = await _finish(accountPath, runId, target);
        } on _LeaseLost {
          return VisibilityResult(
            VisibilityOutcome.busy,
            rewritten: rewritten,
            passes: passes,
          );
        }
        if (next == null) break;
        target = next;
      }
    } on Object {
      // Give the account back at once, so the retried delivery of this
      // event (the handler answers 503) can claim it instead of finding a
      // lease nobody is working under.
      await _release(accountPath, runId);
      rethrow;
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

  /// Inside the join transaction (a `JoinTransactionHook`): reads every
  /// joint account and every shared personal one of [hid] and returns the
  /// writes that make them visible to all of [memberIds]. They commit with
  /// the join or not at all, and each account update fires
  /// `/events/account-visibility`, whose retries rewrite the history
  /// durably until it matches (Codex review, PR #33).
  Future<void Function()> prepareJoinWidening(
    DocumentTransaction tx,
    String hid,
    List<String> memberIds,
    DateTime now,
  ) async {
    final members = [...memberIds]..sort();
    final candidates = await _sharedAccounts(hid, tx: tx);
    return () {
      for (final MapEntry(key: path, value: account) in candidates.entries) {
        if (_sameSet(_stringList(account['visibleTo']), members)) continue;
        tx.write(path, {
          'visibleTo': members,
          'updatedAt': now,
          'updatedBy': 'system',
        }, merge: true);
      }
    };
  }

  /// After a join to [hid] has committed: rewrites the history of every
  /// joint and shared account whose history does not match its
  /// `visibleTo` yet, so the partner's first look is complete without
  /// waiting for Eventarc. Best effort; the account events repair anything
  /// this leaves. Returns the accounts it synced.
  Future<int> syncAfterJoin(String hid) async {
    var synced = 0;
    for (final MapEntry(key: path, value: data) in (await _sharedAccounts(
      hid,
    )).entries) {
      if (_applied(data)) continue;
      final result = await sync(hid, path.split('/').last);
      if (result.outcome == VisibilityOutcome.synced) synced++;
    }
    return synced;
  }

  /// Joint accounts and shared personal accounts of [hid], by path.
  Future<Map<String, Map<String, Object?>>> _sharedAccounts(
    String hid, {
    DocumentTransaction? tx,
  }) async {
    final accounts = 'households/$hid/accounts';
    Future<List<StoredDocument>> where(String field, Object value) => tx != null
        ? tx.whereEquals(accounts, field, value, limit: 500)
        : _store.pageWhereEquals(accounts, field, value, limit: 500);
    return {
      for (final doc in [
        ...await where('scope', 'joint'),
        ...await where('sharedWithPartner', true),
      ])
        doc.path: doc.data,
    };
  }

  // ------------------------------------------------------------- the run

  /// Claims the account for [runId]. Returns the `visibleTo` to rewrite
  /// for, or the outcome when there is nothing for this run to do.
  Future<Object> _claim(String accountPath, String runId) =>
      _store.transaction<Object>((tx) async {
        final account = await tx.read(accountPath);
        if (account == null) return VisibilityOutcome.missing;
        final target = _stringList(account['visibleTo'])..sort();
        // An account always has a reader; none would hide its history from
        // everyone, so it is left alone.
        if (target.isEmpty) return VisibilityOutcome.missing;
        final running = _map(account['visibilitySync']);
        final now = _clock.now().toUtc();
        if (running != null && _leaseLive(running, now)) {
          return VisibilityOutcome.busy;
        }
        if (running == null && _applied(account)) {
          return VisibilityOutcome.upToDate;
        }
        tx.write(accountPath, {
          'visibilitySync': _syncMap(runId, target, now, done: 0, total: null),
        }, merge: true);
        return target;
      });

  /// Whether the history of [account] was last rewritten for exactly its
  /// current `visibleTo`.
  static bool _applied(Map<String, Object?> account) {
    final applied = account['visibilityAppliedTo'];
    return applied is List &&
        _sameSet(_stringList(applied), _stringList(account['visibleTo']));
  }

  /// One pass over the history for the account's [target] `visibleTo`.
  /// Returns the transactions changed, or null when the lease was lost.
  Future<int?> _pass(
    String hid,
    String accountPath,
    String runId,
    List<String> target,
  ) async {
    final transactions = 'households/$hid/transactions';
    final accountId = accountPath.split('/').last;
    var total = 0;
    for (final field in _accountFields) {
      total += await _store.countWhereEquals(transactions, field, accountId);
    }
    var done = 0;
    var rewritten = 0;
    if (!await _progress(accountPath, runId, target, done, total)) return null;

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
        // This account counts with the visibleTo the pass is for (a change
        // during the run gets its own pass); the other account of a
        // transfer is read fresh for every page.
        final visibleTo = <String, List<String>?>{accountId: target};
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
        done += page.length;
        // The page's writes commit only while this run still holds the
        // lease, in the same transaction that checks it: a run whose lease
        // ran out and was taken over writes nothing more (Codex review).
        if (!await _progress(
          accountPath,
          runId,
          target,
          done,
          total,
          writes: writes,
        )) {
          return null;
        }
        rewritten += writes.length;
        if (page.length < pageSize) break;
        after = page.last.path.split('/').last;
      }
    }
    return rewritten;
  }

  /// In one transaction: checks that [runId] still holds the account's
  /// lease, applies [writes] (a page of history), writes progress and renews
  /// the lease. Returns false, writing nothing, when another run holds the
  /// account now.
  Future<bool> _progress(
    String accountPath,
    String runId,
    List<String> target,
    int done,
    int total, {
    List<DocumentWrite> writes = const [],
  }) => _store.transaction((tx) async {
    final account = await tx.read(accountPath);
    if (!_holds(account, runId)) return false;
    for (final w in writes) {
      tx.write(w.path, w.data, merge: w.merge);
    }
    tx.write(accountPath, {
      'visibilitySync': _syncMap(
        runId,
        target,
        _clock.now().toUtc(),
        done: done,
        total: total < done ? done : total,
      ),
    }, merge: true);
    return true;
  });

  /// Records [target] as applied when it is still the account's
  /// `visibleTo` and releases the lease. Returns null when finished, or the
  /// account's new `visibleTo` to rewrite for.
  ///
  /// Throws [_LeaseLost] when another run holds the account now: then this
  /// run records nothing.
  Future<List<String>?> _finish(
    String accountPath,
    String runId,
    List<String> target,
  ) => _store.transaction((tx) async {
    final account = await tx.read(accountPath);
    if (account == null) return null;
    if (!_holds(account, runId)) throw const _LeaseLost();
    final current = _stringList(account['visibleTo'])..sort();
    final now = _clock.now().toUtc();
    if (current.isNotEmpty && !_sameSet(current, target)) {
      tx.write(accountPath, {
        'visibilitySync': _syncMap(runId, current, now, done: 0, total: null),
      }, merge: true);
      return current;
    }
    // A whole-document write (safe inside the transaction): a merge write
    // does not clear a map field set to null.
    tx.write(accountPath, {
      ...account,
      'visibilityAppliedTo': target,
      'visibilitySync': null,
    });
    return null;
  });

  /// Drops [runId]'s claim on the account, keeping what was applied, so the
  /// work stays pending for the next delivery. Best effort: when this fails
  /// too, the lease simply runs out.
  Future<void> _release(String accountPath, String runId) async {
    try {
      await _store.transaction((tx) async {
        final account = await tx.read(accountPath);
        if (account == null) return;
        final running = _map(account['visibilitySync']);
        if (running == null || running['runId'] != runId) return;
        tx.write(accountPath, {...account, 'visibilitySync': null});
      });
    } on Object catch (e) {
      _log.warning('could not release the visibility lease', e);
    }
  }

  /// Whether [account]'s running rewrite is [runId]'s.
  static bool _holds(Map<String, Object?>? account, String runId) =>
      _map(account?['visibilitySync'])?['runId'] == runId;

  Map<String, Object?> _syncMap(
    String runId,
    List<String> target,
    DateTime now, {
    required int done,
    required int? total,
  }) => {
    'runId': runId,
    'target': target,
    'leaseUntil': now.add(lease),
    'done': done,
    'total': total,
  };

  /// A lease counts only while it runs and only as far as this job ever
  /// sets one: a `leaseUntil` beyond `now + lease` was not written by a run
  /// and is ignored (defence in depth; the rules refuse the field from the
  /// phone).
  bool _leaseLive(Map<String, Object?> running, DateTime now) {
    final until = running['leaseUntil'];
    return until is DateTime &&
        until.isAfter(now) &&
        !until.isAfter(now.add(lease));
  }

  String _newRunId() => List.generate(
    8,
    (_) => _random.nextInt(256),
  ).map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}

// ------------------------------------------------------------------ route

/// The Shelf handler for [accountVisibilityPath].
///
/// Answers 200 with the [VisibilityResult]; 429 when another run holds the
/// account, so Eventarc delivers the event again later; 204 for an event
/// that names no account (dropped: a retry would not help); 405 for a
/// non-POST; and 503 when Firestore is unavailable, so Eventarc retries.
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
    if (result.outcome == VisibilityOutcome.busy) {
      // Not acknowledged: if the run holding the lease dies, this delivery
      // is what brings the work back once the lease runs out. A retry
      // after the run finishes answers `upToDate` (Codex review, PR #33).
      return Response(
        429,
        body: jsonEncode(result.toJson()),
        headers: {'content-type': 'application/json', 'retry-after': '30'},
      );
    }
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

/// A run found its lease taken over by another run.
final class _LeaseLost implements Exception {
  const new();
}

// ---------------------------------------------------------------- helpers

Map<String, Object?>? _map(Object? value) =>
    value is Map<String, Object?> ? value : null;

List<String> _stringList(Object? value) =>
    value is List ? value.whereType<String>().toList() : <String>[];

bool _sameSet(Iterable<String> a, Iterable<String> b) {
  final sa = a.toSet();
  final sb = b.toSet();
  return sa.length == sb.length && sa.containsAll(sb);
}
