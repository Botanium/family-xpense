import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:xpense_app/a2ui/xpense_surface_host.dart';
import 'package:xpense_app/data/accounts_repository.dart';
import 'package:xpense_app/data/household_repository.dart';
import 'package:xpense_shared/xpense_shared.dart';

/// The household the Ask cards and the parser use, from the same sources
/// as the rest of the app: the membership (base currency), the accounts
/// repository (accounts, members, latest rate; Firestore in dev and prod,
/// the fakes in `fakes`), and the default categories, which every
/// household is created with until it can edit them. The save path reads
/// the same accounts, so the ids on a card are ones it can save.
///
/// People, loans and goals have no store yet; their lists stay empty.
final askHouseholdProvider = Provider<XpenseHousehold>(
  (ref) => xpenseHouseholdFrom(
    membership: ref.watch(membershipProvider).value,
    accounts: ref.watch(accountsProvider).value ?? const [],
    members: ref.watch(householdMembersProvider).value ?? const [],
    viewerUid: ref.watch(accountsRepositoryProvider).viewerUid,
    latestRate: ref.watch(latestRateProvider).value,
  ),
  name: 'askHouseholdProvider',
);

/// Builds the Ask household from the app's household data.
XpenseHousehold xpenseHouseholdFrom({
  required Membership? membership,
  required List<Account> accounts,
  required List<HouseholdMember> members,
  required String? viewerUid,
  required FxRate? latestRate,
}) => XpenseHousehold(
  baseCurrency: switch (membership) {
    InHousehold(:final household) => household.baseCurrency.code,
    _ => Currency.usd.code,
  },
  accounts: [
    for (final a in accounts)
      if (!a.archived)
        HouseholdAccount(id: a.id, name: a.name, currency: a.currency.code),
  ],
  categories: [
    for (final c in defaultCategories)
      HouseholdCategory(id: c.slug, name: c.nameIn('en')),
  ],
  partnerName: members
      .where((m) => m.uid != viewerUid)
      .map((m) => m.displayName)
      .firstOrNull,
  latestRate: latestRate?.pair == FxPair.usdIqd ? latestRate?.rateString : null,
);
