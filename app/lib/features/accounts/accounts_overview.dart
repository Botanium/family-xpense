import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:xpense_app/data/accounts_repository.dart';
import 'package:xpense_app/data/fx_repository.dart';
import 'package:xpense_app/data/household_repository.dart';
import 'package:xpense_shared/xpense_shared.dart';

/// The filter bar on Accounts (DESIGN_SYSTEM 9, screen 10).
enum AccountsFilter {
  /// Every account the viewer can see.
  all,

  /// The viewer's own personal accounts.
  mine,

  /// The partner's personal accounts they share.
  partner,

  /// Joint accounts.
  joint,
}

/// Whose an account is, for its meta line ("You", "Sam, shared", "Joint").
enum AccountOwner {
  /// The viewer's, private.
  mine,

  /// The viewer's, shared with the partner.
  mineShared,

  /// The partner's (shared, or the viewer could not see it).
  partner,

  /// Both members'.
  joint,
}

/// One row of the Accounts list.
@immutable
final class AccountRow {
  /// Creates a row.
  const new({required this.account, required this.owner, this.baseMinor});

  /// The account.
  final Account account;

  /// Whose it is.
  final AccountOwner owner;

  /// The balance in the base currency when the account is in another
  /// currency and a rate is known; null otherwise.
  final int? baseMinor;

  @override
  bool operator ==(Object other) =>
      other is AccountRow &&
      other.account == account &&
      other.owner == owner &&
      other.baseMinor == baseMinor;

  @override
  int get hashCode => Object.hash(account, owner, baseMinor);
}

/// The Accounts screen's figures, derived from the repository's streams.
@immutable
final class AccountsOverview {
  /// Creates an overview.
  const new({
    required this.baseCurrency,
    required this.rows,
    required this.totalMinor,
    required this.complete,
    required this.unconverted,
    required this.hasPartner,
    this.partnerName,
  });

  /// The household base currency.
  final Currency baseCurrency;

  /// Every visible, unarchived account, in list order.
  final List<AccountRow> rows;

  /// Sum of the visible, unarchived accounts in [baseCurrency].
  final int totalMinor;

  /// Whether the viewer sees every account in the household: the label is
  /// then "Household balance", otherwise "Your view" (DATA_MODEL 4).
  final bool complete;

  /// Currencies left out of [totalMinor] for want of a rate.
  final Set<Currency> unconverted;

  /// Whether the household has a second member.
  final bool hasPartner;

  /// The partner's name, for the filter bar and meta lines.
  final String? partnerName;

  /// The rows [filter] keeps.
  List<AccountRow> filtered(AccountsFilter filter) => [
    for (final row in rows)
      if (switch (filter) {
        AccountsFilter.all => true,
        AccountsFilter.mine =>
          row.owner == AccountOwner.mine ||
              row.owner == AccountOwner.mineShared,
        AccountsFilter.partner => row.owner == AccountOwner.partner,
        AccountsFilter.joint => row.owner == AccountOwner.joint,
      })
        row,
  ];

  @override
  bool operator ==(Object other) =>
      other is AccountsOverview &&
      other.baseCurrency == baseCurrency &&
      listEquals(other.rows, rows) &&
      other.totalMinor == totalMinor &&
      other.complete == complete &&
      setEquals(other.unconverted, unconverted) &&
      other.hasPartner == hasPartner &&
      other.partnerName == partnerName;

  @override
  int get hashCode => Object.hash(
    baseCurrency,
    Object.hashAll(rows),
    totalMinor,
    complete,
    Object.hashAll(unconverted),
    hasPartner,
    partnerName,
  );
}

/// Whose [account] is, seen by [viewerUid].
AccountOwner ownerOf(Account account, String viewerUid) =>
    switch (account.scope) {
      AccountScope.joint => AccountOwner.joint,
      AccountScope.personal when account.ownerUid == viewerUid =>
        account.sharedWithPartner ? AccountOwner.mineShared : AccountOwner.mine,
      AccountScope.personal => AccountOwner.partner,
    };

/// Builds the overview. Pure, so it is tested without widgets.
///
/// Only [accounts] the viewer can read reach here (the repository's queries
/// carry the visibleTo filter), so the total holds nothing of a partner's
/// private account. [members] tell whether anything is hidden: a partner
/// with private accounts makes the view incomplete.
AccountsOverview buildOverview({
  required List<Account> accounts,
  required List<HouseholdMember> members,
  required String viewerUid,
  required Currency baseCurrency,
  FxRate? rate,
}) {
  final rows = <AccountRow>[];
  var total = 0;
  final unconverted = <Currency>{};
  for (final account in accounts) {
    if (account.archived) continue;
    int? baseMinor;
    if (account.currency == baseCurrency) {
      total += account.balanceMinor;
    } else {
      final converted = rate?.convert(account.balance, baseCurrency);
      baseMinor = converted?.valueOrNull?.minorUnits;
      if (baseMinor == null) {
        unconverted.add(account.currency);
      } else {
        total += baseMinor;
      }
    }
    rows.add(
      AccountRow(
        account: account,
        owner: ownerOf(account, viewerUid),
        baseMinor: baseMinor,
      ),
    );
  }
  final partner = members.where((m) => m.uid != viewerUid).firstOrNull;
  return AccountsOverview(
    baseCurrency: baseCurrency,
    rows: rows,
    totalMinor: total,
    complete: !members.any((m) => m.uid != viewerUid && m.hasPrivateAccounts),
    unconverted: unconverted,
    hasPartner: partner != null,
    partnerName: partner == null || partner.displayName.isEmpty
        ? null
        : partner.displayName,
  );
}

/// The household's base currency, or null when not in a household.
final baseCurrencyProvider = Provider<Currency?>((ref) {
  final membership = ref.watch(membershipProvider).value;
  return membership is InHousehold ? membership.household.baseCurrency : null;
}, name: 'baseCurrencyProvider');

/// The Accounts overview, once accounts, members and the rate have loaded.
final accountsOverviewProvider = Provider<AsyncValue<AccountsOverview>>((ref) {
  final accounts = ref.watch(accountsProvider);
  final members = ref.watch(householdMembersProvider);
  final rate = ref.watch(latestRateProvider);
  final base = ref.watch(baseCurrencyProvider);
  final viewer = ref.watch(accountsRepositoryProvider).viewerUid;
  if (accounts.hasError) {
    return AsyncError(accounts.error!, accounts.stackTrace!);
  }
  final list = accounts.value;
  final people = members.value;
  if (list == null || people == null || base == null || viewer == null) {
    return const AsyncLoading();
  }
  return AsyncData(
    buildOverview(
      accounts: list,
      members: people,
      viewerUid: viewer,
      baseCurrency: base,
      rate: rate.value,
    ),
  );
}, name: 'accountsOverviewProvider');
