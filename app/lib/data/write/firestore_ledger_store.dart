// The Firestore `LedgerStore` (DATA_MODEL 2, 3, 5). Reads come from the
// phone's cache first, so a save works offline against what the phone
// already knows; a plan is committed as one `WriteBatch` whose balance and
// loan changes are `FieldValue.increment`s. `runTransaction` is never used:
// it fails offline (D-13).
import 'dart:async';
import 'dart:math';

import 'package:clock/clock.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:xpense_app/data/household_repository.dart';
import 'package:xpense_app/data/mappers/transaction_mapper.dart';
import 'package:xpense_app/data/transactions_repository.dart';
import 'package:xpense_app/data/write/ledger_store.dart';
import 'package:xpense_shared/xpense_shared.dart';

/// [LedgerStore] over Firestore.
final class FirestoreLedgerStore implements LedgerStore {
  /// Creates the store. [scope] says who is writing in which household;
  /// [_firestore] must already point at the emulator when one is used.
  new({
    required this._firestore,
    required this._scope,
    Clock? clock,
    Random? random,
    this.writeAckTimeout = defaultWriteAckTimeout,
  }) : _clock = clock ?? const Clock(),
       _random = random ?? Random.secure();

  /// The store for the signed-in member of [households]' current household.
  factory connect({
    required FirebaseAuth auth,
    required FirebaseFirestore firestore,
    required HouseholdRepository households,
    Duration writeAckTimeout = defaultWriteAckTimeout,
  }) => FirestoreLedgerStore(
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
    writeAckTimeout: writeAckTimeout,
  );

  /// How long a commit waits for the server before it counts as queued.
  static const Duration defaultWriteAckTimeout = Duration(seconds: 3);

  /// How long [commit] waits for the server before returning
  /// [WriteAck.queued]. The batch is already on the phone by then.
  final Duration writeAckTimeout;

  final FirebaseFirestore _firestore;
  final LedgerScope? Function() _scope;
  final Clock _clock;
  final Random _random;

  @override
  LedgerScope? get scope => _scope();

  @override
  DateTime now() => _clock.now();

  @override
  String newId() => uuidV7(_clock.now(), _random);

  // ---------------------------------------------------------------- reads

  @override
  Future<LedgerHousehold?> household() async {
    final hid = scope?.householdId;
    if (hid == null) return null;
    final data = await _read(_firestore.collection('households').doc(hid));
    final base = Currency.tryParse('${data?['baseCurrency']}');
    if (data == null || base == null) return null;
    return LedgerHousehold(
      baseCurrency: base,
      memberIds: _strings(data['memberIds']),
      rateKind: data['rateKind'] == 'official' ? 'official' : 'market',
    );
  }

  @override
  Future<LedgerAccount?> account(String id) async {
    final data = await _readIn('accounts', id);
    final currency = Currency.tryParse('${data?['currency']}');
    if (data == null || currency == null) return null;
    return LedgerAccount(
      id: id,
      currency: currency,
      visibleTo: _strings(data['visibleTo']),
      joint: data['scope'] == 'joint',
      ownerUid: switch (data['ownerUid']) {
        final String uid => uid,
        _ => null,
      },
    );
  }

  @override
  Future<LedgerCategory?> category(String id) async {
    final data = await _readIn('categories', id);
    if (data == null) return null;
    return LedgerCategory(
      id: id,
      kind: switch (data['kind']) {
        final String kind => kind,
        _ => null,
      },
    );
  }

  @override
  Future<LedgerLoan?> loan(String id) async {
    final data = await _readIn('loans', id);
    final currency = Currency.tryParse('${data?['currency']}');
    if (data == null || currency == null) return null;
    return LedgerLoan(id: id, currency: currency);
  }

  @override
  Future<bool> hasPerson(String id) async =>
      await _readIn('people', id) != null;

  @override
  Future<String?> goalAccount(String id) async =>
      switch ((await _readIn('goals', id))?['accountId']) {
        final String accountId => accountId,
        _ => null,
      };

  /// How far back [rateOn] looks for an earlier day's rate.
  static const Duration rateWindow = Duration(days: 120);

  @override
  Future<DayRate?> rateOn(String day) async {
    final hid = scope?.householdId;
    final date = DateTime.tryParse(day);
    if (hid == null || date == null) return null;
    final from = date.subtract(rateWindow);
    String two(int v) => v.toString().padLeft(2, '0');
    final fromDay = '${from.year}-${two(from.month)}-${two(from.day)}';
    // Ascending and take the last: the emulator cannot scan document ids
    // newest first (WP-13 hand-over).
    final query = _collection(hid, 'fxRates')
        .where(FieldPath.documentId, isGreaterThanOrEqualTo: fromDay)
        .where(FieldPath.documentId, isLessThanOrEqualTo: day)
        .orderBy(FieldPath.documentId);
    QuerySnapshot<Map<String, dynamic>> snapshot;
    try {
      snapshot = await query.get(const GetOptions(source: Source.cache));
      if (snapshot.docs.isEmpty) snapshot = await query.get();
    } on FirebaseException {
      try {
        snapshot = await query.get();
      } on FirebaseException {
        return null;
      }
    }
    for (final doc in snapshot.docs.reversed) {
      final value = doc.data()['usdIqd'];
      if (value is! String) continue;
      final rate = FxRate.forPair(FxPair.usdIqd, value).valueOrNull;
      if (rate == null) continue;
      return DayRate(
        day: doc.id,
        rate: rate,
        kind: switch (doc.data()['kind']) {
          final String kind => kind,
          _ => null,
        },
      );
    }
    return null;
  }

