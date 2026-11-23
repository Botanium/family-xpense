// The Firestore adapter behind `RulesRepository` (DATA_MODEL 2.12). Only
// the composition root and tests name this file.
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:xpense_app/data/rules_repository.dart';
import 'package:xpense_shared/xpense_shared.dart';

/// The stored `sets` map for [lesson] (DATA_MODEL 2.12), read by [uid].
///
/// `who` is stored relative to the household: `me` becomes the member's
/// uid, `joint` the joint scope. `partner` is not stored, since the phone
/// may not know the partner's uid; such a lesson keeps its other fields.
Map<String, Object?> storedSets(RuleLesson lesson, {required String uid}) => {
  'categoryId': ?lesson.categoryId,
  'accountId': ?lesson.accountId,
  'type': ?lesson.intent,
  ...switch (lesson.who) {
    'me' => {'whoScope': 'member', 'whoUid': uid},
    'joint' => {'whoScope': 'joint'},
    _ => const <String, Object?>{},
  },
};

/// The parser's rule from a stored document, read by [uid]; null when the
/// document is malformed.
ParserRule? ruleFromDoc(
  String id,
  Map<String, Object?> data, {
  required String uid,
}) {
  final kind = RuleKind.values.where((k) => k.wire == data['kind']).firstOrNull;
  final pattern = data['pattern'];
  final sets = data['sets'];
  if (kind == null || pattern is! String || pattern.isEmpty || sets is! Map) {
    return null;
  }
  String? text(String key) => sets[key] is String ? sets[key] as String : null;
  final who = switch ((text('whoScope'), text('whoUid'))) {
    ('joint', _) => 'joint',
    ('member', final w?) => w == uid ? 'me' : 'partner',
    _ => null,
  };
  return ParserRule(
    id: id,
    kind: kind,
    pattern: pattern,
    categoryId: text('categoryId'),
    accountId: text('accountId'),
    who: who,
    intent: text('type'),
  );
}

/// [RulesRepository] over `households/{hid}/rules`.
///
/// Rules are personal (`ownerUid`, visible to the member only): the phone
/// does not know which accounts the partner can see, and a rule that names
/// a private account must not leak it. Sharing rules is a later choice.
final class FirestoreRulesRepository implements RulesRepository {
  /// Listens to the member's rules in household [hid].
  new({
    required FirebaseFirestore firestore,
    required this.hid,
    required this.uid,
  }) : _collection = firestore
           .collection('households')
           .doc(hid)
           .collection('rules') {
    _subscription = _collection
        .where('visibleTo', arrayContains: uid)
        .snapshots()
        .listen(
          (snapshot) {
            _ids = {for (final doc in snapshot.docs) doc.id};
            _rules = [
              for (final doc in snapshot.docs)
                ?ruleFromDoc(doc.id, doc.data(), uid: uid),
            ];
            if (!_changes.isClosed) _changes.add(_rules);
          },
          onError: (Object error) =>
              debugPrint('rules listener stopped: ${error.runtimeType}'),
        );
  }

  /// The household.
  final String hid;

  /// The member.
  final String uid;

  final CollectionReference<Map<String, dynamic>> _collection;
  late final StreamSubscription<QuerySnapshot<Map<String, dynamic>>>
  _subscription;
  final StreamController<List<ParserRule>> _changes =
      StreamController<List<ParserRule>>.broadcast();
  List<ParserRule> _rules = const [];
  Set<String> _ids = const {};

  @override
  List<ParserRule> get current => _rules;

  @override
  Stream<List<ParserRule>> watch() => _changes.stream;

  @override
  Future<void> learn(RuleLesson lesson) async {
    final pattern = rulePattern(lesson.pattern);
    if (lesson.isEmpty || pattern.isEmpty) return;
    final ref = _collection.doc('${ruleIdFor(lesson.kind, pattern)}_$uid');
    final sets = storedSets(lesson, uid: uid);
    Future<void> update() => ref.update({
      for (final MapEntry(:key, :value) in sets.entries) 'sets.$key': value,
      if (lesson.who == 'joint') 'sets.whoUid': FieldValue.delete(),
      'hits': FieldValue.increment(1),
      'lastUsedAt': FieldValue.serverTimestamp(),
      'fromTxnId': ?lesson.fromTxnId,
      'updatedBy': uid,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    Future<void> create() => ref.set({
      'kind': lesson.kind.wire,
      'pattern': pattern,
      'sets': sets,
      'ownerUid': uid,
      'scope': 'personal',
      'visibleTo': [uid],
      'hits': 1,
      'lastUsedAt': FieldValue.serverTimestamp(),
      'fromTxnId': ?lesson.fromTxnId,
      'createdBy': uid,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedBy': uid,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    // No read first: the rules refuse a read of a rule that does not exist
    // yet (`canReadVisible` looks at its `visibleTo`), so a transaction
    // cannot ask. The listened set says which it is; if it is behind (the
    // rule was made on another phone, or deleted), the other write runs.
    final known = _ids.contains(ref.id);
    try {
      await (known ? update() : create());
    } on FirebaseException catch (e) {
      if (e.code != 'permission-denied' && e.code != 'not-found') rethrow;
      await (known ? create() : update());
    }
  }

  /// Stops listening and closes [watch].
  Future<void> dispose() async {
    await _subscription.cancel();
    await _changes.close();
  }
}
