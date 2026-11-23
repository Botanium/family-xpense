// Shared set-up for the Activity tests (WP-22): the whole app on the fakes,
// with entries saved through the real memory write path, so deletes and
// undo go through `TransactionsRepository` exactly as in the app.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xpense_app/app.dart';
import 'package:xpense_app/bootstrap.dart';
import 'package:xpense_app/core/routing/routing.dart';
import 'package:xpense_app/data/accounts_repository_fake.dart';
import 'package:xpense_app/data/activity_feed.dart';
import 'package:xpense_app/data/transactions_repository.dart';
import 'package:xpense_app/features/activity/activity_row.dart';
import 'package:xpense_shared/xpense_shared.dart';

import '../onboarding/onboarding_screens_test.dart' show usePhone;
import '../support/test_app.dart';

/// A draft for the sample household (accounts of
/// `FakeAccountsRepository.sample`).
EntryDraft entry(
  String id, {
  required int amount,
  String intent = 'expense',
  String account = 'acc-visa',
  String? to,
  String? category,
  String who = 'me',
  String on = '2026-11-22',
  String time = '09:00',
  String? title,
  String? note,
  String? person,
  String? currency,
  FxQuote? fx,
}) => EntryDraft(
  id: id,
  intent: intent,
  amountMinor: amount,
  currency: currency,
  accountId: account,
  toAccountId: to,
  categoryId:
      category ??
      switch (intent) {
        'expense' => 'groceries',
        'income' => 'salary',
        _ => null,
      },
  who: who,
  occurredOn: on,
  occurredTime: time,
  title: title,
  note: note,
  personName: person,
  fx: fx,
);

/// The artboard's entries (docs/design 16), newest first: three days.
List<EntryDraft> artboardEntries() => [
  entry(
    'rent',
    amount: 140000,
    account: 'acc-checking',
    category: 'home',
    who: 'joint',
    title: 'Rent',
    time: '08:00',
  ),
  entry(
    'salary',
    intent: 'income',
    amount: 320000,
    account: 'acc-checking',
    title: 'Salary',
    time: '08:30',
  ),
  entry(
    'alex',
    intent: 'loan_given',
    amount: 30000,
    account: 'acc-checking',
    person: 'Alex',
    time: '08:45',
  ),
  entry('costco', amount: 4280, title: 'Costco', note: 'paper towels'),
  entry(
    'shell',
    amount: 5810,
    category: 'fuel',
    who: 'partner',
    title: 'Shell',
    on: '2026-11-21',
    time: '18:00',
  ),
  entry(
    'bike',
    intent: 'income',
    amount: 15000,
    account: 'acc-sam-checking',
    category: 'sale',
    who: 'partner',
    title: 'Bike sale',
    on: '2026-11-21',
    time: '19:00',
  ),
  entry(
    'pharmacy',
    amount: 41175,
    account: 'acc-cash',
    currency: 'IQD',
    category: 'health',
    title: 'Pharmacy',
    on: '2026-11-20',
    fx: FxQuote(pair: 'USD/IQD', pairRate: '1705'),
  ),
];

/// Saves [drafts] in batches of at most [maxEntriesPerSave].
Future<void> seed(ProviderContainer container, List<EntryDraft> drafts) async {
  final repository = container.read(transactionsRepositoryProvider);
  for (var i = 0; i < drafts.length; i += maxEntriesPerSave) {
    final end = (i + maxEntriesPerSave).clamp(0, drafts.length);
    final result = await repository.saveEntries(drafts.sublist(i, end));
    expect(
      result,
      isA<Ok<SavedEntries, TransactionsFailure>>(),
      reason: '${result.failureOrNull}',
    );
  }
}

/// Pumps the app on the sample household with [drafts] saved, on Activity.
Future<ProviderContainer> pumpActivity(
  WidgetTester tester, {
  List<EntryDraft>? drafts,
  TestServices? services,
}) async {
  usePhone(tester);
  final container = await pumpXpenseApp(
    tester,
    services ??
        TestServices(
          accounts: FakeAccountsRepository.sample()..sharingDelay = null,
        ),
  );
  await tester.runAsync(() => seed(container, drafts ?? artboardEntries()));
  container.read(routerProvider).go(AppRoutes.activity);
  await tester.pumpAndSettle();
  return container;
}

/// The overrides of [services] with [feed] as the Activity feed (and the
/// memory write path, not wired to it).
List<Override> overridesWithFeed(TestServices services, ActivityFeed feed) =>
    appOverrides(
      clock: services.clock.clock,
      settings: services.settingsStore,
      biometricLock: services.biometricLock,
      glass: services.glass,
      authRepository: services.auth,
      householdRepository: services.households,
      accountsRepository: services.accounts,
      activityFeed: feed,
      featureFlags: services.flags,
      onDeviceLlm: services.onDeviceLlm,
      speechCapture: services.speech,
    );

/// Pumps the app on the sample household with [feed] as the Activity feed,
/// on Activity, without settling (a feed may never answer).
Future<ProviderContainer> pumpWithFeed(
  WidgetTester tester,
  ActivityFeed feed,
) async {
  usePhone(tester);
  final services = TestServices(
    accounts: FakeAccountsRepository.sample()..sharingDelay = null,
  );
  final container = ProviderContainer.test(
    overrides: overridesWithFeed(services, feed),
    retry: (_, _) => null,
  );
  await tester.pumpWidget(
    UncontrolledProviderScope(container: container, child: const XpenseApp()),
  );
  await tester.pumpAndSettle();
  container.read(routerProvider).go(AppRoutes.activity);
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
  return container;
}

/// The title each shown row reads (its title, else its counterparty).
Set<String> shownTitles(WidgetTester tester) => {
  for (final w in tester.widgetList<ActivityEntryRow>(
    find.byType(ActivityEntryRow),
  ))
    if (w.txn.title.isNotEmpty) w.txn.title else w.txn.personName ?? '',
};

/// The id of the shown row titled [title].
String idOf(WidgetTester tester, String title) => tester
    .widgetList<ActivityEntryRow>(find.byType(ActivityEntryRow))
    .firstWhere((w) => w.txn.title == title || w.txn.personName == title)
    .txn
    .id;
