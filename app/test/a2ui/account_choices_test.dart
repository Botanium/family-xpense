// The owner's first phone test (2026-11-24): "10000 iqd dinner" in a
// one-member household with only dollar accounts showed "Which account?"
// with no answers and a dead "Fix it in the form". The slip now offers
// every account (the save converts), and with none, offers to add one.
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:xpense_app/a2ui/testing/fake_xpense_actions.dart';
import 'package:xpense_app/a2ui/xpense_surface_host.dart';
import 'package:xpense_app/core/ui/ui.dart';
import 'package:xpense_shared/xpense_shared.dart';

import 'a2ui_harness.dart';

/// The owner's household with [accounts]: no partner, a rate entered.
XpenseHousehold _solo(List<HouseholdAccount> accounts) => XpenseHousehold(
  baseCurrency: 'USD',
  accounts: accounts,
  categories: sampleHousehold.categories,
  soleMember: true,
  latestRate: '1705',
  rateEnteredToday: true,
);

const _cash = HouseholdAccount(id: 'a_cash', name: 'Cash', currency: 'USD');
const _bank = HouseholdAccount(id: 'a_bank', name: 'Bank', currency: 'USD');
const _savings = HouseholdAccount(
  id: 'a_sav',
  name: 'Savings',
  currency: 'USD',
);
const _wallet = HouseholdAccount(id: 'a_wal', name: 'Wallet', currency: 'IQD');

/// IQD 10,000 dining out, the account missing (the fixture's draft).
Future<FakeXpenseActions> _pumpDinner(
  WidgetTester tester,
  List<HouseholdAccount> accounts,
) async {
  final actions = FakeXpenseActions(household: _solo(accounts));
  final (:host, actions: _, sent: _) = hostWith(
    fixture('local_capture_missing_account'),
    actions: actions,
  );
  await pumpThread(tester, host);
  return actions;
}

bool _saveEnabled(WidgetTester tester) =>
    tester
        .widget<XpPressable>(
          find
              .ancestor(
                of: find.text('Save'),
                matching: find.byType(XpPressable),
              )
              .first,
        )
        .onPressed !=
    null;

Finder _pick(String id) => find.byKey(ValueKey('pick_accountId_$id'));

void main() {
  testWidgets('only accounts in the other currency: all are offered, and a '
      'pick saves with a conversion note', (tester) async {
    final actions = await _pumpDinner(tester, [_cash, _bank, _savings]);
    expect(find.text('Which account?'), findsOneWidget);
    expect(find.text('Fix it in the form'), findsNothing);
    for (final id in ['a_cash', 'a_bank', 'a_sav']) {
      expect(_pick(id), findsOneWidget);
    }
    expect(_saveEnabled(tester), isFalse);

    await tester.tap(_pick('a_bank'));
    await tester.pump();
    expect(
      find.text(
        "This account is in USD: saving converts the amount at the day's "
        'rate.',
      ),
      findsOneWidget,
    );
    expect(_saveEnabled(tester), isTrue);
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    final saved = actions.calls.single.argument! as List<EntryDraft>;
    // The draft keeps the member's dinars; the write path converts.
    expect(
      (saved.single.accountId, saved.single.currency, saved.single.amountMinor),
      ('a_bank', 'IQD', 10000),
    );
  });

  testWidgets('one account: it is the one answer', (tester) async {
    await _pumpDinner(tester, [_cash]);
    expect(_pick('a_cash'), findsOneWidget);
    await tester.tap(_pick('a_cash'));
    await tester.pump();
    expect(_saveEnabled(tester), isTrue);
  });

  testWidgets('several accounts in both currencies: all are offered', (
    tester,
  ) async {
    await _pumpDinner(tester, [_cash, _wallet]);
    expect(_pick('a_cash'), findsOneWidget);
    expect(_pick('a_wal'), findsOneWidget);
    await tester.tap(_pick('a_wal'));
    await tester.pump();
    // Same currency: nothing to convert.
    expect(find.textContaining('converts'), findsNothing);
    expect(_saveEnabled(tester), isTrue);
  });

  testWidgets('no accounts: says so and offers to add one; the new account '
      'is offered when the sheet closes', (tester) async {
    final actions = await _pumpDinner(tester, const []);
    expect(find.text('Which account?'), findsNothing);
    expect(
      find.text('There are no accounts yet. Add one to save this.'),
      findsOneWidget,
    );
    expect(_saveEnabled(tester), isFalse);

    // The sheet adds an account; the slip reads the household again.
    actions.household = _solo(const [_cash]);
    await tester.tap(find.byKey(const ValueKey('add_account')));
    await tester.pump();
    expect(actions.methods, ['openAddAccount']);
    expect(find.text('Which account?'), findsOneWidget);
    expect(_pick('a_cash'), findsOneWidget);
  });
}
