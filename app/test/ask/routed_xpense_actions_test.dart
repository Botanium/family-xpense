// The Ask cards' navigation through the app's router (owner's first phone
// test, 2026-11-24: "Fix it in the form" did nothing, as the app passed
// the in-memory fake for navigation).
import 'package:flutter_test/flutter_test.dart';
import 'package:xpense_app/a2ui/testing/fake_xpense_actions.dart';
import 'package:xpense_app/a2ui/xpense_surface_host.dart';
import 'package:xpense_app/app.dart';
import 'package:xpense_app/core/routing/routing.dart';
import 'package:xpense_app/data/accounts_repository_fake.dart';
import 'package:xpense_app/features/ask/routed_xpense_actions.dart';

import '../onboarding/onboarding_screens_test.dart' show usePhone;
import '../support/test_app.dart';
import '../ui/ui_harness.dart' show loadSignalFonts;

void main() {
  setUpAll(loadSignalFonts);

  Future<(RoutedXpenseActions, FakeXpenseActions)> pump(
    WidgetTester tester, {
    FakeAccountsRepository? accounts,
  }) async {
    usePhone(tester);
    final container = await pumpXpenseApp(
      tester,
      TestServices(accounts: accounts ?? FakeAccountsRepository()),
    );
    final inner = FakeXpenseActions();
    return (
      RoutedXpenseActions(
        router: () => container.read(routerProvider),
        inner: inner,
      ),
      inner,
    );
  }

  testWidgets('Add an account opens the new-account sheet and completes '
      'when it closes', (tester) async {
    final (actions, _) = await pump(tester);
    var closed = false;
    final opened = actions.openAddAccount().then((_) => closed = true);
    await tester.pumpAndSettle();
    expect(find.text('New account'), findsOneWidget);
    expect(closed, isFalse);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    await opened;
    expect(find.text('New account'), findsNothing);
    expect(closed, isTrue);
  });

  testWidgets('Fix it in the form opens Add manually, also for a draft '
      'that does not read', (tester) async {
    final (actions, inner) = await pump(tester);
    FormSaved? result;
    var closed = false;
    final opened = actions
        .openManualForm({
          'id': 'd1',
          'intent': 'expense',
          'amountMinor': 10000,
          'currency': 'IQD',
        })
        .then((r) {
          result = r;
          closed = true;
        });
    await tester.pumpAndSettle();
    expect(find.text('Add manually'), findsOneWidget);
    expect(inner.calls, isEmpty);

    // Closed unsaved: nothing to settle.
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    await opened;
    expect(closed, isTrue);
    expect(result, isNull);
  });

  // Codex review, PR #46: what the form saves goes back to the card, and
  // a quiet form leaves the save's Undo to the card.
  testWidgets('a save in the form comes back to the card, with no toast '
      'when quiet', (tester) async {
    final (actions, _) = await pump(
      tester,
      accounts: FakeAccountsRepository.sample(),
    );
    FormSaved? result;
    final opened = actions
        .openManualForm({
          'id': 'd7',
          'intent': 'expense',
          'amountMinor': 4280,
          'currency': 'USD',
          'accountId': 'acc-checking',
          'categoryId': 'groceries',
          'who': 'me',
        }, quiet: true)
        .then((r) => result = r);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save expense'));
    await tester.pumpAndSettle();
    await opened;

    expect(find.text('Add manually'), findsNothing);
    // No toast with its own Undo: the card offers it.
    expect(find.text('Undo'), findsNothing);
    expect(result?.draft.id, 'd7');
    expect(result?.txnIds, hasLength(1));
    expect(result?.groupId, isNotEmpty);
  });

  // Codex review, PR #46: the form's Undo toast for a card's draft goes
  // back through the card, not straight to the write path.
  testWidgets("the form's Undo toast goes through the card", (tester) async {
    final accounts = FakeAccountsRepository.sample();
    final (actions, _) = await pump(tester, accounts: accounts);
    String? undone;
    FormSaved? result;
    final opened = actions
        .openManualForm({
          'id': 'd7',
          'intent': 'expense',
          'amountMinor': 4280,
          'currency': 'USD',
          'accountId': 'acc-checking',
          'categoryId': 'groceries',
          'who': 'me',
        }, undo: (groupId) async => undone = groupId)
        .then((r) => result = r);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save expense'));
    await tester.pumpAndSettle();
    await opened;

    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(undone, isNotNull);
    expect(undone, result?.groupId);
  });

  test('the add-account route is its own path', () {
    expect(AppRoutes.addAccount, isNot(startsWith('${AppRoutes.accounts}/')));
  });
}
