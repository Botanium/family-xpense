// The Firestore adapter of `FxRepository`. Only the composition root and
// tests name this file.
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:xpense_app/data/fx_repository.dart';
import 'package:xpense_app/data/household_repository.dart';
import 'package:xpense_app/data/read/home_reader_firebase.dart'
    show isTransientDenial;
import 'package:xpense_app/data/read/scoped_listen.dart';
import 'package:xpense_app/services/clock.dart';
import 'package:xpense_shared/xpense_shared.dart';

/// An [FxRepository] over `households/{hid}/fxRates` and the household's
/// `rateKind`, following the signed-in member's household.
final class FirebaseFxRepository implements FxRepository {
  /// Creates the adapter. The Firestore instance must already point at the
  /// emulator when one is used (the household adapter does that).
  new({
    required this._auth,
    required this._firestore,
    required this._households,
    Clock? clock,
  }) : _clock = clock ?? const Clock();

  /// The adapter on [FirebaseFirestore.instance] and [FirebaseAuth.instance].
  factory connect({required HouseholdRepository households}) =>
      FirebaseFxRepository(
        auth: FirebaseAuth.instance,
        firestore: FirebaseFirestore.instance,
        households: households,
      );

  /// How long a write waits for Firestore before it counts as queued
  /// offline.
  static const Duration writeAckTimeout = Duration(seconds: 8);

  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;
  final HouseholdRepository _households;
  final Clock _clock;

  ({String hid, String uid})? get _scope {
    final membership = _households.current;
    final uid = _auth.currentUser?.uid;
    return membership is InHousehold && uid != null
        ? (hid: membership.household.id, uid: uid)
        : null;
  }

  Stream<T> _scoped<T>(
    T empty,
    Stream<T> Function(({String hid, String uid}) scope) build,
  ) => scopedListen<({String hid, String uid}), T>(
    scopes: _households.watchMembership().map((m) {
      final uid = _auth.currentUser?.uid;
      return m is InHousehold && uid != null
          ? (hid: m.household.id, uid: uid)
          : null;
    }),
    build: build,
    empty: empty,
    isTransient: isTransientDenial,
  );

  DocumentReference<Map<String, dynamic>> _household(String hid) =>
      _firestore.collection('households').doc(hid);

  @override
  Stream<List<DailyRate>> watchRates() => _scoped(
    const <DailyRate>[],
    (scope) =>
        ratesSince(
          _household(scope.hid).collection('fxRates'),
          rateDayOf(_clock.now().subtract(rateHistoryWindow)),
        ).snapshots().map(
          (snapshot) => [
            for (final doc in snapshot.docs.reversed)
              ?dailyRateFromFirestore(doc.id, doc.data()),
          ],
        ),
  );

  @override
  Stream<RateKind> watchRateKind() => _scoped(
    RateKind.market,
    (scope) =>
        _household(scope.hid)
            .snapshots()
            .map((doc) => RateKind.fromWire(doc.data()?['rateKind'])),
  );

  @override
  Future<Result<void, FxFailure>> setRate(String day, FxRate rate) async {
    final scope = _scope;
    if (scope == null) return const Err(FxNotAllowed());
    if (!isRateDay(day) || rate.pair != FxPair.usdIqd) {
      return const Err(FxBadDay());
    }
    const what = 'saving a daily rate';
    try {
      final kind = await _rateKind(scope.hid);
      final batch = _firestore.batch()
        ..set(_household(scope.hid).collection('fxRates').doc(day), {
          'usdIqd': rate.rateString,
          'kind': kind.wire,
          'enteredBy': scope.uid,
          'enteredAt': FieldValue.serverTimestamp(),
        });
      await _commit(batch, what);
      return const Ok(null);
    } on FirebaseException catch (e, s) {
      return Err(_failure(e, s, what));
    }
  }

  @override
  Future<Result<void, FxFailure>> setRateKind(RateKind kind) async {
    final scope = _scope;
    if (scope == null) return const Err(FxNotAllowed());
    const what = 'saving the rate label';
    try {
      final batch = _firestore.batch()
        ..update(_household(scope.hid), {'rateKind': kind.wire});
      await _commit(batch, what);
      return const Ok(null);
    } on FirebaseException catch (e, s) {
      return Err(_failure(e, s, what));
    }
  }

  /// The household's label, from the cache first so an offline answer
  /// does not wait for the server.
  Future<RateKind> _rateKind(String hid) async {
    for (final source in const [Source.cache, Source.server]) {
      try {
        final doc = await _household(hid).get(GetOptions(source: source));
        if (doc.exists) return RateKind.fromWire(doc.data()?['rateKind']);
      } on FirebaseException {
        // Not cached, or offline: try the other source.
      }
    }
    return RateKind.market;
  }

  Future<void> _commit(WriteBatch batch, String what) async {
    final commit = batch.commit();
    try {
      await commit.timeout(writeAckTimeout);
    } on TimeoutException {
      // Offline: the batch stays queued and shows from the cache at once.
      unawaited(
        commit.then<void>(
          (_) {},
          onError: (Object e, StackTrace s) => _report(e, s, what),
        ),
      );
    }
  }

  static FxFailure _failure(FirebaseException e, StackTrace s, String what) {
    _report(e, s, what);
    return switch (e.code) {
      'permission-denied' || 'unauthenticated' => const FxNotAllowed(),
      _ => FxUnknown(e.code),
    };
  }

  static void _report(Object error, StackTrace stack, String what) =>
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stack,
          library: 'fx_repository',
          context: ErrorDescription('while $what'),
        ),
      );
}

/// The day documents of [fxRates] from [fromDay] on, oldest first.
/// Firestore (and its emulator) cannot scan document ids newest first, so
/// callers read ascending and take from the end (WP-13 hand-over).
Query<Map<String, dynamic>> ratesSince(
  CollectionReference<Map<String, dynamic>> fxRates,
  String fromDay,
) => fxRates
    .where(FieldPath.documentId, isGreaterThanOrEqualTo: fromDay)
    .orderBy(FieldPath.documentId);

/// Reads a stored day's rate (DATA_MODEL 2.13), or null when it is
/// malformed.
DailyRate? dailyRateFromFirestore(String day, Map<String, dynamic> data) {
  final rate = switch (data['usdIqd']) {
    final String value => FxRate.forPair(FxPair.usdIqd, value).valueOrNull,
    _ => null,
  };
  if (rate == null || !isRateDay(day)) return null;
  return DailyRate(
    day: day,
    rate: rate,
    kind: RateKind.fromWire(data['kind']),
    enteredBy: switch (data['enteredBy']) {
      final String uid => uid,
      _ => null,
    },
  );
}
