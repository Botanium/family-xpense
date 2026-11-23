// The household's categories (DATA_MODEL 2.6, BACKLOG S2.7): the default
// tree seeded when the household is created, then renamed, added to,
// reordered and archived by its members.
//
// An archived category is never deleted: entries that use it keep showing
// its name, and editing such an entry keeps it. Pickers offer only the
// live ones (plus the one an entry already has).
//
// This file is the interface features import. The Firestore adapter is
// `categories_repository_firebase.dart` and the in-memory one is
// `categories_repository_fake.dart`; only the composition root and tests
// name them.
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:xpense_shared/xpense_shared.dart';

/// One of the household's categories (`categories/{id}`).
@immutable
final class CategoryRecord {
  /// Creates the record.
  const new({
    required this.id,
    required this.kind,
    required this.names,
    required this.order,
    this.slug,
    this.parentId,
    this.system = false,
    this.archived = false,
  });

  /// The seeded record of the default category [def] at [order].
  factory seeded(CategoryDef def, int order) => CategoryRecord(
    id: def.slug,
    slug: def.slug,
    kind: def.kind,
    names: def.names,
    parentId: def.parentSlug,
    order: order,
    system: true,
  );

  /// The document id. A seeded category's id is its slug.
  final String id;

  /// The stable slug of a seeded category; null for one a member added.
  final String? slug;

  /// Expense or income. Never changes: entries are checked against it.
  final CategoryKind kind;

  /// Names by language code; only `en` for now (D-36).
  final Map<String, String> names;

  /// The group's id for a sub-category; null for a group.
  final String? parentId;

  /// The position among the household's categories.
  final int order;

  /// Whether it came with the default tree.
  final bool system;

  /// Archived: kept for the entries that use it, offered nowhere else.
  final bool archived;

  /// Whether this is a top-level group.
  bool get isGroup => parentId == null;

  /// The name in [language], else English, else the slug or id.
  String nameIn(String language) =>
      names[language] ?? names[fallbackLanguage] ?? slug ?? id;

  /// As the pickers take it: the id stands in the definition's slug.
  CategoryDef get def =>
      CategoryDef(slug: id, kind: kind, names: names, parentSlug: parentId);

  /// A copy with the given fields changed.
  CategoryRecord copyWith({
    Map<String, String>? names,
    int? order,
    bool? archived,
  }) => CategoryRecord(
    id: id,
    slug: slug,
    kind: kind,
    names: names ?? this.names,
    parentId: parentId,
    order: order ?? this.order,
    system: system,
    archived: archived ?? this.archived,
  );

  @override
  bool operator ==(Object other) =>
      other is CategoryRecord &&
      other.id == id &&
      other.slug == slug &&
      other.kind == kind &&
      mapEquals(other.names, names) &&
      other.parentId == parentId &&
      other.order == order &&
      other.system == system &&
      other.archived == archived;

  @override
  int get hashCode => Object.hash(
    id,
    slug,
    kind,
    Object.hashAllUnordered(names.entries.map((e) => (e.key, e.value))),
    parentId,
    order,
    system,
    archived,
  );

  @override
  String toString() => 'CategoryRecord($id, ${nameIn(fallbackLanguage)})';
}

/// The default tree as records, in seed order.
List<CategoryRecord> get defaultCategoryRecords => [
  for (final (i, c) in defaultCategories.indexed) CategoryRecord.seeded(c, i),
];

/// Why a category write did not work. Carries a stable [code], never a
/// user-facing string.
@immutable
sealed class CategoriesFailure implements Failure {
  const new();

  @override
  bool operator ==(Object other) => other.runtimeType == runtimeType;

  @override
  int get hashCode => runtimeType.hashCode;

  @override
  String toString() => code;
}

/// Not in a household, or Firestore's rules refused the write.
final class CategoriesNotAllowed extends CategoriesFailure {
  /// Creates the failure.
  const new();

  @override
  String get code => 'categories.not_allowed';
}

/// No category with that id.
final class CategoryNotFound extends CategoriesFailure {
  /// Creates the failure.
  const new();

  @override
  String get code => 'categories.not_found';
}

/// The name is empty or longer than [maxCategoryNameLength].
final class CategoryNameInvalid extends CategoriesFailure {
  /// Creates the failure.
  const new();

