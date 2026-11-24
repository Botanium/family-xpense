// The Ask cards' navigation through the app's router (owner's first phone
// test, 2026-11-24: "Fix it in the form" did nothing, as the app passed
// the in-memory fake for navigation).
import 'package:flutter_test/flutter_test.dart';
import 'package:xpense_app/a2ui/testing/fake_xpense_actions.dart';
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
    WidgetTester tester,
  ) async {
    usePhone(tester);
    final container = await pumpXpenseApp(
      tester,
      TestServices(accounts: FakeAccountsRepository()),
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
    actions.openManualForm({
      'id': 'd1',
      'intent': 'expense',
      'amountMinor': 10000,
      'currency': 'IQD',
    });
    await tester.pumpAndSettle();
    expect(find.text('Add manually'), findsOneWidget);
    expect(inner.calls, isEmpty);
  });

  test('the add-account route is its own path', () {
    expect(AppRoutes.addAccount, isNot(startsWith('${AppRoutes.accounts}/')));
  });
}
