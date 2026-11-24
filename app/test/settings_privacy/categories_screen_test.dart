// WP-24: Settings > Categories (S2.7): rename, add, reorder, archive and
// restore the household's categories.
import 'dart:async';

import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xpense_app/app.dart';
import 'package:xpense_app/core/routing/routing.dart';
import 'package:xpense_app/core/ui/ui.dart';
import 'package:xpense_app/data/categories_repository.dart';
import 'package:xpense_app/features/settings_privacy/categories/categories_screen.dart';
import 'package:xpense_shared/xpense_shared.dart';

import '../support/test_app.dart';

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<TestServices> _open(WidgetTester tester) async {
  tester.view
    ..physicalSize = const Size(390, 844) * 3
    ..devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  final services = TestServices();
  final container = await pumpXpenseApp(tester, services);
  unawaited(
    container.read(routerProvider).push<void>(AppRoutes.settingsCategories),
  );
  await tester.pumpAndSettle();
  expect(find.byType(CategoriesScreen), findsOneWidget);
  return services;
}

Finder _row(String id) => find.byKey(ValueKey('category_$id'));

/// Scrolls the editor's list until [finder] is built and on screen.
Future<void> _reveal(WidgetTester tester, Finder finder) async {
  // Back to the top first, so one way down finds anything.
  await tester.drag(
    find.byKey(const ValueKey('categories_list')),
    const Offset(0, 20000),
  );
  await tester.pumpAndSettle();
  await tester.scrollUntilVisible(
    finder,
    200,
    scrollable: find
        .descendant(
          of: find.byKey(const ValueKey('categories_list')),
          matching: find.byType(Scrollable),
        )
        .first,
  );
  await tester.pumpAndSettle();
}

Future<void> _action(WidgetTester tester, String id, String action) async {
  await _reveal(tester, _row(id));
  await tester.tap(_row(id));
  await _settle(tester);
  await tester.tap(find.text(action));
  await _settle(tester);
}

Future<void> _typeName(WidgetTester tester, String name) async {
  await tester.enterText(
    find.descendant(
      of: find.byType(GlassSheet),
      matching: find.byType(CupertinoTextField),
    ),
    name,
  );
  await tester.tap(find.text('Save').last);
  await _settle(tester);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('lists groups with their sub-categories, by kind', (
    tester,
  ) async {
    await _open(tester);
    expect(_row('food'), findsOneWidget);
    expect(_row('groceries'), findsOneWidget);
    expect(_row('salary'), findsNothing);

    await tester.tap(find.text('Income'));
    await tester.pumpAndSettle();
    expect(_row('food'), findsNothing);
    expect(_row('other_income'), findsOneWidget);
  });

  testWidgets('rename', (tester) async {
    final services = await _open(tester);
    await _action(tester, 'groceries', 'Rename');
    await _typeName(tester, 'Food shop');

    expect(services.categories.byId('groceries')?.nameIn('en'), 'Food shop');
    expect(find.text('Food shop'), findsOneWidget);
  });

  testWidgets('a name must be 1 to 40 characters', (tester) async {
    final services = await _open(tester);
    await _action(tester, 'groceries', 'Rename');
    await _typeName(tester, '   ');

    expect(find.text('Enter a name of up to 40 characters.'), findsOneWidget);
    expect(services.categories.byId('groceries')?.nameIn('en'), 'Groceries');
  });

  testWidgets('add a group, then a category under it', (tester) async {
    final services = await _open(tester);
    await _reveal(tester, find.text('Add category'));
    await tester.tap(find.text('Add category'));
    await _settle(tester);
    await _typeName(tester, 'Pets');

    final pets = services.categories.all.singleWhere(
      (c) => c.nameIn('en') == 'Pets',
    );
    expect(pets.kind, CategoryKind.expense);
    expect(pets.isGroup, isTrue);
    expect(pets.system, isFalse);

    await _action(tester, pets.id, 'Add a category under it');
    expect(find.text('New under Pets'), findsOneWidget);
    await _typeName(tester, 'Vet');
    final vet = services.categories.all.singleWhere(
      (c) => c.nameIn('en') == 'Vet',
    );
    expect(vet.parentId, pets.id);
    await _reveal(tester, _row(vet.id));
  });

  testWidgets('reorder: Move down and Move up among siblings', (tester) async {
    final services = await _open(tester);
    List<String> groups() => [
      for (final c in liveCategoryTree(
        services.categories.all,
        CategoryKind.expense,
      ))
        if (c.isGroup) c.id,
    ];
    final before = groups();
    await _action(tester, before.first, 'Move down');
    expect(groups().take(2), [before[1], before[0]]);

    await _action(tester, before.first, 'Move up');
    expect(groups(), before);
  });

  testWidgets('the first sibling cannot move up', (tester) async {
    final services = await _open(tester);
    final first = liveCategoryTree(
      services.categories.all,
      CategoryKind.expense,
    ).first;
    await tester.tap(_row(first.id));
    await _settle(tester);
    expect(find.text('Move up'), findsNothing);
    expect(find.text('Move down'), findsOneWidget);
  });

  testWidgets('archive, then restore', (tester) async {
    final services = await _open(tester);
    await _action(tester, 'dining', 'Archive');

    expect(services.categories.byId('dining')?.archived, isTrue);
    expect(_row('dining'), findsNothing);
    await _reveal(tester, find.byKey(const ValueKey('archived_dining')));
    expect(find.byKey(const ValueKey('archived_dining')), findsOneWidget);

    await tester.tap(find.text('Restore'));
    await tester.pumpAndSettle();
    expect(services.categories.byId('dining')?.archived, isFalse);
    await _reveal(tester, _row('dining'));
  });

  testWidgets('a failed save says so', (tester) async {
    final services = await _open(tester);
    services.categories.nextFailure = const CategoriesNotAllowed();
    await _action(tester, 'dining', 'Archive');
    await _reveal(tester, find.text("Couldn't save. Try again."));
    expect(services.categories.byId('dining')?.archived, isFalse);
  });

  test('reorderedPositions keeps the slots and moves only what changed', () {
    final all = [
      for (final (i, id) in ['a', 'b', 'c'].indexed)
        CategoryRecord(
          id: id,
          kind: CategoryKind.expense,
          names: {'en': id},
          order: i * 10,
        ),
    ];
    expect(reorderedPositions(all, ['b', 'a']), {'b': 0, 'a': 10});
    expect(reorderedPositions(all, ['a', 'b', 'c']), isEmpty);
  });

  test('reorderedPositions spreads tied siblings out (Codex review, '
      'PR #43)', () {
    // Added at the same time on two phones: both took position 5.
    final all = [
      for (final id in ['a', 'b'])
        CategoryRecord(
          id: id,
          kind: CategoryKind.expense,
          names: {'en': id},
          order: 5,
        ),
    ];
    expect(reorderedPositions(all, ['b', 'a']), {'a': 6});
  });

  test('archiving a group retires its sub-categories for new entries', () {
    final all = [
      for (final c in defaultCategoryRecords)
        if (c.id == 'food') c.copyWith(archived: true) else c,
    ];
    final groceries = all.singleWhere((c) => c.id == 'groceries');
    expect(isLiveCategory(groceries, all), isFalse);
    expect(
      pickableCategories(all).map((d) => d.slug),
      isNot(contains('groceries')),
    );
    // An entry that already uses it keeps it, with its group.
    expect(
      pickableCategories(all, keep: 'groceries').map((d) => d.slug),
      containsAll(['groceries', 'food']),
    );
  });
}
