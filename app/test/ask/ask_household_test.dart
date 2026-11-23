// The household Ask uses: built from the app's own household data, so the
// ids on a card are ones the write path can save.
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xpense_app/app.dart';
import 'package:xpense_app/bootstrap.dart';
import 'package:xpense_app/core/routing/routing.dart';
import 'package:xpense_app/data/accounts_repository.dart';
import 'package:xpense_app/data/accounts_repository_fake.dart';
import 'package:xpense_app/data/household_repository.dart';
import 'package:xpense_app/data/household_repository_fake.dart';
import 'package:xpense_app/data/rules_repository.dart';
import 'package:xpense_app/features/ask/ask_household.dart';
import 'package:xpense_shared/xpense_shared.dart';

import '../support/test_app.dart';

void main() {
  test('accounts, partner, base currency and rate come from the app', () {
    final h = xpenseHouseholdFrom(
      membership: const InHousehold(FakeHouseholdRepository.sampleHousehold),
      accounts: const [
        Account(
          id: 'a1',
          name: 'Checking',
          kind: AccountKind.bank,
          currency: Currency.usd,
          scope: AccountScope.personal,
          visibleTo: ['me'],
        ),
        Account(
          id: 'a2',
          name: 'Old cash',
          kind: AccountKind.cash,
          currency: Currency.iqd,
          scope: AccountScope.personal,
          visibleTo: ['me'],
          archived: true,
        ),
      ],
      members: const [
        HouseholdMember(uid: 'me', displayName: 'Dara'),
        HouseholdMember(uid: 'p', displayName: 'Shilan'),
      ],
      viewerUid: 'me',
      latestRate: FxRate.parse('USD/IQD', '1520').valueOrNull,
    );
    expect(h.baseCurrency, 'USD');
    expect([for (final a in h.accounts) a.id], ['a1'], reason: 'not archived');
    expect(h.accounts.single.currency, 'USD');
    expect(h.partnerName, 'Shilan');
    expect(h.latestRate, '1520');
    expect(h.category('groceries')?.name, 'Groceries');
    expect(h.category('other_expense'), isNotNull);
  });

  testWidgets('in the fakes environment a card saves through the write path', (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(390, 1400) * 3
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final services = TestServices(accounts: FakeAccountsRepository.sample())
      ..xpenseActionsFor = connectXpenseActions;
    // The sample household's own account id, as a learned rule.
    await services.rules.learn(
      const RuleLesson(
        kind: RuleKind.merchant,
        pattern: 'Costco',
        categoryId: 'groceries',
        accountId: 'acc-checking',
      ),
    );
    final container = await pumpXpenseApp(tester, services);
    container.read(routerProvider).go(AppRoutes.ask);
    await tester.pumpAndSettle();
    expect(
      container.read(askHouseholdProvider).account('acc-checking'),
      isNotNull,
    );
    await tester.enterText(find.byType(EditableText), 'Costco 42.80');
    await tester.testTextInput.receiveAction(TextInputAction.send);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.text('Saved.'), findsOneWidget);
    expect(services.actions.saved, isEmpty, reason: 'not the fake');
  });
}
