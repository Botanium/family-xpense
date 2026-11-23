// An in-memory `CategoriesRepository` for tests and the `fakes`
// environment. Only the composition root and tests name this file.
import 'dart:async';

import 'package:xpense_app/data/categories_repository.dart';
import 'package:xpense_app/data/write/ledger_store.dart';
import 'package:xpense_app/data/write/memory_ledger_store.dart';
import 'package:xpense_shared/xpense_shared.dart';

/// A [CategoriesRepository] that keeps one household's categories in
/// memory, starting with the given categories (the default tree by
/// default).
///
/// With a [ledger] (the in-memory write path's store), every category is
/// in it too, so a save can use a category added here, as one Firestore
/// household would.
final class MemoryCategoriesRepository implements CategoriesRepository {
  /// Creates the store.
  new({Iterable<CategoryRecord>? categories, this.ledger}) {
    (categories ?? defaultCategoryRecords).forEach(_put);
  }

  /// The write path's store this one keeps in step.
  final MemoryLedgerStore? ledger;

  final Map<String, CategoryRecord> _all = {};
  final _changes = StreamController<void>.broadcast(sync: true);
  var _nextId = 0;

  /// When set, the next write fails with it (then it clears).
  CategoriesFailure? nextFailure;

  /// Every category, in order.
  List<CategoryRecord> get all => _all.values.toList()
    ..sort((a, b) {
      final byOrder = a.order.compareTo(b.order);
      return byOrder != 0 ? byOrder : a.id.compareTo(b.id);
    });

  /// Category [id], if any.
  CategoryRecord? byId(String id) => _all[id];

  /// Puts [category] in the store, as the partner's phone would.
  void put(CategoryRecord category) {
    _put(category);
    _changes.add(null);
  }

  void _put(CategoryRecord c) {
    _all[c.id] = c;
    ledger?.categories[c.id] = LedgerCategory(id: c.id, kind: c.kind.wire);
  }

  Result<T, CategoriesFailure>? _fail<T>() {
    final failure = nextFailure;
    if (failure == null) return null;
    nextFailure = null;
    return Err(failure);
  }

  @override
  Stream<List<CategoryRecord>> watchCategories() {
    late final StreamController<List<CategoryRecord>> controller;
    StreamSubscription<void>? changes;
    controller = StreamController<List<CategoryRecord>>(
      onListen: () {
        changes = _changes.stream.listen((_) => controller.add(all));
        controller.add(all);
      },
      onCancel: () => changes?.cancel(),
    );
    return controller.stream;
  }

  @override
  Future<Result<String, CategoriesFailure>> add({
    required String name,
    required CategoryKind kind,
    String? parentId,
  }) async {
    final failed = _fail<String>();
    if (failed != null) return failed;
    final clean = cleanCategoryName(name);
    if (clean == null) return const Err(CategoryNameInvalid());
    final id = 'cat-new-${_nextId++}';
    put(
      CategoryRecord(
        id: id,
        kind: kind,
        names: {fallbackLanguage: clean},
        parentId: parentId,
        order: _all.values.fold(-1, (m, c) => c.order > m ? c.order : m) + 1,
      ),
    );
    return Ok(id);
  }

  @override
  Future<Result<void, CategoriesFailure>> rename(String id, String name) async {
    final failed = _fail<void>();
    if (failed != null) return failed;
    final clean = cleanCategoryName(name);
    if (clean == null) return const Err(CategoryNameInvalid());
    final c = _all[id];
    if (c == null) return const Err(CategoryNotFound());
    put(c.copyWith(names: {...c.names, fallbackLanguage: clean}));
    return const Ok(null);
  }

  @override
  Future<Result<void, CategoriesFailure>> reorder(List<String> ids) async {
    final failed = _fail<void>();
    if (failed != null) return failed;
    final moved = reorderedPositions(all, ids);
    for (final e in moved.entries) {
      _put(_all[e.key]!.copyWith(order: e.value));
    }
    _changes.add(null);
    return const Ok(null);
  }

  @override
  Future<Result<void, CategoriesFailure>> setArchived(
    String id, {
    required bool archived,
  }) async {
    final failed = _fail<void>();
    if (failed != null) return failed;
    final c = _all[id];
    if (c == null) return const Err(CategoryNotFound());
    put(c.copyWith(archived: archived));
    return const Ok(null);
  }
}
