// [TransactionsReader] over Firestore: snapshot listeners on one
// transaction and its revisions. The cache answers first, so the screen
// works offline; a server timestamp still pending reads as null.
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:xpense_app/data/household_repository.dart';
import 'package:xpense_app/data/mappers/transaction_mapper.dart';
import 'package:xpense_app/data/transactions_reader.dart';
import 'package:xpense_app/data/write/ledger_store.dart';

/// [TransactionsReader] over Firestore.
final class FirestoreTransactionsReader implements TransactionsReader {
  /// Creates the reader. [_scope] says who reads in which household.
  new({required this._firestore, required this._scope});

  /// The reader for the signed-in member of [households]' current
  /// household.
  factory connect({
    required FirebaseAuth auth,
    required FirebaseFirestore firestore,
    required HouseholdRepository households,
  }) => FirestoreTransactionsReader(
    firestore: firestore,
    scope: () {
      final uid = auth.currentUser?.uid;
      return switch (households.current) {
        InHousehold(:final household) when uid != null => LedgerScope(
          householdId: household.id,
          uid: uid,
        ),
        _ => null,
      };
    },
  );

  final FirebaseFirestore _firestore;
  final LedgerScope? Function() _scope;

  DocumentReference<Map<String, dynamic>>? _doc(String id) {
    final hid = _scope()?.householdId;
    if (hid == null) return null;
    return _firestore
        .collection('households')
        .doc(hid)
        .collection('transactions')
        .doc(id);
  }

  @override
  Stream<EntryRecord?> watchEntry(String id) {
    final ref = _doc(id);
    if (ref == null) return Stream.value(null);
    return ref
        .snapshots(includeMetadataChanges: true)
        .map((snap) {
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
        })
        // A refused read (no longer visible) reads as "not found".
        .transform(_refusedAs<EntryRecord?>(null))
        .distinct();
  }

  @override
  Stream<List<EntryRevision>> watchRevisions(String id) {
    final ref = _doc(id);
    if (ref == null) return Stream.value(const []);
    return ref
        .collection('revisions')
        .orderBy('rev', descending: true)
        .snapshots()
        .map(
          (snap) => newestFirst([
            for (final doc in snap.docs)
              ?revisionFromFields(doc.id, _plain(doc.data())),
          ]),
        )
        .transform(_refusedAs<List<EntryRevision>>(const []));
  }

  /// Turns a Firestore error (the rules refused the read) into [value].
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
