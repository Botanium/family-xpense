// The Firestore adapter behind `ActivityReader` (DATA_MODEL 2.5, 6, 7). Only
// the composition root names this file.
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import 'package:xpense_app/data/household_repository.dart';
import 'package:xpense_app/data/mappers/transaction_mapper.dart';
import 'package:xpense_app/data/read/activity_reader.dart';
import 'package:xpense_app/data/read/scoped_listen.dart';
import 'package:xpense_app/data/transactions_repository.dart';

/// [ActivityReader] over `households/{hid}/transactions`.
///
/// Each [watch] follows the household membership and keeps one snapshot
/// listener with metadata changes, so the window is served from the cache
/// at once (offline too), marks entries whose write is still on the phone,
/// and updates on every write. A longer window is a new listener with a
/// larger limit; the cache serves the part already read.
final class FirestoreActivityReader implements ActivityReader {
  /// Creates the adapter. [_firestore] must already point at the emulator
  /// when one is used (the household adapter does that).
  new({
    required this._firestore,
    required this._households,
    required this._uid,
  });

  /// The adapter on [FirebaseFirestore.instance] and [FirebaseAuth.instance].
  factory connect({required HouseholdRepository households}) =>
      FirestoreActivityReader(
        firestore: FirebaseFirestore.instance,
        households: households,
        uid: () => FirebaseAuth.instance.currentUser?.uid,
      );

  final FirebaseFirestore _firestore;
  final HouseholdRepository _households;
  final String? Function() _uid;

  @override
  Stream<ActivityWindow> watch(ActivityQuery query) => scoped(
    membership: _households.watchMembership(),
    uid: _uid,
    query: query,
    open: (hid, uid, {required serverFilter}) =>
        buildQuery(
              _firestore
                  .collection('households')
                  .doc(hid)
                  .collection('transactions'),
              uid: uid,
              query: query,
              serverFilter: serverFilter,
            )
            .snapshots(includeMetadataChanges: true)
            .map(
              (snapshot) => windowFrom(
                snapshot,
                query: query,
                filteredOnPhone: !serverFilter && hasFilter(query),
              ),
            ),
  );

  /// The window for [query], following [membership]: one listener from
  /// [open] per household and member, restarted when they change
  /// ([scopedListen]).
  ///
  /// - No index for a filter (`failed-precondition`): reads the "All"
  ///   window and filters on the phone.
  /// - `permission-denied`: right after a household is created or joined,
  ///   the membership can arrive before the server has accepted it, so the
  ///   first listen is refused. It is tried again with backoff
  ///   ([retries] times from [retryDelay]) while the scope is unchanged
  ///   (Codex review, PR #38).
  /// - Any other error ends the listener and is reported as an
  ///   [ActivityReadFailure]; the same scope emitted again listens anew.
  @visibleForTesting
  static Stream<ActivityWindow> scoped({
    required Stream<Membership> membership,
    required String? Function() uid,
    required ActivityQuery query,
    required Stream<ActivityWindow> Function(
      String hid,
      String uid, {
      required bool serverFilter,
    })
    open,
    int retries = scopedListenRetries,
    Duration retryDelay = scopedListenRetryDelay,
  }) => scopedListen<({String hid, String uid}), ActivityWindow>(
    scopes: membership.map((m) {
      final hid = m is InHousehold ? m.household.id : null;
      final member = hid == null ? null : uid();
      return hid == null || member == null ? null : (hid: hid, uid: member);
    }),
    build: (scope) => _withIndexFallback(
      query,
      ({required serverFilter}) =>
          open(scope.hid, scope.uid, serverFilter: serverFilter),
    ),
    empty: const ActivityWindow(entries: [], hasMore: false),
    retries: retries,
    retryDelay: retryDelay,
  ).transform(
    StreamTransformer.fromHandlers(
      handleError: (error, stack, sink) {
        _report(error, stack);
        sink.addError(failureOf(error), stack);
      },
    ),
  );

