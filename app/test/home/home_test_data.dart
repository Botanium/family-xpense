import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:xpense_app/app.dart';
import 'package:xpense_app/bootstrap.dart';
import 'package:xpense_app/data/accounts_repository.dart';
import 'package:xpense_app/data/accounts_repository_fake.dart';
import 'package:xpense_app/data/mappers/transaction_mapper.dart';
import 'package:xpense_app/data/transactions_repository.dart';
import 'package:xpense_app/services/settings_store.dart';
import 'package:xpense_shared/xpense_shared.dart';

import '../support/test_app.dart';

/// The sample viewer and partner.
const String you = FakeAccountsRepository.sampleViewer;

/// The partner.
const String sam = FakeAccountsRepository.samplePartner;

/// Visible to both.
const List<String> both = [you, sam];

/// Home's "today" in these tests: 21 November 2026, as on the artboard.
final DateTime today = DateTime(2026, 11, 21, 19);

var _ids = 0;

/// A transaction on [day] of November 2026 (or of [month]) at [hour].
LedgerTransaction txn({
  required LedgerType type,
  required int cents,
  int day = 1,
  int month = 11,
  int hour = 9,
  int? baseCents,
  Currency currency = Currency.usd,
  String account = 'acc-visa',
  List<String> visibleTo = both,
  String? who = you,
  String title = '',
  String? category,
  String? goalId,
  String? toAccount,
  DateTime? deletedAt,
  int? adjustmentSign,
  String? id,
}) {
  final at = DateTime(2026, month, day, hour);
  return LedgerTransaction(
    id: id ?? 't${_ids++}',
    type: type,
    amountMinor: cents,
    currency: currency,
    accountId: account,
    toAccountId: toAccount,
    baseAmountMinor: baseCents ?? cents,
    whoScope: who == null ? WhoScope.joint : WhoScope.member,
    whoUid: who,
    occurredAt: at,
    occurredOn:
        '2026-${month.toString().padLeft(2, '0')}-'
        '${day.toString().padLeft(2, '0')}',
    visibleTo: visibleTo,
    title: title,
    categoryId: category,
    goalId: goalId,
    adjustmentSign: adjustmentSign,
    deletedAt: deletedAt,
  );
}

/// Daily spending shape of the artboard's chart, 1 to 21 November.
const List<int> artboardBars = [
  18, 30, 12, 44, 22, 8, 26, 38, 14, 20, 52, //
  16, 24, 10, 34, 28, 12, 40, 18, 30, 62,
];

/// A month that adds up to artboard 06: income 5,650.00, spent 4,410.00
/// (210 a day), saved 650.00, Recent Costco, Salary, Shell, Lunch. It also
/// holds what must not count: Sam's private entry, a deleted one and last
/// month's.
List<LedgerTransaction> artboardMonth() {
  _ids = 0;
  const unit = 790; // cents per bar unit: 558 units = 4,408.20
  final list = <LedgerTransaction>[];
  for (var day = 1; day <= 20; day++) {
    final cents = artboardBars[day - 1] * unit;
    if (day == 5) {
      // An IQD 10,000 lunch, stored at 5.87 dollars (1,705 a dollar).
      list
        ..add(
          txn(
            type: LedgerType.expense,
            cents: 10000,
            baseCents: 587,
            currency: Currency.iqd,
            account: 'acc-cash',
            day: day,
            title: 'Lunch',
            category: 'dining',
          ),
        )
        ..add(
          txn(
            type: LedgerType.expense,
            cents: cents - 587,
            day: day,
            category: 'groceries',
          ),
        );
    } else {
      list.add(
        txn(
          type: LedgerType.expense,
          cents: cents,
          day: day,
          category: 'groceries',
        ),
      );
    }
  }
  // Today: 62 units plus 1.80, so the month is exactly 4,410.00.
  const todayTotal = 62 * unit + 180;
  list.addAll([
    txn(
      type: LedgerType.expense,
      cents: todayTotal - 4280 - 5810 - 1840,
      day: 21,
      hour: 7,
      category: 'groceries',
    ),
    txn(
      type: LedgerType.expense,
      cents: 1840,
      day: 21,
      hour: 12,
      who: null,
      title: 'Lunch',
      category: 'dining',
    ),
    txn(
      type: LedgerType.expense,
      cents: 5810,
      day: 21,
      hour: 15,
      who: sam,
      title: 'Shell',
      category: 'fuel',
    ),
    txn(
      type: LedgerType.income,
      cents: 320000,
      day: 21,
      hour: 16,
      account: 'acc-checking',
      visibleTo: const [you],
      title: 'Salary',
      category: 'salary',
    ),
    txn(
      type: LedgerType.expense,
      cents: 4280,
      day: 21,
      hour: 18,
      title: 'Costco',
      category: 'groceries',
    ),
    txn(
      type: LedgerType.income,
      cents: 245000,
      day: 15,
      account: 'acc-sam-checking',
      who: sam,
      title: 'Salary',
      category: 'salary',
    ),
    txn(
      type: LedgerType.transfer,
      cents: 65000,
      day: 2,
      account: 'acc-checking',
      toAccount: 'acc-trip',
      title: 'Summer trip',
      goalId: 'goal-trip',
    ),
    // None of these count.
    txn(
      type: LedgerType.expense,
      cents: 999900,
      day: 10,
      account: 'acc-sam-private',
      visibleTo: const [sam],
      who: sam,
      title: 'Private',
    ),
    txn(
      type: LedgerType.expense,
      cents: 777700,
      day: 11,
      title: 'Deleted',
      deletedAt: DateTime.utc(2026, 11, 12),
    ),
    txn(
      type: LedgerType.expense,
      cents: 555500,
      day: 30,
      month: 10,
      title: 'Last month',
    ),
  ]);
  return list;
}

