// WP-24: an archived category stays on the entries that use it, shows its
// (renamed) name there, and survives editing those entries; it is no
// longer offered for new ones.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xpense_app/core/routing/routing.dart';
import 'package:xpense_app/core/ui/ui.dart';
import 'package:xpense_app/features/ask/ask_household.dart';
import 'package:xpense_shared/xpense_shared.dart';

import '../capture/ledger_app.dart';
import 'entry_detail_test.dart' show seedEntry;

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('an archived, renamed category still names its entry, and '
      'an edit keeps it', (tester) async {
    final app = LedgerApp();
    final id = await seedEntry(app);
    await app.categories.rename('dining', 'Eating out');
    await app.categories.setArchived('dining', archived: true);
    final container = await app.pump(tester);
    await pushTo(tester, container, AppRoutes.entry(id));

    expect(find.widgetWithText(XpDisclosure, 'Eating out'), findsOneWidget);

    // Edit another field: the category is still chosen and saved.
    await _tap(tester, find.widgetWithText(XpDisclosure, 'Category'));
    expect(find.text('Edit entry'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(GlassSheet),
        matching: find.text('Eating out'),
      ),
      findsOneWidget,
      reason: 'kept on offer',
    );
    await _tap(tester, find.text('Save changes'));

    final stored = app.memory.transactions[id]!;
    expect(stored['categoryId'], 'dining');
  });

  testWidgets('an archived category is not offered for a new entry', (
    tester,
  ) async {
    final app = LedgerApp();
    await app.categories.setArchived('dining', archived: true);
    final container = await app.pump(tester);
    await pushTo(tester, container, AppRoutes.addEntry);
    await _tap(tester, find.text('Food'));

    expect(find.text('Groceries'), findsOneWidget);
    expect(find.text('Dining out'), findsNothing);
    container.listen(askHouseholdProvider, (_, _) {});
    await tester.pumpAndSettle();
    expect(container.read(askHouseholdProvider).category('dining'), isNull);
    expect(
      container.read(askHouseholdProvider).category('groceries'),
      isNotNull,
    );
  });

  testWidgets('a category added in the editor can be used and saved', (
    tester,
  ) async {
    final app = LedgerApp();
    final added = await app.categories.add(
      name: 'Pets',
      kind: CategoryKind.expense,
    );
    final petsId = added.valueOrNull!;
    final container = await app.pump(tester);
    container.listen(askHouseholdProvider, (_, _) {});
    await tester.pumpAndSettle();
    expect(
      container.read(askHouseholdProvider).category(petsId)?.kind,
      'expense',
    );
    await pushTo(tester, container, AppRoutes.addEntry);
    await tester.enterText(find.byType(EditableText).first, '12');
    await _tap(tester, find.text('Pets'));
    await _tap(tester, find.text('Save expense'));

    expect(app.saved.single['categoryId'], petsId);
    await tester.pump(const Duration(seconds: 11));
    await tester.pumpAndSettle();
  });

  testWidgets('Ask offers nothing from an archived group (Codex review, '
      'PR #43)', (tester) async {
    final app = LedgerApp();
    await app.categories.setArchived('food', archived: true);
    final container = await app.pump(tester);
    container.listen(askHouseholdProvider, (_, _) {});
    await tester.pumpAndSettle();
    final household = container.read(askHouseholdProvider);
    expect(household.category('food'), isNull);
    expect(household.category('groceries'), isNull);
    expect(household.category('fuel'), isNotNull);
  });
}
