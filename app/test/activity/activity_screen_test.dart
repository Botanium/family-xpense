// Activity (screen 16) through the whole app and router, on the fakes
// (WP-22, BACKLOG S2.4): day groups with the net, the filter bar, "Search or
// ask", swipe Edit and Delete with Undo, the context menu, and the loading,
// empty, error and offline states.
import 'dart:async';

import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xpense_app/bootstrap.dart';
import 'package:xpense_app/core/routing/routing.dart';
import 'package:xpense_app/core/ui/ui.dart';
import 'package:xpense_app/data/accounts_repository_fake.dart';
import 'package:xpense_app/data/read/activity_reader.dart';
import 'package:xpense_app/data/read/activity_reader_memory.dart';
import 'package:xpense_app/data/transactions_repository.dart';
import 'package:xpense_app/features/activity/activity_controller.dart';
import 'package:xpense_app/features/activity/activity_dates.dart';
import 'package:xpense_app/features/activity/activity_model.dart';
import 'package:xpense_app/features/activity/activity_row.dart';
import 'package:xpense_app/features/activity/activity_screen.dart';
import 'package:xpense_shared/xpense_shared.dart';

import '../onboarding/onboarding_screens_test.dart' show location;
import '../support/test_app.dart';
import '../ui/ui_harness.dart' show loadSignalFonts;
import 'activity_harness.dart';

Finder searchField() => find.descendant(
  of: find.byType(XpSearchField),
  matching: find.byType(EditableText),
);

Finder row(String title) => find.ancestor(
  of: find.text(title),
  matching: find.byType(ActivityEntryRow),
);

