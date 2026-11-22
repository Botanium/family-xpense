/// [HouseholdReader] over Firestore (`google_cloud_firestore`, the client
/// the admin SDK returns).
///
/// Every member-scoped query carries `where('visibleTo', arrayContains:
/// uid)` (DATA_MODEL 4), and uses only the indexes in
/// `firebase/firestore.indexes.json`.
library;

import 'package:google_cloud_firestore/google_cloud_firestore.dart' as fs;
import 'package:logging/logging.dart';

import 'package:xpense_agent/tools/household_reader.dart';
import 'package:xpense_agent/tools/local_day.dart';

final _log = Logger('xpense.runtime.reader');

/// Reads household data with admin rights, filtered per member.
final class FirestoreHouseholdReader implements HouseholdReader {
  /// Creates a reader over [_db].
  new(this._db, {this.maxTransactions = 5000});

  final fs.Firestore _db;

  /// Upper bound on transactions read per query.
  final int maxTransactions;

  /// How far back a missing day's rate is looked for.
  static const rateLookbackDays = 60;

  String _h(String hid) => 'households/$hid';

  Future<T> _guard<T>(String op, Future<T> Function() body) async {
    try {
      return await body();
    } on Exception catch (e) {
      _log.warning('$op failed: ${e.runtimeType}');
      throw HouseholdUnavailable(op, e);
    }
  }

  Future<List<fs.QueryDocumentSnapshot<fs.DocumentData>>> _visible(
    String hid,
    String collection,
    String uid,
  ) async =>
      (await _db
              .collection('${_h(hid)}/$collection')
              .where('visibleTo', fs.WhereFilter.arrayContains, uid)
              .get())
          .docs;

  @override
  Future<HouseholdProfile?> profile(String hid) => _guard('profile', () async {
    final snap = await _db.doc(_h(hid)).get();
    final d = snap.data();
    if (d == null) return null;
    return HouseholdProfile(
      hid: hid,
      baseCurrency: _str(d['baseCurrency']) ?? 'USD',
      memberIds: [
        for (final m in _list(d['memberIds']))
          if (m is String) m,
      ],
      timeZone: _str(d['timeZone']) ?? 'Asia/Baghdad',
      weekStart: _str(d['weekStart']) ?? 'sat',
      rateKind: _str(d['rateKind']) ?? 'market',
    );
  });

  @override
  Future<List<HouseholdMember>> members(String hid) =>
      _guard('members', () async {
        final docs = (await _db.collection('${_h(hid)}/members').get()).docs;
        return [
          for (final doc in docs)
            HouseholdMember(
              uid: doc.id,
              displayName: _str(doc.data()['displayName']) ?? 'Member',
              role: _str(doc.data()['role']),
            ),
        ];
      });

  @override
  Future<List<HouseholdAccount>> accounts(String hid, {required String uid}) =>
      _guard('accounts', () async {
        return [
          for (final doc in await _visible(hid, 'accounts', uid))
            if (_str(doc.data()['currency']) case final currency?)
              HouseholdAccount(
                id: doc.id,
                name: _str(doc.data()['name']) ?? 'Account',
                kind: _str(doc.data()['kind']) ?? 'other',
                currency: currency,
                scope: _str(doc.data()['scope']) ?? 'personal',
                ownerUid: _str(doc.data()['ownerUid']),
                balanceMinor: _int(doc.data()['balanceMinor']) ?? 0,
                archived: doc.data()['archived'] == true,
                order: _int(doc.data()['order']) ?? 0,
              ),
        ];
      });

  @override
  Future<List<HouseholdCategory>> categories(String hid) =>
      _guard('categories', () async {
        final docs = (await _db.collection('${_h(hid)}/categories').get()).docs;
        return [
          for (final doc in docs)
            HouseholdCategory(
              id: doc.id,
              slug: _str(doc.data()['slug']) ?? doc.id,
              name: _name(doc.data()['names']) ?? doc.id,
              kind: _str(doc.data()['kind']) ?? 'expense',
              parentId: _str(doc.data()['parentId']),
              archived: doc.data()['archived'] == true,
            ),
        ];
      });

  @override
  Future<List<HouseholdPerson>> people(String hid, {required String uid}) =>
      _guard('people', () async {
        return [
          for (final doc in await _visible(hid, 'people', uid))
            HouseholdPerson(
              id: doc.id,
              name: _str(doc.data()['name']) ?? 'Someone',
              aliases: [
                for (final a in _list(doc.data()['aliases']))
                  if (a is String) a,
              ],
            ),
        ];
      });