  @override
  Future<LedgerTransaction?> transaction(
    String id, {
    bool fresh = false,
  }) async {
    final hid = scope?.householdId;
    if (hid == null) return null;
    final ref = _collection(hid, 'transactions').doc(id);
    final data = await _read(ref, fresh: fresh);
    return data == null ? null : transactionFromFields(id, _plain(data));
  }

  /// The document's data from the cache, else the server; with [fresh],
  /// from the server, else the cache. Null when neither has it or the
  /// rules refuse it.
  Future<Map<String, dynamic>?> _read(
    DocumentReference<Map<String, dynamic>> ref, {
    bool fresh = false,
  }) async {
    const estimate = ServerTimestampBehavior.estimate;
    final order = fresh
        ? const [Source.server, Source.cache]
        : const [Source.cache, Source.server];
    for (final source in order) {
      try {
        final snapshot = await ref.get(
          GetOptions(source: source, serverTimestampBehavior: estimate),
        );
        if (snapshot.exists) return snapshot.data();
        // The server is the authority: a document it does not have is
        // gone. The cache may simply not hold it yet.
        if (source == Source.server) return null;
      } on FirebaseException {
        // Not in the cache, or offline: try the other source.
      }
    }
    return null;
  }

  Future<Map<String, dynamic>?> _readIn(String collection, String id) {
    final hid = scope?.householdId;
    if (hid == null) return Future.value();
    return _read(_collection(hid, collection).doc(id));
  }

  // -------------------------------------------------------------- writes

  @override
  Future<Result<WriteAck, StoreFailure>> commit(
    LedgerPlan plan, {
    void Function(StoreFailure failure)? onLateFailure,
  }) async {
    final scope = this.scope;
    if (scope == null) {
      return const Err(StoreFailure(StoreFailureKind.denied, 'no-household'));
    }
    final hid = scope.householdId;
    final batch = _firestore.batch();
    final txns = _collection(hid, 'transactions');
    for (final write in plan.writes) {
      switch (write) {
        case TxnCreate(:final id, :final fields):
          batch.set(txns.doc(id), _stored(fields));
        case TxnUpdate(:final id, :final fields):
          batch.update(txns.doc(id), _stored(fields));
        case RevisionCreate(:final txnId, :final id, :final fields):
          batch.set(
            txns.doc(txnId).collection('revisions').doc(id),
            _stored(fields),
          );
      }
    }
    final stamps = {
      'updatedAt': FieldValue.serverTimestamp(),
      'updatedBy': scope.uid,
    };
    // Only the balance and the stamps: never `visibleTo` or the
    // server-only `visibilityAppliedTo` / `visibilitySync` (WP-13).
    plan.effects.accounts.forEach((id, delta) {
      batch.update(_collection(hid, 'accounts').doc(id), {
        'balanceMinor': FieldValue.increment(delta),
        ...stamps,
      });
    });
    plan.effects.loans.forEach((id, delta) {
      batch.update(_collection(hid, 'loans').doc(id), {
        'outstandingMinor': FieldValue.increment(delta),
        ...stamps,
      });
    });

    final Future<void> commit;
    try {
      commit = batch.commit();
    } on FirebaseException catch (e, s) {
      return Err(_failure(e, s));
    }
    try {
      await commit.timeout(writeAckTimeout);
      return const Ok(WriteAck.synced);
    } on TimeoutException {
      // On the phone already; Firestore sends it when it can.
      unawaited(
        commit.then<void>(
          (_) {},
          onError: (Object e, StackTrace s) {
            final failure = e is FirebaseException
                ? _failure(e, s)
                : _unknown(e, s);
            onLateFailure?.call(failure);
          },
        ),
      );
      return const Ok(WriteAck.queued);
    } on FirebaseException catch (e, s) {
      return Err(_failure(e, s));
    }
  }

  // ------------------------------------------------------------- helpers

  CollectionReference<Map<String, dynamic>> _collection(
    String hid,
    String name,
  ) => _firestore.collection('households').doc(hid).collection(name);

  /// [fields] as Firestore stores them: [serverTime] becomes a server
  /// timestamp and `DateTime` a `Timestamp`.
  static Map<String, Object?> _stored(Map<String, Object?> fields) => {
    for (final e in fields.entries) e.key: _storedValue(e.value),
  };

  static Object? _storedValue(Object? value) => switch (value) {
    ServerTime() => FieldValue.serverTimestamp(),
    final DateTime t => Timestamp.fromDate(t),
    final Map<String, Object?> m => _stored(m),
    final List<Object?> l => [for (final v in l) _storedValue(v)],
    _ => value,
  };

  /// Stored data with `Timestamp`s as UTC `DateTime`s, for the mapper.
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

  static List<String> _strings(Object? value) =>
      value is List ? value.whereType<String>().toList() : <String>[];

  static StoreFailure _failure(FirebaseException error, StackTrace stack) {
    _report(error, stack);
    return switch (error.code) {
      'permission-denied' ||
      'unauthenticated' ||
      'not-found' => StoreFailure(StoreFailureKind.denied, error.code),
      _ => StoreFailure(StoreFailureKind.unknown, error.code),
    };
  }

  static StoreFailure _unknown(Object error, StackTrace stack) {
    _report(error, stack);
    return StoreFailure(StoreFailureKind.unknown, '${error.runtimeType}');
  }

  static void _report(Object error, StackTrace stack) =>
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stack,
          library: 'transactions_repository',
          context: ErrorDescription('while writing transactions'),
        ),
      );
}
