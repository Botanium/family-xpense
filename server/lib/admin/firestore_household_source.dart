/// The Firestore [HouseholdSource] for `/decide` (WP-33).
///
/// Every list read that inherits account privacy filters on
/// `visibleTo arrayContains uid` (DATA_MODEL 4), so the question set never
/// offers an account, person or past entry the speaker cannot see.
library;

import 'package:google_cloud_firestore/google_cloud_firestore.dart' as fs;
import 'package:xpense_agent/admin/admin_gateway.dart';
import 'package:xpense_agent/decide/household_profile.dart';
import 'package:xpense_shared/xpense_shared.dart';

/// Reads household data with the admin Firestore client.
final class FirestoreHouseholdSource implements HouseholdSource {
  /// Creates a source over [_db].
  new(this._db);

  final fs.Firestore _db;

  @override
  Future<HouseholdProfile> profile({
    required String hid,
    required String uid,
  }) async {
    try {
      final root = 'households/$hid';
      final results = await Future.wait([
        _db.doc(root).get(),
        _db.collection('$root/members').get(),
        _db
            .collection('$root/accounts')
            .where('visibleTo', fs.WhereFilter.arrayContains, uid)
            .get(),
        _db
            .collection('$root/people')
            .where('visibleTo', fs.WhereFilter.arrayContains, uid)
            .get(),
        _db.collection('$root/categories').get(),
      ]);
      final household = (results[0] as fs.DocumentSnapshot<fs.DocumentData>)
          .data();
      final baseCurrency = switch (household) {
        {'baseCurrency': final String code} => code,
        _ => 'USD',
      };
      List<(String, Map<String, Object?>)> docs(int i) => [
        for (final d in (results[i] as fs.QuerySnapshot<fs.DocumentData>).docs)
          (d.id, d.data()),
      ];
      return HouseholdProfile(
        baseCurrency: baseCurrency,
        members: [
          for (final (id, m) in docs(1))
            ProfileMember(uid: id, name: _string(m['displayName']) ?? 'Member'),
        ],
        accounts: _sorted(docs(2))
            .where((e) => e.$2['archived'] != true)
            .map(
              (e) => ProfileAccount(
                id: e.$1,
                name: _string(e.$2['name']) ?? 'Account',
                currency: _string(e.$2['currency']) ?? baseCurrency,
                kind: _string(e.$2['kind']) ?? 'other',
                joint: e.$2['scope'] == 'joint',
                ownerUid: _string(e.$2['ownerUid']),
              ),
            )
            .toList(),
        people: [
          for (final (id, p) in docs(3))
            if (_string(p['name']) case final name?)
              ProfilePerson(
                id: id,
                name: name,
                aliases: [
                  for (final a in (p['aliases'] as List?) ?? const [])
                    if (a is String && a.isNotEmpty) a,
                ],
                memberUid: _string(p['memberUid']),
              ),
        ],
        categories: _sorted(docs(4))
            .where((e) => e.$2['archived'] != true)
            .map((e) => _category(e.$1, e.$2))
            .nonNulls
            .toList(),
      );
    } on Exception catch (e) {
      throw GatewayUnavailable('householdProfile', e);
    }
  }

  @override
  Future<List<RecentEntry>> entriesWithAmount({
    required String hid,
    required String uid,
    required int amountMinor,
    required String fromDay,
    required String toDay,
  }) async {
    try {
      final snapshot = await _db
          .collection('households/$hid/transactions')
          .where('visibleTo', fs.WhereFilter.arrayContains, uid)
          .where('amountMinor', fs.WhereFilter.equal, amountMinor)
          .where('occurredOn', fs.WhereFilter.greaterThanOrEqual, fromDay)
          .where('occurredOn', fs.WhereFilter.lessThanOrEqual, toDay)
          .limit(20)
          .get();
      return [
        for (final d in snapshot.docs)
          if (d.data() case {
            'amountMinor': final int amount,
            'currency': final String currency,
            'occurredOn': final String on,
            'accountId': final String accountId,
          })
            RecentEntry(
              id: d.id,
              amountMinor: amount,
              currency: currency,
              occurredOn: on,
              accountId: accountId,
              title: _string(d.data()['title']),
              deleted: d.data()['deletedAt'] != null,
            ),
      ];
    } on Exception catch (e) {
      throw GatewayUnavailable('entriesWithAmount', e);
    }
  }

  static ProfileCategory? _category(String id, Map<String, Object?> c) {
    final slug = _string(c['slug']) ?? id;
    final names = c['names'];
    final name = names is Map ? _string(names['en']) : null;
    final kind = switch (c['kind']) {
      'income' => CategoryKind.income,
      'expense' => CategoryKind.expense,
      _ => null,
    };
    if (kind == null) return null;
    return ProfileCategory(
      id: id,
      slug: slug,
      name: name ?? slug,
      kind: kind,
      parentId: _string(c['parentId']),
    );
  }

  static List<(String, Map<String, Object?>)> _sorted(
    List<(String, Map<String, Object?>)> docs,
  ) => [...docs]..sort((a, b) => _order(a.$2).compareTo(_order(b.$2)));

  static int _order(Map<String, Object?> d) => switch (d['order']) {
    final num n => n.toInt(),
    _ => 1 << 30,
  };

  static String? _string(Object? v) => v is String && v.isNotEmpty ? v : null;
}
