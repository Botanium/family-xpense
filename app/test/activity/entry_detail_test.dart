import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xpense_app/app.dart';
import 'package:xpense_app/core/routing/routing.dart';
import 'package:xpense_app/core/ui/ui.dart';
import 'package:xpense_app/data/read/entry_reader.dart';
import 'package:xpense_app/data/transactions_repository.dart';
import 'package:xpense_app/features/activity/detail/entry_history.dart';
import 'package:xpense_shared/xpense_shared.dart';

import '../capture/ledger_app.dart';

/// Saves a dinar expense on the joint Visa, then moves it to cash, as on
/// artboard 17. Returns its id.
Future<String> seedEntry(LedgerApp app) async {
  final saved = await app.repository.saveEntries([
    EntryDraft(
      id: 'd1',
      intent: 'expense',
      amountMinor: 10000,
      currency: 'IQD',
      accountId: 'acc-cash',
      categoryId: 'dining',
      who: 'me',
      occurredOn: '2026-11-22',
      occurredTime: '08:20',
      note: 'Lunch with the kids',
      origin: 'on_device',
    ),
  ], source: EntrySource.voice);
  final id = saved.valueOrNull!.txnIds.single;
  final edited = await app.repository.editEntry(
    id,
    EntryDraft(
      id: 'd1',
      intent: 'expense',
      amountMinor: 12000,
      currency: 'IQD',
      accountId: 'acc-cash',
      categoryId: 'dining',
      who: 'me',
      occurredOn: '2026-11-22',
      occurredTime: '08:20',
      note: 'Lunch with the kids',
    ),
  );
  expect(edited.isOk, isTrue);
  return id;
}

