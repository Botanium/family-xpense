// WP-24: Settings > Exchange rate (S2.6): the rate label, the history, and
// correcting a day, which never rewrites saved entries.
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:xpense_app/app.dart';
import 'package:xpense_app/core/routing/routing.dart';
import 'package:xpense_app/core/ui/ui.dart';
import 'package:xpense_app/data/fx_repository.dart';
import 'package:xpense_app/features/settings_privacy/fx/rate_settings_screen.dart';
import 'package:xpense_shared/xpense_shared.dart';

import '../capture/ledger_app.dart';

FxRate _rate(String v) => FxRate.forPair(FxPair.usdIqd, v).valueOrNull!;

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// The app's clock is 2026-11-22; Sam entered the 20th, the viewer the 21st.
Future<LedgerApp> _open(WidgetTester tester) async {
  final app = LedgerApp(withRate: false);
  app.fx
    ..put(DailyRate(day: '2026-11-20', rate: _rate('1700'), enteredBy: partner))
    ..put(
      DailyRate(
        day: '2026-11-21',
        rate: _rate('1705'),
        kind: RateKind.official,
        enteredBy: viewer,
      ),
    );
  final container = await app.pump(tester);
  unawaited(container.read(routerProvider).push<void>(AppRoutes.settingsRate));
  await tester.pumpAndSettle();
  expect(find.byType(RateSettingsScreen), findsOneWidget);
  return app;
}

Future<void> _keys(WidgetTester tester, String keys, {int delete = 0}) async {
  for (var i = 0; i < delete; i++) {
    await tester.tap(find.bySemanticsLabel('Delete').last);
    await tester.pump();
  }
  for (final key in keys.split('')) {
    await tester.tap(find.text(key).last);
    await tester.pump();
  }
  await tester.tap(find.text('Save').last);
  await _settle(tester);
}

void main() {
  testWidgets('the history, newest first, with who and which label', (
    tester,
  ) async {
    await _open(tester);
    final rows = tester
        .widgetList<XpListRow>(find.byType(XpListRow))
        .map((r) => (r.title, r.subtitle))
        .toList();
    expect(rows, [
      ('Today', 'Not entered yet'),
      ('Nov 21', 'You · Official'),
      ('Nov 20', 'Sam · Market'),
    ]);
    expect(find.text('1,705'), findsOneWidget);
    expect(find.text('1,700'), findsOneWidget);
  });

  testWidgets('the label: official or market, for the rates entered next', (
    tester,
  ) async {
    final app = await _open(tester);
    await tester.tap(find.text('Official'));
    await tester.pumpAndSettle();
    expect(app.fx.kind, RateKind.official);

    await tester.tap(find.text('Today'));
    await _settle(tester);
    await _keys(tester, '');
    expect(app.fx.written.single.day, '2026-11-22');
    expect(app.fx.written.single.kind, RateKind.official);
  });

  testWidgets('correcting a past day never rewrites a saved entry', (
    tester,
  ) async {
    final app = await _open(tester);
    final saved = await app.repository.saveEntries([
      EntryDraft(
        id: 'd1',
        intent: 'expense',
        amountMinor: 17050,
        currency: 'IQD',
        accountId: 'acc-cash',
        categoryId: 'groceries',
        who: 'me',
        occurredOn: '2026-11-21',
      ),
    ]);
    final id = saved.valueOrNull!.txnIds.single;
    final before = Map<String, Object?>.of(app.memory.transactions[id]!);
    expect(before['baseAmountMinor'], 1000);

    await tester.tap(find.text('Nov 21'));
    await _settle(tester);
    expect(find.text('Dollar rate on Nov 21'), findsOneWidget);
    // 1,705 → 1,710: within 5% of the day before (1,700).
    await _keys(tester, '10', delete: 2);
    await tester.pumpAndSettle();

    expect(app.fx.written.single.day, '2026-11-21');
    expect(app.fx.written.single.rate.rateString, '1710');
    expect(find.text('1,710'), findsOneWidget);
    expect(app.memory.transactions[id], before, reason: 'kept as saved');
  });

  testWidgets('a correction more than 5% from the day before asks first', (
    tester,
  ) async {
    final app = await _open(tester);
    await tester.tap(find.text('Nov 21'));
    await _settle(tester);
    await _keys(tester, '0');
    expect(
      find.text('17,050 is more than 5% away from 1,700. Is it right?'),
      findsOneWidget,
    );
    await tester.tap(find.text('Change it'));
    await _settle(tester);
    await _keys(tester, '', delete: 1);
    // Back to 1,705: nothing changed, nothing written.
    expect(app.fx.written, isEmpty);
  });

  testWidgets('Settings links to the rate and the categories', (tester) async {
    final app = LedgerApp();
    final container = await app.pump(tester);
    unawaited(container.read(routerProvider).push<void>(AppRoutes.settings));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(XpDisclosure, 'Exchange rate'), findsOneWidget);
    expect(find.widgetWithText(XpDisclosure, 'Market'), findsOneWidget);
    await tester.tap(find.widgetWithText(XpDisclosure, 'Categories'));
    await tester.pumpAndSettle();
    expect(
      container.read(routerProvider).state.uri.path,
      '/settings/categories',
    );
  });
}
