import 'package:meta/meta.dart';

/// The language whose name every default category must have.
const String fallbackLanguage = 'en';

/// Whether a category holds spending or income (`categories.kind`).
enum CategoryKind {
  /// Spending categories.
  expense('expense'),

  /// Income categories.
  income('income');

  new(this.wire);

  /// The stored string.
  final String wire;
}

/// One entry of the default category tree (AI_PIPELINE 4, DATA_MODEL 2.6).
///
/// The tree is seeded per household. [slug] is stable forever; [names] is
/// keyed by language code (only `en` for now, D-36) so other languages can be
/// added without changing slugs. Users can rename, add and archive.
@immutable
final class CategoryDef {
  /// Creates a category definition.
  const new({
    required this.slug,
    required this.kind,
    required this.names,
    this.parentSlug,
  });

  /// Stable identifier, for example `groceries`.
  final String slug;

  /// Expense or income.
  final CategoryKind kind;

  /// Display names keyed by language code, for example `{'en': 'Groceries'}`.
  final Map<String, String> names;

  /// The group's slug for a sub-category; `null` for a top-level group.
  final String? parentSlug;

  /// Whether this is a top-level group.
  bool get isGroup => parentSlug == null;

  /// The name in [language], falling back to [fallbackLanguage].
  String nameIn(String language) => names[language] ?? names[fallbackLanguage]!;
}

