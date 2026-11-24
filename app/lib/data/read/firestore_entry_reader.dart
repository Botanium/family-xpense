// [EntryReader] over Firestore: snapshot listeners on one
// transaction and its revisions. The cache answers first, so the screen
// works offline; a server timestamp still pending reads as null. A
// listener the rules refuse is started again (`scoped_listen.dart`).
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:xpense_app/data/household_repository.dart';
import 'package:xpense_app/data/mappers/transaction_mapper.dart';
import 'package:xpense_app/data/read/entry_reader.dart';
import 'package:xpense_app/data/read/scoped_listen.dart';
import 'package:xpense_app/data/write/ledger_store.dart';

/// [EntryReader] over Firestore.
final class FirestoreEntryReader implements EntryReader {
  /// Creates the reader. [_scopes] says who reads in which household: the
  /// current scope now and on every change, null outside a household.
  new({required this._firestore, required this._scopes});

  /// The reader for the signed-in member of [households]' current
  /// household.
  factory connect({
    required FirebaseAuth auth,
    required FirebaseFirestore firestore,
    required HouseholdRepository households,
  }) => FirestoreEntryReader(
    firestore: firestore,
    scopes: () => households.watchMembership().map((membership) {
      final uid = auth.currentUser?.uid;
      return switch (membership) {
        InHousehold(:final household) when uid != null => LedgerScope(
          householdId: household.id,
          uid: uid,
        ),
        _ => null,
      };
    }),
  );

  final FirebaseFirestore _firestore;
  final Stream<LedgerScope?> Function() _scopes;

  DocumentReference<Map<String, dynamic>> _doc(LedgerScope scope, String id) =>
      _firestore
          .collection('households')
          .doc(scope.householdId)
          .collection('transactions')
          .doc(id);

  /// A listener on the current scope that is started again while the
  /// rules refuse it (a household founded a moment ago; see
  /// [scopedListen]), reading [empty] meanwhile; other Firestore errors,
  /// and a refusal after the last retry, read as [empty].
  Stream<T> _watch<T>(
    T empty,
    Stream<T> Function(DocumentReference<Map<String, dynamic>> doc) build,
    String id,
  ) => scopedListen<LedgerScope, T>(
    scopes: _scopes(),
    build: (scope) => build(_doc(scope, id)),
    empty: empty,
    emptyWhileRetrying: true,
  ).transform(_refusedAs<T>(empty));

  @override
  Stream<EntryRecord?> watchEntry(String id) => _watch<EntryRecord?>(
    null,
    (doc) => doc.snapshots(includeMetadataChanges: true).map((snap) {
      final data = snap.data();
      if (data == null) return null;
      final plain = _plain(data);
      final txn = transactionFromFields(id, plain);
      if (txn == null) return null;
      return EntryRecord(
        txn: txn,
        createdAt: switch (plain['createdAt']) {
          final DateTime t => t,
          _ => null,
        },
        syncing: snap.metadata.hasPendingWrites,
      );
    }),
    id,
  ).distinct();

  @override
  Stream<List<EntryRevision>> watchRevisions(String id) =>
      _watch<List<EntryRevision>>(
        const [],
        (doc) => doc
            .collection('revisions')
            .orderBy('rev', descending: true)
            .snapshots()
            .map(
              (snap) => newestFirst([
                for (final d in snap.docs)
                  ?revisionFromFields(d.id, _plain(d.data())),
              ]),
            ),
        id,
      );

  /// Turns any other Firestore error into [value]: the entry reads as
  /// "not found".
  static StreamTransformer<T, T> _refusedAs<T>(T value) =>
      StreamTransformer.fromHandlers(
        handleError: (error, stack, sink) => error is FirebaseException
            ? sink.add(value)
            : sink.addError(error, stack),
      );

  static Map<String, Object?> _plain(Map<String, dynamic> data) => {
    for (final e in data.entries) e.key: _plainValue(e.value),
  };

  static Object? _plainValue(Object? value) => switch (value) {
    final Timestamp t => t.toDate().toUtc(),
    final Map<Object?, Object?> m => {
      for (final e in m.entries) '${e.key}': _plainValue(e.value),
    },
    final List<Object?> l => [for (final v in l) _plainValue(v)],
    final v => v,
  };
}
