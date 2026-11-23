// Activity (WP-22, BACKLOG S2.4) on the dev flavor against the Firebase
// emulator suite, under the fake project `demo-xpense`: the real Firestore
// SDK, the real rules and the real Activity queries (`visibleTo`,
// `deletedAt == null`, the filters). Saves entries over three days, then
// walks the screen: day groups, a filter, a search, a question handed to
// Ask, and swipe Delete with Undo, checking `deletedAt` on the server.
// Paced for the PR demo; XPENSE_MARK lines tell a recorder where it is.
// Not run by CI: it needs a simulator and the emulators. No server.
//
//   cd firebase && firebase emulators:start --project demo-xpense \
//     --only auth,firestore
//   cd app && flutter test integration_test/activity_emulator_test.dart \
//     -d <simulator> --dart-define=XPENSE_ENV=emulators
//
// Other ports: --dart-define=XPENSE_AUTH_EMULATOR=127.0.0.1:9399
// --dart-define=XPENSE_FIRESTORE_EMULATOR=127.0.0.1:8480.
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:xpense_app/app.dart';
import 'package:xpense_app/bootstrap.dart';
import 'package:xpense_app/core/routing/routing.dart';
import 'package:xpense_app/core/ui/ui.dart';
import 'package:xpense_app/data/accounts_repository.dart';
import 'package:xpense_app/data/auth_repository.dart';
import 'package:xpense_app/data/household_repository.dart';
import 'package:xpense_app/data/transactions_repository.dart';
import 'package:xpense_app/features/activity/activity_dates.dart';
import 'package:xpense_app/features/activity/activity_row.dart';
import 'package:xpense_shared/xpense_shared.dart';

