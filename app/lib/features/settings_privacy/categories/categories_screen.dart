// WP-24: Settings > Categories (BACKLOG S2.7): rename, add, reorder and
// archive the household's categories. An archived category is never
// deleted: entries that use it keep showing it, and editing them keeps it.
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:xpense_app/core/l10n/l10n.dart';
import 'package:xpense_app/core/routing/routing.dart';
import 'package:xpense_app/core/theme/theme.dart';
import 'package:xpense_app/core/ui/ui.dart';
import 'package:xpense_app/data/categories_repository.dart';
import 'package:xpense_shared/xpense_shared.dart';

/// The live categories of [kind] in display order: each group, then its
/// live sub-categories. Sub-categories of an archived group are left out
/// with it.
List<CategoryRecord> liveCategoryTree(
  List<CategoryRecord> all,
  CategoryKind kind,
) {
  final ofKind = [
    for (final c in all)
      if (c.kind == kind && !c.archived) c,
  ];
  return [
    for (final group in ofKind)
      if (group.isGroup) ...[
        group,
        for (final child in ofKind)
          if (child.parentId == group.id) child,
      ],
  ];
}

/// The live siblings of [category] (same kind and parent), in order.
List<CategoryRecord> liveSiblings(
  List<CategoryRecord> all,
  CategoryRecord category,
) => [
  for (final c in all)
    if (c.kind == category.kind &&
        c.parentId == category.parentId &&
        !c.archived)
      c,
];

/// Settings > Categories.
class CategoriesScreen extends ConsumerStatefulWidget {
  /// Creates the screen.
  const new({super.key});

  @override
  ConsumerState<CategoriesScreen> createState() => _CategoriesScreenState();
}

class _CategoriesScreenState extends ConsumerState<CategoriesScreen> {
  CategoryKind _kind = CategoryKind.expense;
  bool _busy = false;
  bool _failed = false;

  CategoriesRepository get _repository =>
      ref.read(categoriesRepositoryProvider);

