// The Firestore adapter of `CategoriesRepository`. Only the composition
// root and tests name this file.
import 'dart:async';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:xpense_app/data/categories_repository.dart';
import 'package:xpense_app/data/household_repository.dart';
import 'package:xpense_app/data/read/scoped_listen.dart';
import 'package:xpense_app/services/clock.dart';
import 'package:xpense_shared/xpense_shared.dart';

/// A [CategoriesRepository] over `households/{hid}/categories`, following
/// the signed-in member's household.
final class FirebaseCategoriesRepository implements CategoriesRepository {
  /// Creates the adapter. The Firestore instance must already point at the
  /// emulator when one is used (the household adapter does that).
  new({
    required this._auth,
    required this._firestore,
    required this._households,
    Clock? clock,
    Random? random,
  }) : _clock = clock ?? const Clock(),
       _random = random ?? Random.secure();

  /// The adapter on [FirebaseFirestore.instance] and [FirebaseAuth.instance].
  factory connect({required HouseholdRepository households}) =>
      FirebaseCategoriesRepository(
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
  final Random _random;

  // The latest list, for the order of a new category and for reordering.
  List<CategoryRecord> _latest = const [];

  ({String hid, String uid})? get _scope {
    final membership = _households.current;
    final uid = _auth.currentUser?.uid;
    return membership is InHousehold && uid != null
        ? (hid: membership.household.id, uid: uid)
        : null;
  }

  CollectionReference<Map<String, dynamic>> _categories(String hid) =>
      _firestore.collection('households').doc(hid).collection('categories');

  @override
  Stream<List<CategoryRecord>> watchCategories() =>
      scopedListen<({String hid, String uid}), List<CategoryRecord>>(
        scopes: _households.watchMembership().map((m) {
          final uid = _auth.currentUser?.uid;
          return m is InHousehold && uid != null
              ? (hid: m.household.id, uid: uid)
              : null;
        }),
        build: (scope) => _categories(scope.hid).snapshots().map((snapshot) {
          final list = [
            for (final doc in snapshot.docs)
              ?categoryFromFirestore(doc.id, doc.data()),
          ]..sort(compareCategories);
          _latest = list;
          return list;
        }),
        empty: const [],
      );

  /// The list to work from: the latest seen, else read once.
  Future<List<CategoryRecord>> _current(String hid) async {
    if (_latest.isNotEmpty) return _latest;
    try {
      final snapshot = await _categories(hid).get();
      return [
        for (final doc in snapshot.docs)
          ?categoryFromFirestore(doc.id, doc.data()),
      ]..sort(compareCategories);
    } on FirebaseException {
      return const [];
    }
  }

  @override
  Future<Result<String, CategoriesFailure>> add({
    required String name,
    required CategoryKind kind,
    String? parentId,
  }) async {
    final scope = _scope;
    if (scope == null) return const Err(CategoriesNotAllowed());
    final clean = cleanCategoryName(name);
    if (clean == null) return const Err(CategoryNameInvalid());
    final all = await _current(scope.hid);
    final order = all.fold(-1, (m, c) => max(m, c.order)) + 1;
    final id = uuidV7(_clock.now(), _random);
    const what = 'adding a category';
    try {
      final batch = _firestore.batch()
        ..set(_categories(scope.hid).doc(id), {
          'slug': null,
          'names': {fallbackLanguage: clean},
          'kind': kind.wire,
          'parentId': parentId,
          'colorKey': null,
          'iconKey': null,
          'order': order,
          'system': false,
          'archived': false,
          'createdAt': FieldValue.serverTimestamp(),
          'createdBy': scope.uid,
          ..._updateStamps(scope.uid),
        });
      await _commit(batch, what);
      return Ok(id);
    } on FirebaseException catch (e, s) {
      return Err(_failure(e, s, what));
    }
  }

  @override
  Future<Result<void, CategoriesFailure>> rename(String id, String name) {
    final clean = cleanCategoryName(name);
    if (clean == null) return Future.value(const Err(CategoryNameInvalid()));
    return _update('renaming a category', {
      id: {'names.$fallbackLanguage': clean},
    });
  }

  @override
  Future<Result<void, CategoriesFailure>> reorder(List<String> ids) async {
    final scope = _scope;
    if (scope == null) return const Err(CategoriesNotAllowed());
    final moved = reorderedPositions(await _current(scope.hid), ids);
    if (moved.isEmpty) return const Ok(null);
    return await _update('reordering categories', {
      for (final e in moved.entries) e.key: {'order': e.value},
    });
  }

  @override
  Future<Result<void, CategoriesFailure>> setArchived(
    String id, {
    required bool archived,
  }) => _update('archiving a category', {
    id: {'archived': archived},
  });

  /// Updates each document by id with its fields, in one batch.
  Future<Result<void, CategoriesFailure>> _update(
    String what,
    Map<String, Map<String, Object?>> changes,
  ) async {
    final scope = _scope;
    if (scope == null) return const Err(CategoriesNotAllowed());
    try {
      final batch = _firestore.batch();
      for (final e in changes.entries) {
        batch.update(_categories(scope.hid).doc(e.key), {
          ...e.value,
          ..._updateStamps(scope.uid),
        });
      }
      await _commit(batch, what);
      return const Ok(null);
    } on FirebaseException catch (e, s) {
      return Err(_failure(e, s, what));
    }
  }

  static Map<String, Object?> _updateStamps(String uid) => {
    'updatedAt': FieldValue.serverTimestamp(),
    'updatedBy': uid,
  };

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

  static CategoriesFailure _failure(
    FirebaseException e,
    StackTrace s,
    String what,
  ) {
    _report(e, s, what);
    return switch (e.code) {
      'permission-denied' || 'unauthenticated' => const CategoriesNotAllowed(),
      'not-found' => const CategoryNotFound(),
      _ => CategoriesUnknown(e.code),
    };
  }

  static void _report(Object error, StackTrace stack, String what) =>
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stack,
          library: 'categories_repository',
          context: ErrorDescription('while $what'),
        ),
      );
}

/// Orders categories by `order`, then id, so equal orders stay stable.
int compareCategories(CategoryRecord a, CategoryRecord b) {
  final byOrder = a.order.compareTo(b.order);
  return byOrder != 0 ? byOrder : a.id.compareTo(b.id);
}

/// Reads a stored category (DATA_MODEL 2.6), or null when it is malformed.
CategoryRecord? categoryFromFirestore(String id, Map<String, dynamic> data) {
  final kind = switch (data['kind']) {
    'expense' => CategoryKind.expense,
    'income' => CategoryKind.income,
    _ => null,
  };
  if (kind == null) return null;
  final names = <String, String>{
    if (data['names'] case final Map<Object?, Object?> map)
      for (final e in map.entries)
        if (e.key case final String key)
          if (e.value case final String value) key: value,
  };
  return CategoryRecord(
    id: id,
    slug: switch (data['slug']) {
      final String slug => slug,
      _ => null,
    },
    kind: kind,
    names: names,
    parentId: switch (data['parentId']) {
      final String parent => parent,
      _ => null,
    },
    order: switch (data['order']) {
      final int order => order,
      _ => 0,
    },
    system: data['system'] == true,
    archived: data['archived'] == true,
  );
}