Future<void> until(bool Function() done, String what) async {
  for (var i = 0; i < 150 && !done(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
  expect(done(), true, reason: 'timed out waiting for $what');
}

Future<void> hold(WidgetTester tester, int tenths) async {
  for (var i = 0; i < tenths; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// Pumps until [finder] shows, for reads that answer asynchronously.
Future<void> waitFor(WidgetTester tester, Finder finder) async {
  for (var i = 0; i < 100 && !tester.any(finder); i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  expect(finder, findsWidgets);
}

void mark(String name) => debugPrint('XPENSE_MARK $name');

String day(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Activity reads, filters, searches, deletes and undoes', (
    tester,
  ) async {
    expect(
      AppEnvironment.compiled,
      AppEnvironment.emulators,
      reason: 'run with --dart-define=XPENSE_ENV=emulators',
    );
    final app = await bootstrap(environment: AppEnvironment.compiled);
    final container = ProviderContainer(overrides: app.overrides);
    addTearDown(container.dispose);
    final firestore = FirebaseFirestore.instance;

    // A new member, household and two accounts.
    final auth = container.read(authRepositoryProvider);
    await auth.signOut();
    final email = 'wp22-${DateTime.now().millisecondsSinceEpoch}@example.com';
    final uid = (await auth.createAccountWithEmail(
      email: email,
      password: 'secret12',
    )).valueOrNull!.uid;
    final households = container.read(householdRepositoryProvider);
    final hid = (await households.create(
      name: 'Activity test',
      displayName: 'Alex',
      baseCurrency: Currency.usd,
    )).valueOrNull!;
    await until(() => households.current is InHousehold, 'the household');
    final accounts = container.read(accountsRepositoryProvider);
    await until(() => accounts.viewerUid == uid, 'the accounts adapter');
    final visa = (await accounts.create(
      const AccountDraft(
        name: 'Joint Visa',
        kind: AccountKind.credit,
        currency: Currency.usd,
        scope: AccountScope.joint,
      ),
    )).valueOrNull!;
    final checking = (await accounts.create(
      const AccountDraft(
        name: 'My checking',
        kind: AccountKind.bank,
        currency: Currency.usd,
        scope: AccountScope.personal,
        openingBalanceMinor: 500000,
      ),
    )).valueOrNull!;

    // Entries over three days, saved through the write path.
    final now = DateTime.now();
    final today = day(now);
    final yesterday = dayBefore(now, 1);
    final earlier = dayBefore(now, 2);
    EntryDraft draft(
      String id,
      String intent,
      int amount,
      String account,
      String on,
      String time, {
      String? category,
      String? title,
      String? person,
      String who = 'me',
    }) => EntryDraft(
      id: id,
      intent: intent,
      amountMinor: amount,
      accountId: account,
      categoryId: category,
      who: who,
      occurredOn: on,
      occurredTime: time,
      title: title,
      personName: person,
    );
    final repo = container.read(transactionsRepositoryProvider);
    final saved = await repo.saveEntries([
      draft(
        'rent',
        'expense',
        140000,
        checking,
        today,
        '08:00',
        category: 'home',
        title: 'Rent',
        who: 'joint',
      ),
      draft(
        'salary',
        'income',
        320000,
        checking,
        today,
        '08:30',
        category: 'salary',
        title: 'Salary',
      ),
      draft(
        'alex',
        'loan_given',
        30000,
        checking,
        today,
        '08:45',
        person: 'Sam',
      ),
      draft(
        'costco',
        'expense',
        4280,
        visa,
        today,
        '09:00',
        category: 'groceries',
        title: 'Costco',
      ),
      draft(
        'shell',
        'expense',
        5810,
        visa,
        yesterday,
        '18:00',
        category: 'fuel',
        title: 'Shell',
      ),
      draft(
        'bike',
        'income',
        15000,
        checking,
        yesterday,
        '19:00',
        category: 'sale',
        title: 'Bike sale',
      ),
      draft(
        'pharmacy',
        'expense',
        2415,
        visa,
        earlier,
        '12:00',
        category: 'health',
        title: 'Pharmacy',
      ),
    ]);
    expect(saved.valueOrNull, isNotNull, reason: '${saved.failureOrNull}');
    await firestore.waitForPendingWrites();

    // ------------------------------------------------------------ screen
    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const XpenseApp()),
    );
    await hold(tester, 10);
    container.read(routerProvider).go(AppRoutes.activity);
    await waitFor(tester, find.text('Costco'));
    mark('activity_open');
    await hold(tester, 20);

    expect(find.text('Today'), findsOneWidget);
    expect(find.text('Yesterday'), findsOneWidget);
    expect(find.text('+1,757.20'), findsOneWidget);
    expect(find.text('+91.90'), findsOneWidget);
    // The opening balance is a correction: listed, but not in the net.
    expect(find.byType(ActivityEntryRow), findsNWidgets(8));

    // A filter: a type query on the server.
    await tester.tap(find.text('In'));
    await waitFor(tester, find.text('Bike sale'));
    await hold(tester, 6);
    expect(find.byType(ActivityEntryRow), findsNWidgets(2));
    mark('filter_in');
    await tester.tap(find.text('Loans'));
    await waitFor(tester, find.text('Sam'));
    expect(find.byType(ActivityEntryRow), findsOneWidget);
    await hold(tester, 6);
    await tester.tap(find.text('All'));
    await waitFor(tester, find.text('Costco'));
    await hold(tester, 4);

    // Search, then a question.
    final field = find.descendant(
      of: find.byType(XpSearchField),
      matching: find.byType(EditableText),
    );
    await tester.enterText(field, 'fuel');
    await hold(tester, 8);
    expect(find.byType(ActivityEntryRow), findsOneWidget);
    mark('search');
    await tester.enterText(field, 'How much did we spend on fuel?');
    await hold(tester, 10);
    expect(find.text('Ask “How much did we spend on fuel?”'), findsOneWidget);
    await tester.enterText(field, '');
    await hold(tester, 6);

    // Swipe to delete, then Undo.
    final costcoId = tester
        .widgetList<ActivityEntryRow>(find.byType(ActivityEntryRow))
        .firstWhere((w) => w.txn.title == 'Costco')
        .txn
        .id;
    final costco = firestore.doc('households/$hid/transactions/$costcoId');
    await tester.drag(find.text('Costco'), const Offset(-200, 0));
    await hold(tester, 10);
    await tester.tap(find.text('Delete'));
    await hold(tester, 6);
    expect(find.text('Costco'), findsNothing);
    expect(find.text('Costco deleted'), findsOneWidget);
    mark('deleted');
    await firestore.waitForPendingWrites();
    expect(
      (await costco.get(const GetOptions(source: Source.server)))
          .data()!['deletedAt'],
      isNotNull,
    );
    await hold(tester, 10);
    await tester.tap(find.text('Undo'));
    await waitFor(tester, find.text('Costco'));
    await firestore.waitForPendingWrites();
    expect(
      (await costco.get(const GetOptions(source: Source.server)))
          .data()!['deletedAt'],
      isNull,
    );
    await hold(tester, 15);
    mark('end');
  });
}