  @override
  String get code => 'categories.name_invalid';
}

/// Anything else; [detail] is for logs.
final class CategoriesUnknown extends CategoriesFailure {
  /// Creates the failure with a machine-readable [detail].
  const new(this.detail);

  /// The error code or type. Never shown.
  final String detail;

  @override
  String get code => 'categories.unknown';
}

/// The longest category name, in characters (the rules check it too).
const int maxCategoryNameLength = 40;

/// [name] trimmed, or null when it is empty or too long.
String? cleanCategoryName(String name) {
  final trimmed = name.trim();
  if (trimmed.isEmpty || trimmed.length > maxCategoryNameLength) return null;
  return trimmed;
}

/// Reads and edits the household's categories.
///
/// Writes are batches that work offline and return once Firestore has them
/// or once they are queued on the phone. Every call returns a [Result].
abstract interface class CategoriesRepository {
  /// Every category, archived ones too, by [CategoryRecord.order]. Empty
  /// while not in a household.
  Stream<List<CategoryRecord>> watchCategories();

  /// Adds a category named [name] of [kind], under the group [parentId]
  /// (null for a new group), after the others. Returns its id.
  Future<Result<String, CategoriesFailure>> add({
    required String name,
    required CategoryKind kind,
    String? parentId,
  });

  /// Renames category [id] in English.
  Future<Result<void, CategoriesFailure>> rename(String id, String name);

  /// Gives the categories [ids] the positions of the same categories in
  /// the current order, in the order given: how siblings are reordered.
  Future<Result<void, CategoriesFailure>> reorder(List<String> ids);

  /// Archives or restores category [id].
  Future<Result<void, CategoriesFailure>> setArchived(
    String id, {
    required bool archived,
  });
}

/// The new `order` values when [ids] take, in the order given, the
/// positions they hold now in [all]: only the changed ones.
Map<String, int> reorderedPositions(
  List<CategoryRecord> all,
  List<String> ids,
) {
  final byId = {for (final c in all) c.id: c};
  final slots = [
    for (final id in ids)
      if (byId[id] case final c?) c.order,
  ]..sort();
  final known = [
    for (final id in ids)
      if (byId.containsKey(id)) id,
  ];
  return {
    for (final (i, id) in known.indexed)
      if (byId[id]!.order != slots[i]) id: slots[i],
  };
}

/// The [CategoriesRepository] for this run. Throws until the composition
/// root sets it.
final categoriesRepositoryProvider = Provider<CategoriesRepository>(
  (ref) => throw UnimplementedError(
    'categoriesRepositoryProvider is set in bootstrap()',
  ),
  name: 'categoriesRepositoryProvider',
);

/// The household's categories, archived ones too, in order.
final StreamProvider<List<CategoryRecord>> categoriesProvider =
    StreamProvider<List<CategoryRecord>>(
      (ref) => ref.watch(categoriesRepositoryProvider).watchCategories(),
      name: 'categoriesProvider',
    );

/// The household's categories, or the default tree while they load or
/// when the household has none stored (a household made before they were
/// seeded), so a name is always found.
final Provider<List<CategoryRecord>> householdCategoriesProvider =
    Provider<List<CategoryRecord>>((ref) {
      final stored = ref.watch(categoriesProvider).value;
      return stored == null || stored.isEmpty ? defaultCategoryRecords : stored;
    }, name: 'householdCategoriesProvider');

/// The categories a picker offers, as definitions: the live ones, plus
/// [keep] (the category an entry already has) even when archived, so
/// editing that entry keeps it.
List<CategoryDef> pickableCategories(List<CategoryRecord> all, {String? keep}) {
  final keptParent = all.where((c) => c.id == keep).firstOrNull?.parentId;
  return [
    for (final c in all)
      if (!c.archived || c.id == keep || c.id == keptParent) c.def,
  ];
}

/// The name of category [id] among [all], archived ones included; null
/// when unknown.
String? categoryNameOf(
  List<CategoryRecord> all,
  String? id, {
  String language = fallbackLanguage,
}) => id == null
    ? null
    : all.where((c) => c.id == id).firstOrNull?.nameIn(language);
