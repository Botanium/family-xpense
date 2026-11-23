// The whole app over the sample household with an in-memory ledger the
// test can inspect: what Add manually saves and what entry detail reads.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:xpense_app/app.dart';
import 'package:xpense_app/bootstrap.dart';
import 'package:xpense_app/data/accounts_repository.dart';
import 'package:xpense_app/data/accounts_repository_fake.dart';
import 'package:xpense_app/data/read/memory_entry_reader.dart';
import 'package:xpense_app/data/write/ledger_store.dart';
import 'package:xpense_app/data/write/ledger_transactions_repository.dart';
import 'package:xpense_app/data/write/memory_ledger_store.dart';
import 'package:xpense_app/services/settings_store.dart';
import 'package:xpense_shared/xpense_shared.dart';

import '../support/test_app.dart';

/// The sample viewer ("You").
const String viewer = FakeAccountsRepository.sampleViewer;

/// The sample partner ("Sam").
const String partner = FakeAccountsRepository.samplePartner;

/// The app's fakes plus a ledger in memory.
final class LedgerApp {
  /// Creates the fakes. [withRate] stores the household's USD/IQD rate
  /// (1,705) for the whole of November 2026; without it, an IQD entry
  /// needs a typed rate.
  factory({
    bool withRate = true,
    AppearanceMode appearance = AppearanceMode.light,
  }) {
    final services = TestServices(
      accounts: FakeAccountsRepository.sample(),
      settings: AppSettings(appearance: appearance),
    );
    final memory = MemoryLedgerStore(
      scope: const LedgerScope(householdId: 'fake-household', uid: viewer),
      householdInfo: const LedgerHousehold(
        baseCurrency: Currency.usd,
        memberIds: [viewer, partner],
      ),
      clock: services.clock.clock,
    );
    for (final a in FakeAccountsRepository.sampleAccounts) {
      memory.accounts[a.id] = LedgerAccount(
        id: a.id,
        currency: a.currency,
        visibleTo: a.visibleTo,
        joint: a.scope == AccountScope.joint,
        ownerUid: a.ownerUid,
      );
    }
    for (final c in defaultCategories) {
      memory.categories[c.slug] = LedgerCategory(id: c.slug, kind: c.kind.wire);
    }
    if (withRate) {
      memory.rates['2026-11-01'] = DayRate(
        day: '2026-11-01',
        rate: FxRate.forPair(FxPair.usdIqd, '1705').valueOrNull!,
        kind: 'market',
      );
    }
    final store = ObservedLedgerStore(memory);
    return LedgerApp._(
      services,
      memory,
      LedgerTransactionsRepository(store),
      MemoryEntryReader(store),
    );
  }

  new _(this.services, this.memory, this.repository, this.reader);

  /// The other fakes.
  final TestServices services;

  /// The ledger, as the phone sees it.
  final MemoryLedgerStore memory;

  /// The write path.
  final LedgerTransactionsRepository repository;

  /// The read side.
  final MemoryEntryReader reader;

  /// Every stored transaction, oldest first.
  List<Map<String, Object?>> get saved => memory.transactions.values.toList();

  /// A container wired like the app.
  ProviderContainer container() => ProviderContainer.test(
    overrides: appOverrides(
      clock: services.clock.clock,
      settings: services.settingsStore,
      biometricLock: services.biometricLock,
      glass: services.glass,
      authRepository: services.auth,
      householdRepository: services.households,
      accountsRepository: services.accounts,
      transactionsRepository: repository,
      entryReader: reader,
      featureFlags: services.flags,
      onDeviceLlm: services.onDeviceLlm,
      speechCapture: services.speech,
    ),
    retry: (_, _) => null,
  );

  /// Pumps the app on Home and returns its container.
  Future<ProviderContainer> pump(WidgetTester tester) async {
    tester.view
      ..physicalSize = const Size(390, 844) * 3
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final scope = container();
    await tester.pumpWidget(
      UncontrolledProviderScope(container: scope, child: const XpenseApp()),
    );
    await tester.pumpAndSettle();
    return scope;
  }
}

/// Goes to [location] in the running app, as `context.push` would.
Future<void> pushTo(
  WidgetTester tester,
  ProviderContainer container,
  String location, {
  Object? extra,
}) async {
  unawaitedPush(container, location, extra);
  await tester.pumpAndSettle();
}

/// Pushes without waiting for the route's result.
void unawaitedPush(
  ProviderContainer container,
  String location,
  Object? extra,
) {
  // The pushed route's future completes when it pops; tests do not wait
  // for that.
  container.read(routerProvider).push<void>(location, extra: extra).ignore();
}
