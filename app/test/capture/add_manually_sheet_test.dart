import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xpense_app/core/routing/routing.dart';
import 'package:xpense_app/core/ui/ui.dart';
import 'package:xpense_shared/xpense_shared.dart';

import 'ledger_app.dart';

Finder _amountInput([int index = 0]) => find
    .descendant(
      of: find.byType(AmountField),
      matching: find.byType(CupertinoTextField),
    )
    .at(index);

Finder _field(String label) => find.descendant(
  of: find.widgetWithText(XpTextField, label),
  matching: find.byType(CupertinoTextField),
);

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<ProviderContainer> _openSheet(
  WidgetTester tester,
  LedgerApp app, {
  Object? extra,
}) async {
  final container = await app.pump(tester);
  await pushTo(tester, container, AppRoutes.addEntry, extra: extra);
  expect(find.text('Add manually'), findsOneWidget);
  return container;
}

Future<void> _pickAccount(
  WidgetTester tester,
  String row,
  String account,
) async {
  await _tap(tester, find.widgetWithText(XpDisclosure, row));
  await _tap(tester, find.text(account).last);
}

/// Lets the save toast time out, so no timer is left running.
Future<void> _toastGone(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 11));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('an expense is saved with its category, who and note', (
    tester,
  ) async {
    final app = LedgerApp();
    await _openSheet(tester, app);

    // Cancel leads, Save trails, and the bottom button names the type.
    expect(find.text('Cancel'), findsOneWidget);
    expect(find.text('Save'), findsOneWidget);
    expect(find.text('Save expense'), findsOneWidget);
    expect(find.text('USD'), findsOneWidget);

    await tester.enterText(_amountInput(), '42.80');
    await _tap(tester, find.text('Food'));
    await _tap(tester, find.text('Groceries'));
    await _tap(tester, find.text('Sam'));
    await _pickAccount(tester, 'Account', 'Joint Visa ••4021');
    await tester.enterText(_field('Note'), 'Weekly shop');
    await _tap(tester, find.text('Save expense'));

    expect(find.text('Add manually'), findsNothing);
    expect(find.text('Saved'), findsOneWidget);
    final [txn] = app.saved;
    expect(txn['type'], 'expense');
    expect(txn['amountMinor'], 4280);
    expect(txn['currency'], 'USD');
    expect(txn['accountId'], 'acc-visa');
    expect(txn['categoryId'], 'groceries');
    expect(txn['whoUid'], partner);
    expect(txn['note'], 'Weekly shop');
    expect(txn['source'], 'manual');

    // Undo on the toast takes the save back.
    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(app.saved.single['deletedAt'], isNotNull);
  });

  testWidgets('income offers only income categories', (tester) async {
    final app = LedgerApp();
    await _openSheet(tester, app);

    await _tap(tester, find.text('Income'));
    expect(find.text('Food'), findsNothing);
    expect(find.text('Save income'), findsOneWidget);
    await tester.enterText(_amountInput(), '3200');
    await _tap(tester, find.text('Earned'));
    await _tap(tester, find.text('Salary'));
    await _tap(tester, find.text('Save income'));

    final [txn] = app.saved;
    expect(txn['type'], 'income');
    expect(txn['amountMinor'], 320000);
    expect(txn['categoryId'], 'salary');
    expect(txn['accountId'], 'acc-checking');
    await _toastGone(tester);
  });

  testWidgets('a transfer between currencies converts at the day rate', (
    tester,
  ) async {
    final app = LedgerApp();
    await _openSheet(tester, app);

    await _tap(tester, find.text('Transfer'));
    expect(find.text('Category'), findsNothing);
    expect(find.text('Who'), findsNothing);
    await tester.enterText(_amountInput(), '100');
    await _pickAccount(tester, 'To', 'Cash (IQD)');
    // The arriving amount is optional; empty converts at the day's rate.
    expect(find.text('Arrives'), findsWidgets);
    await _tap(tester, find.text('Save transfer'));

    final [txn] = app.saved;
    expect(txn['type'], 'transfer');
    expect(txn['accountId'], 'acc-checking');
    expect(txn['toAccountId'], 'acc-cash');
    expect(txn['toAmountMinor'], 170500);
    expect(txn['categoryId'], isNull);
    await _toastGone(tester);
  });

  testWidgets('a transfer to the same account is refused next to To', (
    tester,
  ) async {
    final app = LedgerApp();
    await _openSheet(tester, app);

    await _tap(tester, find.text('Transfer'));
    await tester.enterText(_amountInput(), '5');
    await _pickAccount(tester, 'To', 'My checking ••1187');
    await _tap(tester, find.text('Save transfer'));

    expect(find.text('Choose a different account.'), findsOneWidget);
    expect(app.saved, isEmpty);
  });

  testWidgets('a loan names its person and direction', (tester) async {
    final app = LedgerApp();
    await _openSheet(tester, app);

    await _tap(tester, find.text('Loan'));
    await _tap(tester, find.text('I lent'));
    await tester.enterText(_amountInput(), '300');
    await _tap(tester, find.text('Save loan'));
    expect(find.text("Add who it's with."), findsOneWidget);
    expect(app.saved, isEmpty);

    await tester.enterText(_field('Person'), 'Alex');
    await _tap(tester, find.text('Save loan'));

    final [txn] = app.saved;
    expect(txn['type'], 'loan_given');
    expect(txn['amountMinor'], 30000);
    expect(txn['personName'], 'Alex');
    expect(txn['title'], 'Alex');
    await _toastGone(tester);
  });

  testWidgets('the currency follows the account; dinars get no decimal key', (
    tester,
  ) async {
    final app = LedgerApp();
    await _openSheet(tester, app);

    await tester.enterText(_amountInput(), '12.50');
    await _pickAccount(tester, 'Account', 'Cash (IQD)');
    expect(find.text('IQD'), findsOneWidget);
    final input = tester.widget<CupertinoTextField>(_amountInput());
    expect(input.keyboardType, const TextInputType.numberWithOptions());
    // The cents are dropped with the currency, and a point cannot be typed.
    expect(input.controller!.text, '12');
    await tester.enterText(_amountInput(), '10000.5');
    expect(input.controller!.text, '12');
    await tester.enterText(_amountInput(), '10000');
    await _tap(tester, find.text('Food'));
    await _tap(tester, find.text('Save expense'));

    final [txn] = app.saved;
    expect(txn['currency'], 'IQD');
    expect(txn['amountMinor'], 10000);
    expect(txn['baseAmountMinor'], 587);
    await _toastGone(tester);
  });

  testWidgets('empty fields show their errors next to them', (tester) async {
    final app = LedgerApp();
    await _openSheet(tester, app);

    // The header's Save checks the same way as the bottom button.
    await _tap(tester, find.text('Save'));
    expect(find.text('Enter an amount.'), findsOneWidget);
    expect(find.text('Choose a category.'), findsOneWidget);
    expect(find.text('Add manually'), findsOneWidget);

    await tester.enterText(_amountInput(), '9');
    await tester.pump();
    expect(find.text('Enter an amount.'), findsNothing);
    expect(app.saved, isEmpty);
  });

  testWidgets('a day with no rate asks for one inline', (tester) async {
    final app = LedgerApp(withRate: false);
    await _openSheet(tester, app);

    await _pickAccount(tester, 'Account', 'Cash (IQD)');
    await tester.enterText(_amountInput(), '10000');
    await _tap(tester, find.text('Food'));
    await _tap(tester, find.text('Save expense'));
    expect(
      find.text("There's no dollar rate for this day yet. Enter it to save."),
      findsOneWidget,
    );
    expect(app.saved, isEmpty);

    await tester.enterText(_field('Dollar rate, dinars per dollar'), '1,500');
    await _tap(tester, find.text('Save expense'));
    final [txn] = app.saved;
    expect(txn['fx'], containsPair('source', 'manual'));
    expect(txn['fx'], containsPair('pairRate', '1500'));
    expect(txn['baseAmountMinor'], 667);
    await _toastGone(tester);
  });

  testWidgets('a prefilled draft opens on its values ("Change" on a slip)', (
    tester,
  ) async {
    final app = LedgerApp();
    await _openSheet(
      tester,
      app,
      extra: EntryDraft(
        id: 'slip-1',
        intent: 'expense',
        amountMinor: 10000,
        currency: 'IQD',
        accountId: 'acc-cash',
        categoryId: 'dining',
        who: 'me',
        title: 'Kebab place',
        origin: 'parser',
      ),
    );

    expect(find.text('IQD'), findsOneWidget);
    expect(find.text('Cash (IQD)'), findsOneWidget);
    final input = tester.widget<CupertinoTextField>(_amountInput());
    expect(input.controller!.text, '10000');
    await _tap(tester, find.text('Groceries'));
    await _tap(tester, find.text('Save expense'));

    final [txn] = app.saved;
    expect(txn['categoryId'], 'groceries');
    expect(txn['title'], 'Kebab place');
    // A draft from a slip keeps its origin: saved as from Ask.
    expect(txn['source'], 'chat');
    await _toastGone(tester);
  });

  testWidgets('Cancel with changes asks before discarding', (tester) async {
    final app = LedgerApp();
    await _openSheet(tester, app);

    await tester.enterText(_amountInput(), '5');
    await _tap(tester, find.text('Cancel'));
    expect(find.text('Discard changes'), findsOneWidget);
    await _tap(tester, find.text('Keep editing'));
    expect(find.text('Add manually'), findsOneWidget);

    await _tap(tester, find.text('Cancel'));
    await _tap(tester, find.text('Discard changes'));
    expect(find.text('Add manually'), findsNothing);
    expect(app.saved, isEmpty);
  });

  testWidgets('Cancel on an untouched sheet closes it at once', (tester) async {
    final app = LedgerApp();
    await _openSheet(tester, app);
    await _tap(tester, find.text('Cancel'));
    expect(find.text('Add manually'), findsNothing);
    expect(find.text('Discard changes'), findsNothing);
  });
}
