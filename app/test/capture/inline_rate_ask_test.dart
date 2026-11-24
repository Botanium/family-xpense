// WP-24: Add manually asks for today's rate inline when nobody in the
// household has entered it (ARCHITECTURE 3.5, D-16). Skippable: the entry
// then uses the latest rate and records its date.
import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xpense_app/core/routing/routing.dart';
import 'package:xpense_app/core/ui/ui.dart';
import 'package:xpense_app/data/fx_repository.dart';
import 'package:xpense_shared/xpense_shared.dart';

import 'ledger_app.dart';

Finder _amountInput() => find
    .descendant(
      of: find.byType(AmountField),
      matching: find.byType(CupertinoTextField),
    )
    .first;

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

/// Lets a glass sheet or action sheet finish moving.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// Opens Add manually on a dinar expense of 10,000 in Food.
Future<void> _dinarExpense(WidgetTester tester, LedgerApp app) async {
  final container = await app.pump(tester);
  await pushTo(tester, container, AppRoutes.addEntry);
  await _tap(tester, find.widgetWithText(XpDisclosure, 'Account'));
  await _tap(tester, find.text('Cash (IQD)').last);
  await tester.enterText(_amountInput(), '10000');
  await tester.pump();
  await _tap(tester, find.text('Food'));
}

FxRate _rate(String v) => FxRate.forPair(FxPair.usdIqd, v).valueOrNull!;

final Finder _ask = find.descendant(
  of: find.byType(GlassSheet),
  matching: find.byType(RatePrompt),
);

void main() {
  // The test clock's today is 2026-11-22; LedgerApp's rate is from Nov 1.

  testWidgets('skipped: the entry uses the latest rate and records its day', (
    tester,
  ) async {
    final app = LedgerApp();
    await _dinarExpense(tester, app);

    expect(_ask, findsOneWidget);
    expect(tester.widget<RatePrompt>(_ask).rate, '1,705');
    expect(
      find.text('Or skip: this entry then uses 1,705 from Nov 1.'),
      findsOneWidget,
    );
    await _tap(tester, find.text('Save expense'));

    final [txn] = app.saved;
    expect(txn['fx'], containsPair('pairRate', '1705'));
    expect(txn['fx'], containsPair('asOf', '2026-11-01'));
    expect(app.fx.written, isEmpty, reason: 'skipping writes no rate');
    await tester.pump(const Duration(seconds: 11));
    await tester.pumpAndSettle();
  });

  testWidgets("Use it: today's rate is saved for the household", (
    tester,
  ) async {
    final app = LedgerApp();
    await _dinarExpense(tester, app);

    await _tap(tester, find.text('Use it'));
    expect(app.fx.written.single.day, '2026-11-22');
    expect(_ask, findsNothing);
    await _tap(tester, find.text('Save expense'));

    final [txn] = app.saved;
    expect(txn['fx'], containsPair('asOf', '2026-11-22'));
    await tester.pump(const Duration(seconds: 11));
    await tester.pumpAndSettle();
  });

  testWidgets("Change: a typed rate is today's, after the >5% check", (
    tester,
  ) async {
    final app = LedgerApp();
    await _dinarExpense(tester, app);

    await _tap(tester, find.text('Change').last);
    await _settle(tester);
    for (var i = 0; i < 4; i++) {
      await tester.tap(find.bySemanticsLabel('Delete').last);
      await tester.pump();
    }
    for (final key in '1500'.split('')) {
      await tester.tap(find.text(key).last);
      await tester.pump();
    }
    await tester.tap(find.text('Save').last);
    await _settle(tester);
    // 1,500 is 12% from 1,705: asked first.
    await tester.tap(find.text('Save 1,500'));
    await _settle(tester);
    await tester.pumpAndSettle();

    expect(app.fx.written.single.rate.rateString, '1500');
    await _tap(tester, find.text('Save expense'));
    final [txn] = app.saved;
    expect(txn['fx'], containsPair('pairRate', '1500'));
    expect(txn['baseAmountMinor'], 667);
    await tester.pump(const Duration(seconds: 11));
    await tester.pumpAndSettle();
  });

  testWidgets('answered by the partner: no ask', (tester) async {
    final app = LedgerApp();
    app.fx.put(
      DailyRate(day: '2026-11-22', rate: _rate('1710'), enteredBy: partner),
    );
    await _dinarExpense(tester, app);
    expect(_ask, findsNothing);
  });

  testWidgets('a dollar entry needs no rate: no ask', (tester) async {
    final app = LedgerApp();
    final container = await app.pump(tester);
    await pushTo(tester, container, AppRoutes.addEntry);
    await tester.enterText(_amountInput(), '12');
    await tester.pump();
    expect(_ask, findsNothing);
  });

  testWidgets('an entry on another day is priced by that day: no ask', (
    tester,
  ) async {
    final app = LedgerApp();
    final container = await app.pump(tester);
    await pushTo(
      tester,
      container,
      AppRoutes.addEntry,
      extra: EntryDraft(
        id: 'd',
        intent: 'expense',
        amountMinor: 10000,
        currency: 'IQD',
        accountId: 'acc-cash',
        categoryId: 'food',
        occurredOn: '2026-11-20',
      ),
    );
    expect(_ask, findsNothing);
  });

  testWidgets('a slip quote gives way to the rate answered here (Codex '
      'review, PR #42)', (tester) async {
    final app = LedgerApp();
    final container = await app.pump(tester);
    await pushTo(
      tester,
      container,
      AppRoutes.addEntry,
      extra: EntryDraft(
        id: 'slip-1',
        intent: 'expense',
        amountMinor: 10000,
        currency: 'IQD',
        accountId: 'acc-cash',
        categoryId: 'food',
        occurredOn: '2026-11-22',
        origin: 'parser',
        // Previewed on the slip at the latest rate.
        fx: FxQuote(pair: 'USD/IQD', pairRate: '1705', baseAmountMinor: 587),
      ),
    );

    await _tap(tester, find.text('Change').last);
    await _settle(tester);
    await tester.tap(find.bySemanticsLabel('Delete').last);
    await tester.pump();
    await tester.tap(find.text('0').last);
    await tester.pump();
    await tester.tap(find.text('Save').last);
    await _settle(tester);
    await tester.pumpAndSettle();
    expect(app.fx.written.single.rate.rateString, '1700');

    await _tap(tester, find.text('Save expense'));
    final [txn] = app.saved;
    expect(txn['fx'], containsPair('pairRate', '1700'));
    expect(txn['fx'], containsPair('asOf', '2026-11-22'));
    await tester.pump(const Duration(seconds: 11));
    await tester.pumpAndSettle();
  });
}
