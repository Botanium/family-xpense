// Accounts (screen 10), account detail (screen 11) and Add accounts
// (screen 4) through the whole app and router, on the fakes (WP-13,
// BACKLOG S1.6, S1.7, S1.8).
import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xpense_app/app.dart';
import 'package:xpense_app/core/routing/routing.dart';
import 'package:xpense_app/core/ui/ui.dart';
import 'package:xpense_app/data/accounts_repository.dart';
import 'package:xpense_app/data/accounts_repository_fake.dart';
import 'package:xpense_shared/xpense_shared.dart';

import '../onboarding/onboarding_screens_test.dart'
    show field, location, tapLabel, usePhone;
import '../support/test_app.dart';
import '../ui/ui_harness.dart' show loadSignalFonts;

Future<(ProviderContainer, FakeAccountsRepository)> pumpAt(
  WidgetTester tester,
  String path, {
  FakeAccountsRepository? accounts,
  bool settle = true,
}) async {
  usePhone(tester);
  final repository =
      accounts ?? (FakeAccountsRepository.sample()..sharingDelay = null);
  final container = await pumpXpenseApp(
    tester,
    TestServices(accounts: repository),
  );
  container.read(routerProvider).go(path);
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    // A spinner never settles: pump past the page transition instead.
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
  }
  return (container, repository);
}

Finder amountField() => find.descendant(
  of: find.byType(AmountField),
  matching: find.byType(EditableText),
);

