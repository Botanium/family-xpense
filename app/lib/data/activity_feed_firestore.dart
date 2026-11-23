// The Firestore adapter behind `ActivityFeed` (DATA_MODEL 2.5, 6, 7). Only
// the composition root names this file.
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import 'package:xpense_app/data/activity_feed.dart';
import 'package:xpense_app/data/household_repository.dart';
import 'package:xpense_app/data/mappers/transaction_mapper.dart';
import 'package:xpense_app/data/transactions_repository.dart';

/// [ActivityFeed] over `households/{hid}/transactions`.
///
/// Each [watch] follows the household membership and keeps one snapshot
/// listener with metadata changes, so the window is served from the cache
/// at once (offline too), marks entries whose write is still on the phone,
/// and updates on every write. A longer window is a new listener with a
/// larger limit; the cache serves the part already read.
final class FirestoreActivityFeed implements ActivityFeed {
  /// Creates the adapter. [_firestore] must already point at the emulator
  /// when one is used (the household adapter does that).
  new({
    required this._firestore,
    required this._households,
    required this._uid,
  });

  /// The adapter on [FirebaseFirestore.instance] and [FirebaseAuth.instance].
  factory connect({required HouseholdRepository households}) =>
      FirestoreActivityFeed(
        firestore: FirebaseFirestore.instance,
        households: households,
        uid: () => FirebaseAuth.instance.currentUser?.uid,
      );

  final FirebaseFirestore _firestore;
  final HouseholdRepository _households;
  final String? Function() _uid;

  @override
  Stream<ActivityWindow> watch(ActivityQuery query) {
    StreamSubscription<Membership>? membershipSub;
    StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? querySub;
    String? scope;
    late final StreamController<ActivityWindow> out;

    void listen(String hid, String uid, {required bool serverFilter}) {
      unawaited(querySub?.cancel());
      querySub =
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
              .listen(
                (snapshot) {
                  if (out.isClosed) return;
                  out.add(
                    windowFrom(
                      snapshot,
                      query: query,
                      filteredOnPhone: !serverFilter && hasFilter(query),
                    ),
                  );
                },
                onError: (Object e, StackTrace s) {
                  if (out.isClosed) return;
                  // No index for the filter on this backend: read the "All"
                  // window, which has one, and filter here.
                  if (serverFilter &&
                      hasFilter(query) &&
                      e is FirebaseException &&
                      e.code == 'failed-precondition') {
                    listen(hid, uid, serverFilter: false);
                    return;
                  }
                  _report(e, s);
                  out.addError(failureOf(e), s);
                },
              );
    }

    out = StreamController<ActivityWindow>(
      onListen: () {
        membershipSub = _households.watchMembership().listen(
          (membership) {
            final hid = membership is InHousehold
                ? membership.household.id
                : null;
            final uid = hid == null ? null : _uid();
            final next = hid == null || uid == null ? null : '$hid/$uid';
            if (next == scope && querySub != null) return;
            scope = next;
            if (hid == null || uid == null) {
              unawaited(querySub?.cancel());
              querySub = null;
              out.add(const ActivityWindow(entries: [], hasMore: false));
              return;
            }
            listen(hid, uid, serverFilter: true);
          },
          onError: (Object e, StackTrace s) {
            _report(e, s);
            if (!out.isClosed) out.addError(failureOf(e), s);
          },
        );
      },
      onCancel: () async {
        await querySub?.cancel();
        await membershipSub?.cancel();
      },
    );
    return out.stream;
  }

  static void _report(Object e, StackTrace s) => FlutterError.reportError(
    FlutterErrorDetails(
      exception: e,
      stack: s,
      library: 'activity_feed_firestore',
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
  static ActivityFeedFailure failureOf(Object error) => switch (error) {
    FirebaseException(code: 'permission-denied') => const ActivityNotAllowed(),
    FirebaseException(:final code) => ActivityReadFailed(code),
    _ => ActivityReadFailed(error.runtimeType.toString()),
  };
}
