import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:xpense_app/data/household_repository.dart';
import 'package:xpense_app/data/mappers/transaction_mapper.dart';
import 'package:xpense_app/data/read/home_reader.dart';
import 'package:xpense_app/data/transactions_repository.dart';

/// A `HomeReader` over Firestore, following the signed-in member's
/// household.
final class FirebaseHomeReader implements HomeReader {
  /// Creates the reader. The Firestore instance must already point at the
  /// emulator when one is used.
  new({
    required this._auth,
    required this._firestore,
    required this._households,
  });

  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;
  final HouseholdRepository _households;

  @override
  Stream<List<LedgerTransaction>> watchRange({
    required String fromDay,
    required String toDay,
  }) => _scoped(
    (transactions, uid) => transactions
        // DATA_MODEL 6: visibleTo + deletedAt + occurredOn asc. Deleted
        // entries are left out by the query: a delete still waiting for the
        // server reads `deletedAt` as null in a snapshot but no longer
        // matches the filter in the cache, so it stops counting at once. A
        // month holds a few hundred entries, so nothing is paged.
        .where('deletedAt', isNull: true)
        .where('occurredOn', isGreaterThanOrEqualTo: fromDay)
        .where('occurredOn', isLessThanOrEqualTo: toDay)
        .orderBy('occurredOn')
        .snapshots()
        .map((snapshot) => _live(snapshot, uid)),
  );

  @override
  Stream<List<LedgerTransaction>> watchRecent({required int limit}) => _scoped(
    (transactions, uid) => transactions
        // DATA_MODEL 6: visibleTo + deletedAt + occurredAt desc. Every write
        // stores `deletedAt: null` on a live entry, so deleted ones never
        // use up the limit.
        .where('deletedAt', isNull: true)
        .orderBy('occurredAt', descending: true)
        .limit(limit)
        .snapshots()
        .map((snapshot) => _live(snapshot, uid)),
  );

  static List<LedgerTransaction> _live(
    QuerySnapshot<Map<String, dynamic>> snapshot,
    String uid,
  ) => [
    for (final doc in snapshot.docs)
      if (transactionFromFields(doc.id, _plain(doc.data())) case final t?
          when t.visibleTo.contains(uid) && !t.deleted)
        t,
  ];

  static Map<String, Object?> _plain(Map<String, dynamic> data) => {
    for (final e in data.entries) e.key: _plainValue(e.value),
  };

  static Object? _plainValue(Object? value) => switch (value) {
    final Timestamp t => t.toDate().toUtc(),
    final Map<Object?, Object?> m => {
      for (final e in m.entries) '${e.key}': _plainValue(e.value),
    },
    final List<Object?> l => [for (final v in l) _plainValue(v)],
    _ => value,
  };

  /// Runs [build] on the current household's `transactions`, already
  /// filtered by `visibleTo`, and restarts it whenever the member or the
  /// household changes. Outside a household it emits an empty list.
  Stream<List<LedgerTransaction>> _scoped(
    Stream<List<LedgerTransaction>> Function(
      Query<Map<String, dynamic>> transactions,
      String uid,
    )
    build,
  ) {
    late final StreamController<List<LedgerTransaction>> controller;
    StreamSubscription<Membership>? membership;
    StreamSubscription<List<LedgerTransaction>>? inner;
    String? scopeKey;
    void follow(Membership m) {
      final uid = _auth.currentUser?.uid;
      final hid = m is InHousehold ? m.household.id : null;
      final key = hid == null || uid == null ? null : '$hid/$uid';
      if (key == scopeKey && inner != null) return;
      scopeKey = key;
      unawaited(inner?.cancel());
      inner = null;
      if (hid == null || uid == null) {
        controller.add(const []);
        return;
      }
      final transactions = _firestore
          .collection('households')
          .doc(hid)
          .collection('transactions')
          .where('visibleTo', arrayContains: uid);
      inner = build(
        transactions,
        uid,
      ).listen(controller.add, onError: controller.addError);
    }

    controller = StreamController<List<LedgerTransaction>>(
      onListen: () {
        membership = _households.watchMembership().listen(
          follow,
          onError: controller.addError,
        );
      },
      onCancel: () async {
        await membership?.cancel();
        await inner?.cancel();
      },
    );
    return controller.stream;
  }
}
