import 'package:material_ui/material_ui.dart';
import 'package:xpense_app/core/theme/theme.dart';
import 'package:xpense_app/core/ui/ui.dart';
import 'package:xpense_shared/xpense_shared.dart';

/// The categories of one kind as two rows of chips (DESIGN_SYSTEM screen
/// 9): the groups, then the chosen group's sub-categories.
///
/// Picking a group chooses the group itself; picking a sub-category
/// narrows it. Only the [kind]'s categories are offered, so an expense
/// never gets an income category (D-41 tree, `defaultCategories`).
///
/// The names are the seeded English ones. Renamed and added categories
/// arrive with the categories editor (WP-24, S2.7), which will feed this
/// from the household's `categories` collection.
class CategoryChips extends StatelessWidget {
  /// Creates the chips.
  const new({
    required this.kind,
    required this.selected,
    required this.onSelected,
    this.categories = defaultCategories,
    this.language = fallbackLanguage,
    super.key,
  });

  /// Expense or income.
  final CategoryKind kind;

  /// The chosen category id (a slug), if any.
  final String? selected;

  /// Called with the picked category id; null disables the chips.
  final ValueChanged<String>? onSelected;

  /// The category tree.
  final List<CategoryDef> categories;

  /// The language of the names.
  final String language;

  @override
  Widget build(BuildContext context) {
    final ofKind = categories.where((c) => c.kind == kind).toList();
    final groups = ofKind.where((c) => c.isGroup).toList();
    final current = ofKind.where((c) => c.slug == selected).firstOrNull;
    final group = current == null
        ? null
        : current.isGroup
        ? current.slug
        : current.parentSlug;
    final children = group == null
        ? const <CategoryDef>[]
        : ofKind.where((c) => c.parentSlug == group).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        ChoiceChips<String>(
          options: [
            for (final g in groups)
              ChoiceOption(value: g.slug, label: g.nameIn(language)),
          ],
          selected: group,
          onSelected: onSelected,
        ),
        if (children.isNotEmpty) ...[
          const SizedBox(height: XpSpace.s12),
          ChoiceChips<String>(
            options: [
              for (final c in children)
                ChoiceOption(value: c.slug, label: c.nameIn(language)),
            ],
            selected: current?.isGroup ?? true ? null : current!.slug,
            onSelected: onSelected,
          ),
        ],
      ],
    );
  }
}

/// The name of category [id] in [language], or null when the tree has no
/// such category.
String? categoryName(
  String? id, {
  List<CategoryDef> categories = defaultCategories,
  String language = fallbackLanguage,
}) => categories.where((c) => c.slug == id).firstOrNull?.nameIn(language);