void main() {
  setUpAll(loadSignalFonts);

  group('Accounts (screen 10)', () {
    testWidgets('the total, the filter bar and the rows', (tester) async {
      await pumpAt(tester, AppRoutes.accounts);

      expect(find.text('ACCOUNTS'), findsOneWidget);
      // Sam keeps an account private: this is the member's view only.
      expect(find.text('Your view'), findsOneWidget);
      expect(find.text('USD 12,480.00'), findsOneWidget);
      expect(find.text("Sam's private accounts aren't included."), findsOne);
      for (final label in ['All', 'Mine', 'Sam', 'Joint']) {
        expect(find.text(label), findsWidgets);
      }
      expect(find.text('My checking ••1187'), findsOneWidget);
      expect(find.text('Bank account · You'), findsOneWidget);
      expect(find.text('Bank account · Sam, shared'), findsOneWidget);
      expect(find.text('Credit card · Joint'), findsOneWidget);
      expect(find.text('IQD 315,425'), findsOneWidget);
      expect(find.text('≈ 185.00'), findsOneWidget);
      expect(find.text("Sam's savings"), findsNothing);
    });

    testWidgets("filters keep mine, the partner's or joint", (tester) async {
      await pumpAt(tester, AppRoutes.accounts);

      await tapLabel(tester, 'Sam');
      expect(find.text("Sam's checking ••5530"), findsOneWidget);
      expect(find.text('My checking ••1187'), findsNothing);
      expect(find.text('Joint Visa ••4021'), findsNothing);

      await tapLabel(tester, 'Mine');
      expect(find.text('My checking ••1187'), findsOneWidget);
      expect(find.text('Cash (IQD)'), findsOneWidget);
      expect(find.text("Sam's checking ••5530"), findsNothing);

      // The total stays the household figure the member can see.
      expect(find.text('USD 12,480.00'), findsOneWidget);
    });

    testWidgets('the partner sees nothing of a private account', (
      tester,
    ) async {
      final partner = FakeAccountsRepository.sample(
        viewerUid: FakeAccountsRepository.samplePartner,
      )..sharingDelay = null;
      await pumpAt(tester, AppRoutes.accounts, accounts: partner);

      expect(find.text('My checking ••1187'), findsNothing);
      expect(find.textContaining('1187'), findsNothing);
      expect(find.text('3,940.00'), findsNothing);
      // 12,480.00 − my 3,940.00 + Sam's own 9,000.00.
      expect(find.text('USD 17,540.00'), findsOneWidget);
      expect(find.text('Your view'), findsOneWidget);
    });

    testWidgets('"Household balance" when nothing is hidden', (tester) async {
      final accounts = FakeAccountsRepository(
        members: const [
          HouseholdMember(
            uid: FakeAccountsRepository.sampleViewer,
            displayName: 'You',
          ),
          HouseholdMember(
            uid: FakeAccountsRepository.samplePartner,
            displayName: 'Sam',
          ),
        ],
        accounts: [
          FakeAccountsRepository.sampleAccounts[2], // Joint Visa
        ],
      );
      await pumpAt(tester, AppRoutes.accounts, accounts: accounts);
      expect(find.text('Household balance'), findsOneWidget);
      expect(find.text('−USD 612.00'), findsOneWidget);
    });

    testWidgets('the plus button adds an account with its opening balance', (
      tester,
    ) async {
      final (_, accounts) = await pumpAt(tester, AppRoutes.accounts);

      await tester.tap(find.bySemanticsLabel('Add an account'));
      await tester.pumpAndSettle();
      expect(find.text('New account'), findsOneWidget);
      await tapLabel(tester, 'Bank');
      await tester.enterText(field('Name'), 'Rafidain ••2210');
      await tester.enterText(amountField(), '1200.50');
      await tapLabel(tester, 'Add account');

      expect(find.text('New account'), findsNothing);
      final draft = accounts.created.single;
      expect(draft.name, 'Rafidain ••2210');
      expect(draft.kind, AccountKind.bank);
      expect(draft.currency, Currency.usd);
      expect(draft.scope, AccountScope.personal);
      expect(draft.openingBalanceMinor, 120050);
      expect(find.text('Rafidain ••2210'), findsOneWidget);
      expect(find.text('USD 13,680.50'), findsOneWidget);
    });

    testWidgets('empty: a line and an Add action', (tester) async {
      await pumpAt(
        tester,
        AppRoutes.accounts,
        accounts: FakeAccountsRepository(),
      );
      expect(
        find.text('No accounts yet. Add one with the plus button.'),
        findsOneWidget,
      );
      expect(find.text('USD 0.00'), findsOneWidget);
    });
  });

  group('Account detail (screen 11)', () {
    testWidgets('sharing shows "Sharing past entries…" until the server is '
        'done', (tester) async {
      final (container, accounts) = await pumpAt(tester, AppRoutes.accounts);
      await tapLabel(tester, 'My checking ••1187');
      expect(location(container).path, AppRoutes.account('acc-checking'));
      expect(find.text('ACCOUNT'), findsOneWidget);
      expect(find.text('My checking ••1187 · You'), findsOneWidget);
      expect(find.text('USD 3,940.00'), findsOneWidget);
      expect(find.text('Share with Sam'), findsOneWidget);
      expect(
        find.text('Only you see this account and its entries.'),
        findsOneWidget,
      );

      await tester.tap(find.byType(XpSwitch));
      await tester.pump();
      await tester.pump();

      expect(accounts.calls.last, 'setShared');
      final shared = accounts.allAccounts.singleWhere(
        (a) => a.id == 'acc-checking',
      );
      expect(
        shared.visibleTo,
        [
          FakeAccountsRepository.samplePartner,
          FakeAccountsRepository.sampleViewer,
        ]..sort(),
      );
      expect(find.text('Sam sees this account and its entries.'), findsOne);
      expect(find.text('Sharing past entries…'), findsOneWidget);
      expect(find.byType(XpSpinner), findsOneWidget);

      accounts.finishSharing('acc-checking');
      await tester.pumpAndSettle();
      expect(find.text('Sharing past entries…'), findsNothing);
      expect(find.byType(XpSpinner), findsNothing);

      // Back on the list the row is now "You, shared".
      await tester.tap(find.bySemanticsLabel('Back'));
      await tester.pumpAndSettle();
      expect(find.text('Bank account · You, shared'), findsOneWidget);
    });

    testWidgets('the progress line counts entries while the server works', (
      tester,
    ) async {
      final accounts = FakeAccountsRepository.sample()..sharingDelay = null;
      final cash = accounts.allAccounts.singleWhere((a) => a.id == 'acc-cash');
      accounts.put(
        Account(
          id: cash.id,
          name: cash.name,
          kind: cash.kind,
          currency: cash.currency,
          scope: cash.scope,
          ownerUid: cash.ownerUid,
          sharedWithPartner: true,
          visibleTo: cash.visibleTo,
          balanceMinor: cash.balanceMinor,
          order: cash.order,
          visibilityRev: 1,
          sharingDone: 18,
          sharingTotal: 42,
        ),
      );
      await pumpAt(
        tester,
        AppRoutes.account('acc-cash'),
        accounts: accounts,
        settle: false,
      );
      expect(find.text('Sharing past entries… 18 of 42'), findsOneWidget);
    });

    testWidgets("no switch on a joint or the partner's account", (
      tester,
    ) async {
      await pumpAt(tester, AppRoutes.account('acc-sam-checking'));
      expect(find.text("Sam's checking ••5530 · Sam, shared"), findsOneWidget);
      expect(find.byType(XpSwitch), findsNothing);
    });

    testWidgets("a partner's private account is not found", (tester) async {
      await pumpAt(tester, AppRoutes.account('acc-sam-private'));
      expect(find.text("This account isn't here anymore."), findsOneWidget);
      expect(find.text("Sam's savings"), findsNothing);
    });

    testWidgets('entries show signed, with the opening balance named', (
      tester,
    ) async {
      final accounts = FakeAccountsRepository.sample()
        ..sharingDelay = null
        ..setEntries('acc-checking', [
          AccountEntry(
            id: 't1',
            title: 'Salary',
            type: 'income',
            amountMinor: 320000,
            currency: Currency.usd,
            occurredAt: DateTime(2026, 11, 21, 12),
          ),
          AccountEntry(
            id: 't0',
            title: '',
            type: 'adjustment',
            amountMinor: 74000,
            currency: Currency.usd,
            occurredAt: DateTime(2026, 11, 1, 12),
          ),
        ]);
      await pumpAt(
        tester,
        AppRoutes.account('acc-checking'),
        accounts: accounts,
      );
      expect(find.text('Salary'), findsOneWidget);
      expect(find.text('Nov 21 · Income'), findsOneWidget);
      expect(find.text('+3,200.00'), findsOneWidget);
      expect(find.text('Opening balance'), findsOneWidget);
      expect(find.text('Nov 1 · Balance'), findsOneWidget);
    });

    testWidgets('archive from the more menu, then restore', (tester) async {
      final (_, accounts) = await pumpAt(tester, AppRoutes.account('acc-visa'));
      await tester.tap(find.bySemanticsLabel('More'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Archive'));
      await tester.pumpAndSettle();

      expect(
        accounts.allAccounts.singleWhere((a) => a.id == 'acc-visa').archived,
        isTrue,
      );
      expect(find.text('Archived: hidden from lists and totals.'), findsOne);

      await tester.tap(find.bySemanticsLabel('More'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Restore'));
      await tester.pumpAndSettle();
      expect(
        accounts.allAccounts.singleWhere((a) => a.id == 'acc-visa').archived,
        isFalse,
      );
    });

    testWidgets('edit renames the account', (tester) async {
      final (_, accounts) = await pumpAt(tester, AppRoutes.account('acc-visa'));
      await tester.tap(find.bySemanticsLabel('More'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Edit'));
      await tester.pumpAndSettle();
      expect(find.text('Edit account'), findsOneWidget);
      expect(
        find.text("The currency can't change once an account is added."),
        findsOneWidget,
      );
      await tester.enterText(field('Name'), 'Family Visa');
      await tapLabel(tester, 'Save');

      expect(
        accounts.allAccounts.singleWhere((a) => a.id == 'acc-visa').name,
        'Family Visa',
      );
      expect(find.text('Family Visa · Joint'), findsOneWidget);
    });
  });

  group('Add accounts (screen 4)', () {
    testWidgets("step 3 of 4: add cash in dinars with today's rate, then "
        'Continue to Try it', (tester) async {
      final accounts = FakeAccountsRepository();
      final (container, _) = await pumpAt(
        tester,
        AppRoutes.addAccounts,
        accounts: accounts,
      );
      expect(find.text('ADD ACCOUNTS'), findsOneWidget);
      expect(find.bySemanticsLabel('Step 3 of 4'), findsOneWidget);
      expect(find.text('Where does your money live?'), findsOneWidget);
      expect(find.textContaining('Or just say it'), findsOneWidget);

      // The currency toggle switches the amount to dinars.
      await tester.tap(find.bySemanticsLabel('Currency, USD'));
      await tester.pumpAndSettle();
      await tester.enterText(amountField(), '250000');
      await tester.pumpAndSettle();
      // The household has no rate yet, so the form asks for one.
      expect(find.text("Today's dollar rate, in dinars"), findsOneWidget);
      await tapLabel(tester, 'Add account');
      expect(find.text('Enter the rate, such as 1,705.'), findsOneWidget);
      expect(accounts.created, isEmpty);

      await tester.enterText(field("Today's dollar rate, in dinars"), '1,705');
      await tapLabel(tester, 'Add account');

      final draft = accounts.created.single;
      expect(draft.currency, Currency.iqd);
      expect(draft.openingBalanceMinor, 250000);
      expect(draft.openingRate?.rateString, '1705');
      expect(draft.name, 'Cash');
      // The form clears for the next account and the list shows this one.
      expect(find.text('Added'), findsOneWidget);
      expect(find.text('IQD 250,000'), findsOneWidget);
      expect(find.text('≈ 146.63'), findsOneWidget);

      await tapLabel(tester, 'Continue');
      expect(location(container).path, AppRoutes.tryIt);
    });

    testWidgets('a joint card owes money', (tester) async {
      final accounts = FakeAccountsRepository();
      await pumpAt(tester, AppRoutes.addAccounts, accounts: accounts);
      await tapLabel(tester, 'Card');
      expect(find.text('Card · amount owed'), findsOneWidget);
      await tapLabel(tester, 'Joint');
      await tester.enterText(field('Name'), 'Joint Visa ••4021');
      await tester.enterText(amountField(), '612');
      await tapLabel(tester, 'Add account');

      final draft = accounts.created.single;
      expect(draft.scope, AccountScope.joint);
      expect(draft.openingBalanceMinor, -61200);
      expect(find.text('−612.00'), findsOneWidget);
    });
  });
}