  @override
  Future<List<HouseholdLoan>> loans(String hid, {required String uid}) =>
      _guard('loans', () async {
        return [
          for (final doc in await _visible(hid, 'loans', uid))
            HouseholdLoan(
              id: doc.id,
              direction: _str(doc.data()['direction']) ?? 'given',
              personId: _str(doc.data()['personId']) ?? '',
              principalMinor: _int(doc.data()['principalMinor']) ?? 0,
              outstandingMinor: _int(doc.data()['outstandingMinor']) ?? 0,
              currency: _str(doc.data()['currency']) ?? 'USD',
              status: _str(doc.data()['status']) ?? 'open',
              startedOn: _str(doc.data()['startedOn']),
              dueOn: _str(doc.data()['dueOn']),
            ),
        ];
      });

  @override
  Future<List<HouseholdBudget>> budgets(String hid, {required String uid}) =>
      _guard('budgets', () async {
        return [
          for (final doc in await _visible(hid, 'budgets', uid))
            if (_int(doc.data()['limitMinor']) case final limit?)
              HouseholdBudget(
                id: doc.id,
                categoryId: _str(doc.data()['categoryId']) ?? 'total',
                limitMinor: limit,
              ),
        ];
      });

  @override
  Future<List<LedgerTxn>> transactions(
    String hid, {
    required String uid,
    required String fromOn,
    required String toOn,
    int limit = 2000,
  }) => _guard('transactions', () async {
    // Index: visibleTo (array) + occurredOn asc (DATA_MODEL 6).
    final docs =
        (await _db
                .collection('${_h(hid)}/transactions')
                .where('visibleTo', fs.WhereFilter.arrayContains, uid)
                .where('occurredOn', fs.WhereFilter.greaterThanOrEqual, fromOn)
                .where('occurredOn', fs.WhereFilter.lessThanOrEqual, toOn)
                .orderBy('occurredOn')
                .limit(maxTransactions)
                .get())
            .docs;
    final out = <LedgerTxn>[];
    for (final doc in docs.reversed) {
      final d = doc.data();
      if (d['deletedAt'] != null) continue;
      final amount = _int(d['amountMinor']);
      final currency = _str(d['currency']);
      final type = _str(d['type']);
      final occurredOn = _str(d['occurredOn']);
      final accountId = _str(d['accountId']);
      if (amount == null ||
          currency == null ||
          type == null ||
          occurredOn == null ||
          accountId == null) {
        continue;
      }
      out.add(
        LedgerTxn(
          id: doc.id,
          type: type,
          amountMinor: amount,
          currency: currency,
          baseAmountMinor: _int(d['baseAmountMinor']) ?? amount,
          accountId: accountId,
          toAccountId: _str(d['toAccountId']),
          categoryId: _str(d['categoryId']),
          whoUid: _str(d['whoUid']),
          whoScope: _str(d['whoScope']),
          occurredOn: occurredOn,
          title: _str(d['title']) ?? '',
          note: _str(d['note']),
          personId: _str(d['personId']),
          loanId: _str(d['loanId']),
        ),
      );
      if (out.length >= limit) break;
    }
    return out;
  });

  @override
  Future<FxDay?> fxRateOn(String hid, String date) =>
      _guard('fxRates', () async {
        final col = _db.collection('${_h(hid)}/fxRates');
        final day = await col.doc(date).get();
        if (day.data() case final d?) return _fx(date, d);
        // The most recent earlier day. Document ids are YYYY-MM-DD, but
        // Firestore cannot scan ids descending, so read the previous
        // [rateLookbackDays] days in order and take the last.
        final earlier =
            (await col
                    .whereFieldPath(
                      fs.FieldPath.documentId,
                      fs.WhereFilter.greaterThanOrEqual,
                      col.doc(addDays(date, -rateLookbackDays)),
                    )
                    .whereFieldPath(
                      fs.FieldPath.documentId,
                      fs.WhereFilter.lessThan,
                      col.doc(date),
                    )
                    .orderByFieldPath(fs.FieldPath.documentId)
                    .get())
                .docs;
        if (earlier.isEmpty) return null;
        return _fx(earlier.last.id, earlier.last.data());
      });

  static FxDay? _fx(String date, Map<String, Object?> d) {
    final rate = _str(d['usdIqd']);
    if (rate == null) return null;
    return FxDay(date: date, usdIqd: rate, kind: _str(d['kind']) ?? 'market');
  }
}

String? _str(Object? v) => v is String && v.isNotEmpty ? v : null;

int? _int(Object? v) => v is int ? v : null;

List<Object?> _list(Object? v) => v is List ? v : const [];

String? _name(Object? names) =>
    names is Map ? _str(names['en']) ?? _str(names.values.firstOrNull) : null;