  /// [open] with the type or member filter on the server, falling back to
  /// filtering on the phone when Firestore has no index for it.
  static Stream<ActivityWindow> _withIndexFallback(
    ActivityQuery query,
    Stream<ActivityWindow> Function({required bool serverFilter}) open,
  ) {
    if (!hasFilter(query)) return open(serverFilter: true);
    late final StreamController<ActivityWindow> out;
    StreamSubscription<ActivityWindow>? inner;
    void listen({required bool serverFilter}) {
      inner = open(serverFilter: serverFilter).listen(
        out.add,
        onError: (Object e, StackTrace s) {
          if (serverFilter &&
              e is FirebaseException &&
              e.code == 'failed-precondition') {
            unawaited(inner?.cancel());
            listen(serverFilter: false);
            return;
          }
          out.addError(e, s);
        },
      );
    }

    out = StreamController<ActivityWindow>(
      onListen: () => listen(serverFilter: true),
      onCancel: () => inner?.cancel(),
    );
    return out.stream;
  }

  static void _report(Object e, StackTrace s) => FlutterError.reportError(
    FlutterErrorDetails(
      exception: e,
      stack: s,
      library: 'activity_reader_firestore',
      context: ErrorDescription('while reading Activity'),
    ),
  );

  /// Whether [query] filters beyond the "All" window.
  @visibleForTesting
  static bool hasFilter(ActivityQuery query) =>
      query.types != null || query.whoUid != null;

  /// The query for [query] on [transactions]: always `visibleTo` and
  /// `deletedAt == null`, newest first. With [serverFilter], the type or
  /// member filter too (DATA_MODEL 6).
  @visibleForTesting
  static Query<Map<String, dynamic>> buildQuery(
    CollectionReference<Map<String, dynamic>> transactions, {
    required String uid,
    required ActivityQuery query,
    required bool serverFilter,
  }) {
    var q = transactions.where('visibleTo', arrayContains: uid);
    if (serverFilter) {
      final types = query.types?.map((t) => t.wire).toList()?..sort();
      if (types != null) {
        q = types.length == 1
            ? q.where('type', isEqualTo: types.single)
            : q.where('type', whereIn: types);
      }
      final who = query.whoUid;
      if (who != null) q = q.where('whoUid', isEqualTo: who);
    }
    return q
        .where('deletedAt', isNull: true)
        .orderBy('occurredAt', descending: true)
        .limit(query.limit);
  }

  /// The window for [snapshot].
  @visibleForTesting
  static ActivityWindow windowFrom(
    QuerySnapshot<Map<String, dynamic>> snapshot, {
    required ActivityQuery query,
    required bool filteredOnPhone,
  }) {
    final entries = <LedgerTransaction>[];
    final syncing = <String>{};
    for (final doc in snapshot.docs) {
      final txn = transactionFromFields(doc.id, plainFields(doc.data()));
      // A delete still on the phone may linger for a frame; never show it.
      if (txn == null || txn.deleted || !query.matches(txn)) continue;
      entries.add(txn);
      if (doc.metadata.hasPendingWrites) syncing.add(doc.id);
    }
    return ActivityWindow(
      entries: entries,
      hasMore: snapshot.docs.length >= query.limit,
      fromCache: snapshot.metadata.isFromCache,
      syncing: syncing,
      filteredOnPhone: filteredOnPhone,
    );
  }

  /// Stored data with `Timestamp`s as UTC `DateTime`s, for the mapper.
  @visibleForTesting
  static Map<String, Object?> plainFields(Map<String, dynamic> data) => {
    for (final e in data.entries) e.key: _plain(e.value),
  };

  static Object? _plain(Object? value) => switch (value) {
    final Timestamp t => t.toDate().toUtc(),
    final Map<Object?, Object?> m => {
      for (final e in m.entries) '${e.key}': _plain(e.value),
    },
    final List<Object?> l => [for (final v in l) _plain(v)],
    _ => value,
  };

  /// The typed failure for a read error.
  @visibleForTesting
  static ActivityReadFailure failureOf(Object error) => switch (error) {
    FirebaseException(code: 'permission-denied') => const ActivityNotAllowed(),
    FirebaseException(:final code) => ActivityReadFailed(code),
    _ => ActivityReadFailed(error.runtimeType.toString()),
  };
}