/// A USD expense edited from 10.00 to 12.00, then moved to the IQD cash
/// account as 12,000 dinars. Returns its id.
Future<String> seedCurrencyMove(LedgerApp app) async {
  EntryDraft draft(int amount, String currency, String account) => EntryDraft(
    id: 'd1',
    intent: 'expense',
    amountMinor: amount,
    currency: currency,
    accountId: account,
    categoryId: 'groceries',
    who: 'me',
    occurredOn: '2026-11-22',
    occurredTime: '08:20',
  );
  final saved = await app.repository.saveEntries([
    draft(1000, 'USD', 'acc-checking'),
  ]);
  final id = saved.valueOrNull!.txnIds.single;
  expect(
    (await app.repository.editEntry(
      id,
      draft(1200, 'USD', 'acc-checking'),
    )).isOk,
    isTrue,
  );
  expect(
    (await app.repository.editEntry(id, draft(12000, 'IQD', 'acc-cash'))).isOk,
    isTrue,
  );
  return id;
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Map<String, Object?> _stored(LedgerApp app, String id) =>
    app.memory.transactions[id]!;

void main() {
  group('buildHistory', () {
    test('each row keeps the currency it was written in', () async {
      // Codex review, PR #39: an old USD amount change read as IQD after
      // the entry moved to a dinar account.
      final app = LedgerApp();
      final id = await seedCurrencyMove(app);
      final record = await app.reader.watchEntry(id).first;
      final revisions = await app.reader.watchRevisions(id).first;
      final [moved, amount, created] = buildHistory(record!, revisions);
      expect(moved.parts, {ChangedPart.account, ChangedPart.amount});
      expect(moved.beforeState['currency'], 'USD');
      expect(moved.afterState['currency'], 'IQD');
      expect(amount.onlyPart, ChangedPart.amount);
      expect(amount.beforeState['currency'], 'USD');
      expect(amount.afterState['currency'], 'USD');
      expect(amount.afterState['amountMinor'], 1200);
      expect(created.afterState['currency'], 'USD');
      expect(created.afterState['amountMinor'], 1000);
    });

    test('rows run newest first, each with its before and after', () async {
      final app = LedgerApp();
      final id = await seedEntry(app);
      final record = await app.reader.watchEntry(id).first;
      final revisions = await app.reader.watchRevisions(id).first;
      final history = buildHistory(record!, revisions);

      expect(history.map((h) => h.kind), [
        HistoryKind.edit,
        HistoryKind.created,
      ]);
      final edit = history.first;
      expect(edit.onlyPart, ChangedPart.amount);
      expect(edit.before['amountMinor'], 10000);
      expect(edit.after['amountMinor'], 12000);
      expect(edit.restorable, isTrue);
      expect(edit.actor, viewer);
      expect(history.last.after['amountMinor'], 10000);
      expect(history.last.restorable, isFalse);
    });

    test(
      'Restore of an edit drafts the old values on the current entry',
      () async {
        final app = LedgerApp();
        final id = await seedEntry(app);
        final record = await app.reader.watchEntry(id).first;
        final revisions = await app.reader.watchRevisions(id).first;
        final restored = restoreDraft(
          record!.txn,
          revisions.single,
          viewerUid: viewer,
        )!;
        expect(restored.draft.amountMinor, 10000);
        expect(restored.draft.note, 'Lunch with the kids');
        final result = await app.repository.editEntry(
          id,
          restored.draft,
          extras: restored.extras,
        );
        expect(result.isOk, isTrue);
        expect(_stored(app, id)['amountMinor'], 10000);
      },
    );

    test('only the latest delete of a deleted entry offers Restore', () async {
      final app = LedgerApp();
      final id = await seedEntry(app);
      await app.repository.deleteEntry(id);
      final record = await app.reader.watchEntry(id).first;
      final revisions = await app.reader.watchRevisions(id).first;
      final history = buildHistory(record!, revisions);
      expect(history.first.kind, HistoryKind.delete);
      expect(history.first.restorable, isTrue);
      // Field restores wait until the entry is back.
      expect(history[1].restorable, isFalse);
    });
  });

  testWidgets('entry detail shows the amount, rows, rate, source and history', (
    tester,
  ) async {
    final app = LedgerApp();
    final id = await seedEntry(app);
    final container = await app.pump(tester);
    await pushTo(tester, container, AppRoutes.entry(id));

    expect(find.text('ENTRY'), findsOneWidget);
    expect(find.text('EXPENSE · DINING OUT'), findsOneWidget);
    expect(find.text('≈ USD 7.04 AT 1,705 · MARKET'), findsOneWidget);
    expect(find.widgetWithText(XpDisclosure, 'Dining out'), findsOneWidget);
    expect(find.widgetWithText(XpDisclosure, 'Cash (IQD)'), findsOneWidget);
    expect(find.widgetWithText(XpDisclosure, 'You'), findsOneWidget);
    expect(find.text('Lunch with the kids'), findsOneWidget);
    expect(find.text('1,705 · MARKET'), findsOneWidget);
    expect(find.text('VOICE · ON-DEVICE'), findsOneWidget);
    await tester.ensureVisible(find.text('Created by voice'));
    expect(find.text('Amount changed'), findsOneWidget);
    expect(find.text('IQD 10,000 → IQD 12,000'), findsOneWidget);
    expect(find.text('Restore'), findsOneWidget);

    await _tap(tester, find.text('Restore'));
    expect(_stored(app, id)['amountMinor'], 10000);
    // The restore is itself a change in the history.
    expect(find.text('IQD 12,000 → IQD 10,000'), findsOneWidget);
  });

  testWidgets('tapping a row opens the edit sheet at that field', (
    tester,
  ) async {
    final app = LedgerApp();
    final id = await seedEntry(app);
    final container = await app.pump(tester);
    await pushTo(tester, container, AppRoutes.entry(id));

    await _tap(tester, find.widgetWithText(XpDisclosure, 'Category'));
    expect(find.text('Edit entry'), findsOneWidget);
    expect(find.text('Save changes'), findsOneWidget);
    await _tap(tester, find.text('Groceries'));
    await _tap(tester, find.text('Save changes'));

    expect(find.text('Edit entry'), findsNothing);
    expect(container.read(routerProvider).state.uri.path, AppRoutes.entry(id));
    expect(_stored(app, id)['categoryId'], 'groceries');
    expect(find.widgetWithText(XpDisclosure, 'Groceries'), findsOneWidget);
    await tester.ensureVisible(find.text('Category changed'));
    expect(find.text('Dining out → Groceries'), findsOneWidget);
  });

  testWidgets('a transfer into an archived account can still be edited', (
    tester,
  ) async {
    // Codex review, PR #39: the form dropped the archived destination, so
    // even a note change was refused.
    final app = LedgerApp();
    final saved = await app.repository.saveEntries([
      EntryDraft(
        id: 'd1',
        intent: 'transfer',
        amountMinor: 22500,
        currency: 'USD',
        accountId: 'acc-checking',
        toAccountId: 'acc-trip',
        occurredOn: '2026-11-22',
      ),
    ]);
    final id = saved.valueOrNull!.txnIds.single;
    await app.services.accounts.setArchived('acc-trip', archived: true);
    final container = await app.pump(tester);
    await pushTo(tester, container, AppRoutes.entry(id));
    expect(find.widgetWithText(XpDisclosure, 'Summer trip'), findsOneWidget);

    await _tap(tester, find.widgetWithText(XpDisclosure, 'Note'));
    expect(find.text('Edit entry'), findsOneWidget);
    // The sheet still shows the archived destination.
    expect(
      find.descendant(
        of: find.byType(GlassSheet),
        matching: find.widgetWithText(XpDisclosure, 'Summer trip'),
      ),
      findsOneWidget,
    );
    await tester.enterText(
      find.descendant(
        of: find.widgetWithText(XpTextField, 'Note'),
        matching: find.byType(EditableText),
      ),
      'Flights',
    );
    await _tap(tester, find.text('Save changes'));

    expect(find.text('Edit entry'), findsNothing);
    expect(_stored(app, id)['note'], 'Flights');
    expect(_stored(app, id)['toAccountId'], 'acc-trip');
  });

  testWidgets("renaming a loan's person renames its title", (tester) async {
    final app = LedgerApp();
    final saved = await app.repository.saveEntries([
      EntryDraft(
        id: 'd1',
        intent: 'loan_given',
        amountMinor: 30000,
        currency: 'USD',
        accountId: 'acc-checking',
        personName: 'Alex',
        occurredOn: '2026-11-22',
      ),
    ]);
    final id = saved.valueOrNull!.txnIds.single;
    expect(_stored(app, id)['title'], 'Alex');
    final container = await app.pump(tester);
    await pushTo(tester, container, AppRoutes.entry(id));

    await _tap(tester, find.widgetWithText(XpDisclosure, 'Person'));
    await tester.enterText(
      find.descendant(
        of: find.widgetWithText(XpTextField, 'Person'),
        matching: find.byType(EditableText),
      ),
      'Sam',
    );
    await _tap(tester, find.text('Save changes'));

    expect(_stored(app, id)['personName'], 'Sam');
    expect(_stored(app, id)['title'], 'Sam');
    expect(find.text('LOAN GIVEN · SAM'), findsOneWidget);
  });

  testWidgets('history amounts show the currency of their time', (
    tester,
  ) async {
    final app = LedgerApp();
    final id = await seedCurrencyMove(app);
    final container = await app.pump(tester);
    await pushTo(tester, container, AppRoutes.entry(id));

    expect(find.text('IQD 12,000'), findsWidgets);
    await tester.ensureVisible(find.text('Amount changed'));
    expect(find.text('USD 10.00 → USD 12.00'), findsOneWidget);
    // The move changed the account and the amount: one "Edited" row.
    expect(find.text('Edited'), findsOneWidget);
    await tester.ensureVisible(find.text('Added manually'));
    expect(find.text('USD 10.00'), findsOneWidget);
  });

  group('editing a transfer between currencies (Codex review, PR #39)', () {
    Future<String> seedTransfer(LedgerApp app, {int? arrives}) async {
      final saved = await app.repository.saveEntries(
        [
          EntryDraft(
            id: 'd1',
            intent: 'transfer',
            amountMinor: 10000,
            currency: 'USD',
            accountId: 'acc-checking',
            toAccountId: 'acc-cash',
            occurredOn: '2026-11-22',
          ),
        ],
        extras: {'d1': EntryExtras(toAmountMinor: arrives)},
      );
      return saved.valueOrNull!.txnIds.single;
    }

    Future<void> changeAmount(
      WidgetTester tester,
      LedgerApp app,
      String id,
    ) async {
      final container = await app.pump(tester);
      await pushTo(tester, container, AppRoutes.editEntry(id, field: 'amount'));
      expect(find.text('Edit entry'), findsOneWidget);
      await tester.enterText(
        find
            .descendant(
              of: find.byType(AmountField),
              matching: find.byType(EditableText),
            )
            .first,
        '120',
      );
      await tester.pump();
      await _tap(tester, find.text('Save changes'));
      expect(find.text('Edit entry'), findsNothing);
    }

    String arrivesText(WidgetTester tester) => tester
        .widget<EditableText>(
          find
              .descendant(
                of: find.byType(AmountField),
                matching: find.byType(EditableText),
              )
              .last,
        )
        .controller
        .text;

    testWidgets('a typed arriving amount is kept when the amount changes', (
      tester,
    ) async {
      final app = LedgerApp();
      final id = await seedTransfer(app, arrives: 150000);
      expect(_stored(app, id)['toAmountSource'], 'entered');
      final container = await app.pump(tester);
      await pushTo(tester, container, AppRoutes.editEntry(id, field: 'amount'));
      expect(arrivesText(tester), '150000');
      await tester.enterText(
        find
            .descendant(
              of: find.byType(AmountField),
              matching: find.byType(EditableText),
            )
            .first,
        '120',
      );
      await tester.pump();
      await _tap(tester, find.text('Save changes'));

      expect(_stored(app, id)['amountMinor'], 12000);
      expect(_stored(app, id)['toAmountMinor'], 150000);
      expect(_stored(app, id)['toAmountSource'], 'entered');
    });

    testWidgets('a converted arriving amount is converted again', (
      tester,
    ) async {
      final app = LedgerApp();
      final id = await seedTransfer(app);
      expect(_stored(app, id)['toAmountSource'], 'rate');
      expect(_stored(app, id)['toAmountMinor'], 170500);
      await changeAmount(tester, app, id);

      expect(_stored(app, id)['amountMinor'], 12000);
      expect(_stored(app, id)['toAmountMinor'], 204600);
      expect(_stored(app, id)['toAmountSource'], 'rate');
    });
  });

  testWidgets('delete asks first, then offers Undo', (tester) async {
    final app = LedgerApp();
    final id = await seedEntry(app);
    final container = await app.pump(tester);
    await pushTo(tester, container, AppRoutes.entry(id));

    await _tap(tester, find.widgetWithText(XpButton, 'Delete entry'));
    expect(
      find.text('Delete this entry? You can restore it from its history.'),
      findsOneWidget,
    );
    await _tap(tester, find.text('Delete entry').last);
    expect(_stored(app, id)['deletedAt'], isNotNull);
    expect(find.text('This entry is deleted.'), findsOneWidget);
    expect(find.text('Entry deleted'), findsOneWidget);

    await _tap(tester, find.text('Undo'));
    expect(_stored(app, id)['deletedAt'], isNull);
    expect(find.text('This entry is deleted.'), findsNothing);
    await tester.pump(const Duration(seconds: 11));
  });

  testWidgets('an entry that cannot be read says so', (tester) async {
    final app = LedgerApp();
    final container = await app.pump(tester);
    await pushTo(tester, container, AppRoutes.entry('missing'));
    expect(
      find.text(
        "This entry isn't here. It was removed or isn't shared with you.",
      ),
      findsOneWidget,
    );
  });

  test('the reader updates after each write', () async {
    final app = LedgerApp();
    final id = await seedEntry(app);
    final seen = <int?>[];
    final sub = app.reader
        .watchEntry(id)
        .listen((r) => seen.add(r?.txn.amountMinor));
    await pumpEventQueue();
    await app.repository.deleteEntry(id);
    await pumpEventQueue();
    await sub.cancel();
    expect(seen.first, 12000);
    expect(seen.length, 2);
    final revisions = await app.reader.watchRevisions(id).first;
    expect(revisions.map((r) => r.reason), [
      RevisionReason.delete,
      RevisionReason.edit,
    ]);
  });
}