Future<void> swipe(WidgetTester tester, String title, double dx) async {
  await tester.drag(row(title), Offset(dx, 0));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(loadSignalFonts);

  group('day groups', () {
    testWidgets('entries grouped by day, newest first, with the net in mono', (
      tester,
    ) async {
      await pumpActivity(tester);

      expect(find.text('ACTIVITY'), findsOneWidget);
      expect(find.text('Today'), findsOneWidget);
      expect(find.text('Yesterday'), findsOneWidget);
      expect(find.text('Nov 20'), findsOneWidget);
      // Income minus spending; the loan to Alex is left out.
      expect(find.text('+1,757.20'), findsOneWidget);
      expect(find.text('+91.90'), findsOneWidget);

      // Newest first within the day.
      final today = [
        'Costco',
        'Alex',
        'Salary',
        'Rent',
      ].map((t) => tester.getTopLeft(find.text(t)).dy).toList();
      expect(today, orderedEquals([...today]..sort()));

      // Category · who · account; amounts signed, other currencies coded.
      expect(find.text('Groceries · You · Joint Visa ••4021'), findsOneWidget);
      expect(find.text('Fuel · Sam · Joint Visa ••4021'), findsOneWidget);
      expect(
        find.text('Loan given · You · My checking ••1187'),
        findsOneWidget,
      );
      expect(find.text('Home · Joint · My checking ••1187'), findsOneWidget);
      expect(find.text('−42.80'), findsOneWidget);
      expect(find.text('+3,200.00'), findsOneWidget);
      expect(find.text('300.00'), findsOneWidget);
      expect(find.text('−IQD 41,175'), findsOneWidget);
    });

    testWidgets('an untitled correction names its type once', (tester) async {
      await pumpActivity(
        tester,
        drafts: [
          entry(
            'fix',
            intent: 'adjustment',
            amount: 500,
            account: 'acc-checking',
          ),
        ],
      );
      expect(find.text('Balance correction'), findsOneWidget);
      expect(find.text('You · My checking ••1187'), findsOneWidget);
    });

    testWidgets('tapping a row opens the entry', (tester) async {
      final container = await pumpActivity(tester);
      final id = idOf(tester, 'Costco');
      await tester.tap(find.text('Costco'));
      await tester.pumpAndSettle();
      expect(location(container).toString(), AppRoutes.entry(id));
    });
  });

  group('filters', () {
    testWidgets('All, Out, In, Loans, You and the partner by name', (
      tester,
    ) async {
      await pumpActivity(tester);
      for (final label in ['All', 'Out', 'In', 'Loans', 'You', 'Sam']) {
        expect(find.text(label), findsWidgets, reason: label);
      }

      Future<Set<String>> shown(String filter) async {
        final tab = find.descendant(
          of: find.byType(XpFilterBar),
          matching: find.text(filter),
        );
        // The bar scrolls sideways when the labels are wider than the
        // screen.
        await tester.ensureVisible(tab);
        await tester.pumpAndSettle();
        await tester.tap(tab);
        await tester.pumpAndSettle();
        return shownTitles(tester);
      }

      expect(await shown('Out'), {'Costco', 'Rent', 'Shell', 'Pharmacy'});
      expect(await shown('In'), {'Salary', 'Bike sale'});
      expect(await shown('Loans'), {'Alex'});
      expect(await shown('You'), {'Costco', 'Alex', 'Salary', 'Pharmacy'});
      expect(await shown('Sam'), {'Shell', 'Bike sale'});
      expect(await shown('All'), hasLength(7));
    });

    testWidgets(
      'every filter asks the feed with visibleTo and the filter only',
      (tester) async {
        final container = await pumpActivity(tester);
        final controller = container.read(activityControllerProvider.notifier);
        final queries = <ActivityQuery?>[];
        for (final f in [
          ActivityFilter.all,
          ActivityFilter.out,
          ActivityFilter.inflow,
          ActivityFilter.loans,
          ActivityFilter.you,
          ActivityFilter.partner,
        ]) {
          controller.select(f);
          queries.add(container.read(activityQueryProvider));
        }
        expect(queries, [
          const ActivityQuery(limit: 50),
          const ActivityQuery(limit: 50, types: {LedgerType.expense}),
          const ActivityQuery(limit: 50, types: {LedgerType.income}),
          const ActivityQuery(limit: 50, types: ActivityFilter.loanTypes),
          const ActivityQuery(
            limit: 50,
            whoUid: FakeAccountsRepository.sampleViewer,
          ),
          const ActivityQuery(
            limit: 50,
            whoUid: FakeAccountsRepository.samplePartner,
          ),
        ]);
      },
    );

    testWidgets('no partner tab before the partner joins', (tester) async {
      await pumpActivity(
        tester,
        drafts: [entry('a', amount: 100, account: 'acc-checking')],
        services: TestServices(
          accounts: FakeAccountsRepository(
            accounts: FakeAccountsRepository.sampleAccounts,
          ),
        ),
      );
      final bar = tester.widget<XpFilterBar>(find.byType(XpFilterBar));
      expect(bar.labels, ['All', 'Out', 'In', 'Loans', 'You']);
    });

    testWidgets('a filter with nothing in it says so', (tester) async {
      await pumpActivity(
        tester,
        drafts: [entry('a', amount: 100, account: 'acc-checking')],
      );
      await tester.tap(find.text('Loans'));
      await tester.pumpAndSettle();
      expect(find.text('Nothing here yet.'), findsOneWidget);
    });
  });

  group('Search or ask', () {
    testWidgets('searches title, note, category and amount', (tester) async {
      await pumpActivity(tester);

      Future<Set<String>> results(String text) async {
        await tester.enterText(searchField(), text);
        await tester.pumpAndSettle();
        return shownTitles(tester);
      }

      expect(await results('costco'), {'Costco'});
      expect(await results('towels'), {'Costco'}); // the note
      expect(await results('fuel'), {'Shell'}); // the category name
      expect(await results('42.8'), {'Costco'}); // the amount
      expect(await results('1,400'), {'Rent'});
      expect(await results('nothing like this'), isEmpty);
      expect(find.text('No matches in the loaded entries.'), findsOneWidget);
      expect(await results(''), hasLength(7));
    });

    testWidgets('a question shows "Ask" and opens Ask with the text', (
      tester,
    ) async {
      final container = await pumpActivity(tester);
      const question = 'How much did we spend on food?';
      await tester.enterText(searchField(), question);
      await tester.pumpAndSettle();
      expect(find.text('Ask “$question”'), findsOneWidget);

      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();
      expect(location(container).toString(), AppRoutes.askWith(text: question));
    });

    testWidgets('a plain search does not open Ask', (tester) async {
      final container = await pumpActivity(tester);
      await tester.enterText(searchField(), 'costco');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();
      expect(location(container).toString(), AppRoutes.activity);
      expect(find.textContaining('Ask “'), findsNothing);
    });
  });

  group('swipe actions', () {
    testWidgets('swipe, Delete, then Undo brings the entry back', (
      tester,
    ) async {
      await pumpActivity(tester);
      await swipe(tester, 'Costco', -200);
      expect(find.text('Edit'), findsOneWidget);
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();

      expect(find.text('Costco'), findsNothing);
      expect(find.text('Costco deleted'), findsOneWidget);
      // The day's net follows: 1,757.20 + 42.80.
      expect(find.text('+1,800.00'), findsOneWidget);

      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();
      expect(find.text('Costco'), findsOneWidget);
      expect(find.text('Costco deleted'), findsNothing);
      expect(find.text('+1,757.20'), findsOneWidget);
    });

    testWidgets('a long swipe deletes without a second tap', (tester) async {
      await pumpActivity(tester);
      await swipe(tester, 'Rent', -340);
      expect(find.text('Rent'), findsNothing);
      expect(find.text('Rent deleted'), findsOneWidget);
      // The toast goes after ten seconds; the entry stays deleted.
      await tester.pump(const Duration(seconds: 11));
      await tester.pumpAndSettle();
      expect(find.text('Rent deleted'), findsNothing);
      expect(find.text('Rent'), findsNothing);
    });

    testWidgets('a short swipe springs back; opening one row closes another', (
      tester,
    ) async {
      await pumpActivity(tester);
      await swipe(tester, 'Costco', -20);
      expect(find.text('Delete'), findsNothing);

      await swipe(tester, 'Costco', -200);
      expect(find.text('Delete'), findsOneWidget);
      await swipe(tester, 'Salary', -200);
      expect(find.text('Delete'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('Delete')).dy,
        closeTo(tester.getTopLeft(find.text('Salary')).dy, 40),
      );
    });

    testWidgets('Edit opens the entry with its form', (tester) async {
      final container = await pumpActivity(tester);
      final id = idOf(tester, 'Shell');
      await swipe(tester, 'Shell', -200);
      await tester.tap(find.text('Edit'));
      await tester.pumpAndSettle();
      expect(location(container).toString(), activityEditLocation(id));
    });

    testWidgets('VoiceOver gets Edit and Delete as row actions', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await pumpActivity(tester);
      expect(
        tester.getSemantics(find.text('Costco')),
        matchesSemantics(
          isButton: true,
          hasEnabledState: true,
          isEnabled: true,
          hasTapAction: true,
          customActions: const [
            CustomSemanticsAction(label: 'Edit'),
            CustomSemanticsAction(label: 'Delete'),
          ],
          label: 'Costco\nGroceries · You · Joint Visa ••4021\n−42.80',
        ),
      );
      semantics.dispose();
    });
  });

  group('context menu', () {
    testWidgets('long-press shows Edit and Delete; Delete deletes', (
      tester,
    ) async {
      await pumpActivity(tester);
      final gesture = await tester.startGesture(
        tester.getCenter(find.text('Salary')),
      );
      await tester.pump(kLongPressTimeout * 2);
      await tester.pump(const Duration(seconds: 1));
      await gesture.up();
      await tester.pumpAndSettle();
      expect(find.byType(CupertinoContextMenuAction), findsNWidgets(2));
      await tester.tap(
        find.descendant(
          of: find.byType(CupertinoContextMenuAction),
          matching: find.text('Delete'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Salary deleted'), findsOneWidget);
      expect(find.byType(ActivityEntryRow), findsNWidgets(6));
      await tester.pump(const Duration(seconds: 11));
    });
  });

  group('states', () {
    testWidgets('empty: one line and Add one, which opens Ask', (tester) async {
      final container = await pumpActivity(tester, drafts: const []);
      expect(find.text('No entries yet.'), findsOneWidget);
      await tester.tap(find.text('Add one'));
      await tester.pumpAndSettle();
      expect(location(container).toString(), AppRoutes.ask);
    });

    testWidgets('loading shows the skeleton', (tester) async {
      await pumpWithReader(tester, _NeverReader());
      expect(find.byType(Skeleton), findsOneWidget);
    });

    testWidgets('error: a line and Try again, which reads again', (
      tester,
    ) async {
      final feed = MemoryActivityReader.empty(
        viewerUid: FakeAccountsRepository.sampleViewer,
      )..failure = const ActivityReadFailed('unavailable');
      await pumpWithReader(tester, feed);
      await tester.pumpAndSettle();
      expect(find.text("Couldn't load your entries."), findsOneWidget);

      feed.failure = null;
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(find.text('No entries yet.'), findsOneWidget);
    });

    testWidgets('the rules refusing the read says so', (tester) async {
      await pumpWithReader(
        tester,
        MemoryActivityReader.empty(
          viewerUid: FakeAccountsRepository.sampleViewer,
        )..failure = const ActivityNotAllowed(),
      );
      await tester.pumpAndSettle();
      expect(
        find.text("You can't see these entries any more."),
        findsOneWidget,
      );
    });

    testWidgets('offline: the strip shows once the cache is all there is', (
      tester,
    ) async {
      final feed = MemoryActivityReader.empty(
        viewerUid: FakeAccountsRepository.sampleViewer,
      )..fromCache = true;
      await pumpWithReader(tester, feed);
      // Not at once: a normal start is served from the cache first.
      expect(find.byType(OfflineBanner), findsNothing);
      await tester.pump(ActivityScreen.offlineGrace);
      await tester.pumpAndSettle();
      expect(find.text('Offline. Showing saved entries.'), findsOneWidget);

      feed
        ..fromCache = false
        ..changed();
      await tester.pumpAndSettle();
      expect(find.byType(OfflineBanner), findsNothing);
    });

    testWidgets('an entry still on the phone shows the syncing dot', (
      tester,
    ) async {
      final container = await pumpActivity(tester);
      (container.read(activityReaderProvider) as MemoryActivityReader)
        ..syncing = {idOf(tester, 'Costco')}
        ..changed();
      await tester.pumpAndSettle();
      expect(
        find.descendant(of: row('Costco'), matching: find.byType(Dot)),
        findsOneWidget,
      );
      expect(
        find.descendant(of: row('Salary'), matching: find.byType(Dot)),
        findsNothing,
      );
    });
  });

  group('paging and 1,000 rows', () {
    List<EntryDraft> many(int count) => [
      for (var i = 0; i < count; i++)
        entry(
          'e$i',
          amount: 100 + i,
          title: 'Entry $i',
          on: _dayBefore('2026-11-22', i ~/ 12),
          time: '${(20 - (i % 12)).toString().padLeft(2, '0')}:00',
        ),
    ];

    testWidgets('scrolling pages back 50 at a time and builds lazily', (
      tester,
    ) async {
      final container = await pumpActivity(tester, drafts: many(1000));
      final feed =
          container.read(activityReaderProvider) as MemoryActivityReader;
      expect(feed.opened.last.limit, 50);
      // Only what is on screen (and the cache extent) is built.
      expect(
        tester.widgetList(find.byType(ActivityEntryRow)).length,
        lessThan(30),
      );

      final list = find.byType(Scrollable).last;
      var frames = 0;
      final watch = Stopwatch()..start();
      while (!tester.any(find.text('Entry 999'))) {
        await tester.drag(list, const Offset(0, -2000));
        await tester.pump();
        await tester.pump();
        frames++;
        expect(frames, lessThan(400), reason: 'never reached the end');
      }
      watch.stop();
      expect(feed.opened.last.limit, 1000);
      expect(
        tester.widgetList(find.byType(ActivityEntryRow)).length,
        lessThan(40),
      );
      // Not a frame-rate measurement (that needs a device in profile
      // mode); a guard that one scroll step stays cheap with 1,000 rows.
      // ignore: avoid_print
      print(
        '1,000 rows: $frames scroll steps in ${watch.elapsedMilliseconds} ms',
      );
    });
  });
  group('Codex review, PR #38', () {
    testWidgets('an empty phone-filtered window still offers older entries', (
      tester,
    ) async {
      final reader = _ScriptedReader();
      final container = await pumpWithReader(tester, reader);
      container
          .read(activityControllerProvider.notifier)
          .select(ActivityFilter.loans);
      await tester.pumpAndSettle();
      expect(find.text('Nothing here in the entries loaded so far.'), findsOne);

      await tester.tap(find.text('Load older entries'));
      await tester.pumpAndSettle();
      expect(reader.opened.last.limit, 100);
      expect(find.text('Old loan'), findsOneWidget);
    });

    testWidgets('a queued delete the server refuses later says so', (
      tester,
    ) async {
      final inner = memoryTransactions();
      final repository = _LateFailing(inner);
      await pumpWithReader(
        tester,
        inner.reader,
        transactions: repository,
        drafts: artboardEntries(),
      );
      await tester.pumpAndSettle();
      final id = idOf(tester, 'Costco');
      await swipe(tester, 'Costco', -340);
      expect(find.text('Costco deleted'), findsOneWidget);

      // Someone else's refused write is not this screen's to report.
      repository.late.add(
        const LateWriteFailure(
          txnIds: ['elsewhere'],
          failure: TransactionsNotAllowed(),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining("didn't go through"), findsNothing);

      repository.late.add(
        LateWriteFailure(txnIds: [id], failure: const TransactionsNotAllowed()),
      );
      await tester.pumpAndSettle();
      expect(
        find.text(
          "A change you made offline didn't go through. "
          'The entry is back as it was.',
        ),
        findsOneWidget,
      );
      await tester.pump(const Duration(seconds: 11));
    });

    testWidgets('a read error after data shows above the kept list', (
      tester,
    ) async {
      final inner = memoryTransactions();
      await pumpWithReader(
        tester,
        inner.reader,
        transactions: inner,
        drafts: artboardEntries(),
      );
      await tester.pumpAndSettle();
      expect(find.text('Costco'), findsOneWidget);

      inner.reader
        ..failure = const ActivityReadFailed('unavailable')
        ..changed();
      await tester.pumpAndSettle();
      expect(find.text("Couldn't load your entries."), findsOneWidget);
      expect(find.text('Costco'), findsOneWidget);

      inner.reader.failure = null;
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(find.text("Couldn't load your entries."), findsNothing);
      expect(find.text('Costco'), findsOneWidget);
    });
  });
}

String _dayBefore(String day, int days) => dayBefore(DateTime.parse(day), days);

final class _NeverReader implements ActivityReader {
  // A read that never answers.
  final StreamController<ActivityWindow> _never = StreamController();

  @override
  Stream<ActivityWindow> watch(ActivityQuery query) => _never.stream;
}

/// Answers the first page with nothing (all filtered out on the phone) but
/// more behind it, and the second with one old loan.
final class _ScriptedReader implements ActivityReader {
  final List<ActivityQuery> opened = [];

  @override
  Stream<ActivityWindow> watch(ActivityQuery query) {
    opened.add(query);
    return Stream.value(
      query.limit <= 50
          ? const ActivityWindow(
              entries: [],
              hasMore: true,
              filteredOnPhone: true,
            )
          : ActivityWindow(
              entries: [
                LedgerTransaction(
                  id: 'old-loan',
                  type: LedgerType.loanGiven,
                  amountMinor: 5000,
                  currency: Currency.usd,
                  accountId: 'acc-checking',
                  baseAmountMinor: 5000,
                  whoScope: WhoScope.member,
                  whoUid: FakeAccountsRepository.sampleViewer,
                  occurredAt: DateTime.utc(2026, 9, 1, 12),
                  occurredOn: '2026-09-01',
                  visibleTo: const [FakeAccountsRepository.sampleViewer],
                  title: 'Old loan',
                ),
              ],
              hasMore: false,
              filteredOnPhone: true,
            ),
    );
  }
}

/// The memory write path, with late failures the test raises by hand.
final class _LateFailing implements TransactionsRepository {
  new(this._inner);

  final TransactionsRepository _inner;
  final StreamController<LateWriteFailure> late =
      StreamController<LateWriteFailure>.broadcast();

  @override
  Stream<LateWriteFailure> get lateFailures => late.stream;

  @override
  Future<Result<SavedEntries, TransactionsFailure>> saveEntries(
    List<EntryDraft> drafts, {
    EntrySource? source,
    Map<String, EntryExtras> extras = const {},
  }) => _inner.saveEntries(drafts, source: source, extras: extras);

  @override
  Future<Result<WriteAck, TransactionsFailure>> editEntry(
    String txnId,
    EntryDraft draft, {
    EntryExtras extras = const EntryExtras(),
  }) => _inner.editEntry(txnId, draft, extras: extras);

  @override
  Future<Result<WriteAck, TransactionsFailure>> deleteEntry(
    String txnId, {
    DeleteReason reason = DeleteReason.delete,
  }) => _inner.deleteEntry(txnId, reason: reason);

  @override
  Future<Result<WriteAck, TransactionsFailure>> undoSave(SavedEntries saved) =>
      _inner.undoSave(saved);

  @override
  Future<Result<WriteAck, TransactionsFailure>> restoreEntry(String txnId) =>
      _inner.restoreEntry(txnId);
}