  Future<void> _run(
    Future<Result<Object?, CategoriesFailure>> Function() write,
  ) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _failed = false;
    });
    final result = await write();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _failed = result is Err;
    });
  }

  /// Asks for a name; null when cancelled.
  Future<String?> _askName({required String title, String initial = ''}) {
    final l10n = context.l10n;
    final controller = TextEditingController(text: initial);
    String? error;
    void submit(BuildContext sheet, StateSetter set) {
      final clean = cleanCategoryName(controller.text);
      if (clean == null) {
        set(() => error = l10n.settingsCategoriesNameInvalid);
        return;
      }
      Navigator.of(sheet).pop(clean);
    }

    late BuildContext sheetContext;
    late StateSetter setSheet;
    return showGlassSheet<String>(
      context: context,
      useRootNavigator: true,
      header: SheetHeader(
        cancelLabel: l10n.settingsCategoriesCancel,
        onCancel: () => Navigator.of(sheetContext).pop(),
        title: title,
        actionLabel: l10n.settingsCategoriesSave,
        onAction: () => submit(sheetContext, setSheet),
      ),
      builder: (sheet) => StatefulBuilder(
        builder: (context, set) {
          sheetContext = sheet;
          setSheet = set;
          return Padding(
            padding: const EdgeInsetsDirectional.all(XpSpace.s16),
            child: XpTextField(
              label: l10n.settingsCategoriesNameLabel,
              hint: l10n.settingsCategoriesNameHint,
              controller: controller,
              error: error,
              textInputAction: TextInputAction.done,
              onChanged: (_) {
                if (error != null) set(() => error = null);
              },
              onSubmitted: (_) => submit(sheet, set),
            ),
          );
        },
      ),
    ).whenComplete(controller.dispose);
  }

  Future<void> _add({CategoryRecord? group}) async {
    final l10n = context.l10n;
    final name = await _askName(
      title: group == null
          ? l10n.settingsCategoriesNewTitle
          : l10n.settingsCategoriesNewSubTitle(group.nameIn(fallbackLanguage)),
    );
    if (name == null || !mounted) return;
    await _run(
      () => _repository.add(name: name, kind: _kind, parentId: group?.id),
    );
  }

  Future<void> _rename(CategoryRecord category) async {
    final name = await _askName(
      title: context.l10n.settingsCategoriesRenameTitle,
      initial: category.nameIn(fallbackLanguage),
    );
    if (name == null || !mounted) return;
    if (name == category.nameIn(fallbackLanguage)) return;
    await _run(() => _repository.rename(category.id, name));
  }

  /// Moves [category] one place among its live siblings, by [step].
  Future<void> _move(CategoryRecord category, int step) async {
    final siblings = liveSiblings(
      ref.read(householdCategoriesProvider),
      category,
    );
    final ids = [for (final c in siblings) c.id];
    final at = ids.indexOf(category.id);
    final to = at + step;
    if (at < 0 || to < 0 || to >= ids.length) return;
    ids
      ..removeAt(at)
      ..insert(to, category.id);
    await _run(() => _repository.reorder(ids));
  }

  void _actions(CategoryRecord category) {
    final l10n = context.l10n;
    final siblings = liveSiblings(
      ref.read(householdCategoriesProvider),
      category,
    );
    final at = siblings.indexWhere((c) => c.id == category.id);
    unawaited(
      showXpActionSheet(
        context: context,
        title: category.nameIn(fallbackLanguage),
        cancelLabel: l10n.settingsCategoriesCancel,
        actions: [
          XpAction(
            label: l10n.settingsCategoriesRename,
            onPressed: () => unawaited(_rename(category)),
          ),
          if (category.isGroup)
            XpAction(
              label: l10n.settingsCategoriesAddSub,
              onPressed: () => unawaited(_add(group: category)),
            ),
          if (at > 0)
            XpAction(
              label: l10n.settingsCategoriesMoveUp,
              onPressed: () => unawaited(_move(category, -1)),
            ),
          if (at >= 0 && at < siblings.length - 1)
            XpAction(
              label: l10n.settingsCategoriesMoveDown,
              onPressed: () => unawaited(_move(category, 1)),
            ),
          XpAction(
            label: l10n.settingsCategoriesArchive,
            destructive: true,
            onPressed: () => unawaited(
              _run(() => _repository.setArchived(category.id, archived: true)),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final type = XpType.of(context);
    final colors = XpColors.of(context);
    final all = ref.watch(householdCategoriesProvider);
    final names = {for (final c in all) c.id: c.nameIn(fallbackLanguage)};
    final live = liveCategoryTree(all, _kind);
    final archived = [
      for (final c in all)
        if (c.kind == _kind && c.archived) c,
    ];
    return Scaffold(
      backgroundColor: colors.canvas,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            XpTopBar(
              title: l10n.settingsCategoriesTitle,
              leading: const XpBackButton(),
            ),
            Expanded(
              child: ListView(
                key: const ValueKey('categories_list'),
                padding: EdgeInsetsDirectional.only(
                  start: XpSpace.screenMargin,
                  end: XpSpace.screenMargin,
                  top: XpSpace.s16,
                  bottom: XpSpace.bottomControlOffset(context),
                ),
                children: [
                  XpFilterBar(
                    labels: [
                      l10n.settingsCategoriesExpense,
                      l10n.settingsCategoriesIncome,
                    ],
                    selectedIndex: _kind.index,
                    onSelected: (i) =>
                        setState(() => _kind = CategoryKind.values[i]),
                  ),
                  if (_failed)
                    Padding(
                      padding: const EdgeInsetsDirectional.only(
                        top: XpSpace.s12,
                      ),
                      child: Semantics(
                        liveRegion: true,
                        child: Text(
                          l10n.settingsCategoriesFailed,
                          style: type.meta.copyWith(color: colors.danger),
                        ),
                      ),
                    ),
                  const SizedBox(height: XpSpace.s16),
                  for (final c in live)
                    Semantics(
                      label: c.isGroup
                          ? null
                          : l10n.settingsCategoriesSubSpoken(
                              c.nameIn(fallbackLanguage),
                              names[c.parentId] ?? '',
                            ),
                      child: XpListRow(
                        key: ValueKey('category_${c.id}'),
                        title: c.nameIn(fallbackLanguage),
                        leading: c.isGroup
                            ? null
                            : const SizedBox(width: XpSpace.s16),
                        // Shows the row opens actions; the row is the
                        // button, so the glyph is not spoken.
                        trailing: ExcludeSemantics(
                          child: XpIcon(
                            XpGlyph.more,
                            color: colors.inkSecondary,
                          ),
                        ),
                        onTap: _busy ? null : () => _actions(c),
                      ),
                    ),
                  const SizedBox(height: XpSpace.s16),
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: XpButton.text(
                      label: l10n.settingsCategoriesAdd,
                      onPressed: _busy ? null : () => unawaited(_add()),
                    ),
                  ),
                  if (archived.isNotEmpty) ...[
                    const SizedBox(height: XpSpace.s24),
                    XpSection(
                      label: l10n.settingsCategoriesArchivedSection,
                      children: [
                        for (final c in archived)
                          XpListRow(
                            key: ValueKey('archived_${c.id}'),
                            title: c.nameIn(fallbackLanguage),
                            trailing: XpButton.text(
                              label: l10n.settingsCategoriesRestore,
                              onPressed: _busy
                                  ? null
                                  : () => unawaited(
                                      _run(
                                        () => _repository.setArchived(
                                          c.id,
                                          archived: false,
                                        ),
                                      ),
                                    ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: XpSpace.s8),
                    Text(
                      l10n.settingsCategoriesArchivedNote,
                      style: type.meta.copyWith(color: colors.inkSecondary),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