/// The default category tree, groups first within each kind, children in
/// order after their group. List order is the seeded `order`.
const List<CategoryDef> defaultCategories = [
  // Expense groups and sub-categories.
  CategoryDef(slug: 'food', kind: .expense, names: {'en': 'Food'}),
  CategoryDef(
    slug: 'groceries',
    kind: .expense,
    parentSlug: 'food',
    names: {'en': 'Groceries'},
  ),
  CategoryDef(
    slug: 'dining',
    kind: .expense,
    parentSlug: 'food',
    names: {'en': 'Dining out'},
  ),
  CategoryDef(
    slug: 'bakery_tea',
    kind: .expense,
    parentSlug: 'food',
    names: {'en': 'Bakery and tea'},
  ),
  CategoryDef(slug: 'home', kind: .expense, names: {'en': 'Home'}),
  CategoryDef(
    slug: 'electricity_generator',
    kind: .expense,
    parentSlug: 'home',
    names: {'en': 'Electricity and generator'},
  ),
  CategoryDef(
    slug: 'water',
    kind: .expense,
    parentSlug: 'home',
    names: {'en': 'Water'},
  ),
  CategoryDef(
    slug: 'apartment_gas',
    kind: .expense,
    parentSlug: 'home',
    names: {'en': 'Apartment gas'},
  ),
  CategoryDef(
    slug: 'internet_phone',
    kind: .expense,
    parentSlug: 'home',
    names: {'en': 'Internet and phone'},
  ),
  CategoryDef(
    slug: 'household_goods',
    kind: .expense,
    parentSlug: 'home',
    names: {'en': 'Household goods'},
  ),
  CategoryDef(
    slug: 'repairs',
    kind: .expense,
    parentSlug: 'home',
    names: {'en': 'Repairs'},
  ),
  CategoryDef(slug: 'transport', kind: .expense, names: {'en': 'Transport'}),
  CategoryDef(
    slug: 'fuel',
    kind: .expense,
    parentSlug: 'transport',
    names: {'en': 'Fuel'},
  ),
  CategoryDef(
    slug: 'taxi',
    kind: .expense,
    parentSlug: 'transport',
    names: {'en': 'Taxi'},
  ),
  CategoryDef(
    slug: 'car_maintenance',
    kind: .expense,
    parentSlug: 'transport',
    names: {'en': 'Car maintenance'},
  ),
  CategoryDef(
    slug: 'public_transport',
    kind: .expense,
    parentSlug: 'transport',
    names: {'en': 'Public transport'},
  ),
  CategoryDef(slug: 'family', kind: .expense, names: {'en': 'Family'}),
  CategoryDef(
    slug: 'kids_school',
    kind: .expense,
    parentSlug: 'family',
    names: {'en': 'Kids and school'},
  ),
  CategoryDef(
    slug: 'clothing',
    kind: .expense,
    parentSlug: 'family',
    names: {'en': 'Clothing'},
  ),
  CategoryDef(
    slug: 'health',
    kind: .expense,
    parentSlug: 'family',
    names: {'en': 'Health'},
  ),
  CategoryDef(
    slug: 'personal_care',
    kind: .expense,
    parentSlug: 'family',
    names: {'en': 'Personal care'},
  ),
  CategoryDef(slug: 'social', kind: .expense, names: {'en': 'Social'}),
  CategoryDef(
    slug: 'gifts',
    kind: .expense,
    parentSlug: 'social',
    names: {'en': 'Gifts'},
  ),
  CategoryDef(
    slug: 'family_support',
    kind: .expense,
    parentSlug: 'social',
    names: {'en': 'Family support'},
  ),
  CategoryDef(
    slug: 'charity',
    kind: .expense,
    parentSlug: 'social',
    names: {'en': 'Charity and zakat'},
  ),
  CategoryDef(
    slug: 'occasions',
    kind: .expense,
    parentSlug: 'social',
    names: {'en': 'Weddings and occasions'},
  ),
  CategoryDef(slug: 'leisure', kind: .expense, names: {'en': 'Leisure'}),
  CategoryDef(
    slug: 'entertainment',
    kind: .expense,
    parentSlug: 'leisure',
    names: {'en': 'Entertainment'},
  ),
  CategoryDef(
    slug: 'travel',
    kind: .expense,
    parentSlug: 'leisure',
    names: {'en': 'Travel'},
  ),
  CategoryDef(
    slug: 'subscriptions',
    kind: .expense,
    parentSlug: 'leisure',
    names: {'en': 'Subscriptions'},
  ),
  CategoryDef(slug: 'finance', kind: .expense, names: {'en': 'Finance'}),
  CategoryDef(
    slug: 'fees',
    kind: .expense,
    parentSlug: 'finance',
    names: {'en': 'Fees'},
  ),
  CategoryDef(
    slug: 'interest',
    kind: .expense,
    parentSlug: 'finance',
    names: {'en': 'Interest'},
  ),
  CategoryDef(
    slug: 'taxes',
    kind: .expense,
    parentSlug: 'finance',
    names: {'en': 'Taxes'},
  ),
  CategoryDef(
    slug: 'other_expense',
    kind: .expense,
    names: {'en': 'Other spending'},
  ),
  // Income groups and sub-categories.
  CategoryDef(slug: 'earned', kind: .income, names: {'en': 'Earned'}),
  CategoryDef(
    slug: 'salary',
    kind: .income,
    parentSlug: 'earned',
    names: {'en': 'Salary'},
  ),
  CategoryDef(
    slug: 'freelance',
    kind: .income,
    parentSlug: 'earned',
    names: {'en': 'Freelance'},
  ),
  CategoryDef(
    slug: 'business',
    kind: .income,
    parentSlug: 'earned',
    names: {'en': 'Business'},
  ),
  CategoryDef(slug: 'received', kind: .income, names: {'en': 'Received'}),
  CategoryDef(
    slug: 'gift_received',
    kind: .income,
    parentSlug: 'received',
    names: {'en': 'Gifts received'},
  ),
  CategoryDef(
    slug: 'refund',
    kind: .income,
    parentSlug: 'received',
    names: {'en': 'Refunds'},
  ),
  CategoryDef(
    slug: 'sale',
    kind: .income,
    parentSlug: 'received',
    names: {'en': 'Sales'},
  ),
  CategoryDef(
    slug: 'rental_income',
    kind: .income,
    parentSlug: 'received',
    names: {'en': 'Rental income'},
  ),
  CategoryDef(
    slug: 'other_income',
    kind: .income,
    names: {'en': 'Other income'},
  ),
];

/// The catch-all expense category (also the Decisions API catch-all option).
const String otherExpenseSlug = 'other_expense';

/// The catch-all income category (also the Decisions API catch-all option).
const String otherIncomeSlug = 'other_income';

/// The default category with [slug], or `null`.
CategoryDef? defaultCategory(String slug) {
  for (final category in defaultCategories) {
    if (category.slug == slug) return category;
  }
  return null;
}

/// The default top-level groups of [kind], in seed order.
List<CategoryDef> defaultGroups(CategoryKind kind) => [
  for (final category in defaultCategories)
    if (category.isGroup && category.kind == kind) category,
];

/// The default sub-categories of the group [groupSlug], in seed order.
List<CategoryDef> defaultChildren(String groupSlug) => [
  for (final category in defaultCategories)
    if (category.parentSlug == groupSlug) category,
];