/// Puts [transactions] in [ledger] as stored documents.
void seed(MemoryLedger ledger, Iterable<LedgerTransaction> transactions) {
  for (final t in transactions) {
    ledger.store.seedTransaction(t.id, {
      ...transactionContent(t),
      'deletedAt': t.deletedAt,
      'rev': 0,
    });
  }
}

/// The app's overrides over [services], with [ledger] as both the write
/// and the read path.
List<Override> homeOverrides(TestServices services, MemoryLedger ledger) =>
    appOverrides(
      clock: services.clock.clock,
      settings: services.settingsStore,
      biometricLock: services.biometricLock,
      glass: services.glass,
      authRepository: services.auth,
      householdRepository: services.households,
      accountsRepository: services.accounts,
      transactionsRepository: ledger.repository,
      homeReader: ledger.reader,
      featureFlags: services.flags,
      onDeviceLlm: services.onDeviceLlm,
      speechCapture: services.speech,
    );

/// The artboard household: the sample accounts without Sam's private
/// savings, so the hero reads "Household balance" as on artboard 06 (the
/// total is the same: that account is never visible to the viewer).
TestServices artboardServices({
  AppearanceMode appearance = AppearanceMode.light,
}) => TestServices(
  settings: AppSettings(appearance: appearance),
  accounts: FakeAccountsRepository(
    members: const [
      HouseholdMember(uid: you, displayName: 'You'),
      HouseholdMember(uid: sam, displayName: 'Sam'),
    ],
    accounts: [
      for (final a in FakeAccountsRepository.sampleAccounts)
        if (a.id != 'acc-sam-private') a,
    ],
    rate: FxRate.forPair(FxPair.usdIqd, '1705').valueOrNull,
  ),
);

/// Pumps the app on Home with the sample household, [transactions] in the
/// ledger and the clock at [today]. Returns the ledger.
Future<MemoryLedger> pumpHome(
  WidgetTester tester, {
  Iterable<LedgerTransaction> transactions = const [],
  TestServices? services,
}) async {
  // An iPhone-sized view, as on the artboards (390 x 844 pt at 3x).
  tester.view
    ..physicalSize = const Size(390, 844) * 3
    ..devicePixelRatio = 3
    // The artboards' frame: safe areas 47 top and 34 bottom.
    ..padding = const FakeViewPadding(top: 47 * 3, bottom: 34 * 3)
    ..viewPadding = const FakeViewPadding(top: 47 * 3, bottom: 34 * 3);
  addTearDown(tester.view.reset);
  final s = services ?? artboardServices();
  s.clock.now = today;
  final ledger = memoryLedger();
  seed(ledger, transactions);
  final container = ProviderContainer.test(
    overrides: homeOverrides(s, ledger),
    retry: (_, _) => null,
  );
  await tester.pumpWidget(
    UncontrolledProviderScope(container: container, child: const XpenseApp()),
  );
  await tester.pumpAndSettle();
  return ledger;
}
