import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:xpense_app/data/accounts_repository.dart';
import 'package:xpense_app/data/household_repository.dart';
import 'package:xpense_app/data/read/home_reader.dart';
import 'package:xpense_app/data/transactions_repository.dart';
import 'package:xpense_app/features/home/home_summary.dart';
import 'package:xpense_app/services/clock.dart';

/// The month Home shows: the one of today, by the injected clock.
///
/// It moves on by itself at local midnight, and [HomeMonthNotifier.refresh]
/// reads the clock again when the app resumes and on pull to refresh, so a
/// Home left open overnight or in the background shows the new day (and,
/// on the 1st, the new month) rather than yesterday's (Codex review,
/// PR #37).
final NotifierProvider<HomeMonthNotifier, HomeMonth> homeMonthProvider =
    NotifierProvider<HomeMonthNotifier, HomeMonth>(
      HomeMonthNotifier.new,
      name: 'homeMonthProvider',
    );

/// Holds [homeMonthProvider]'s month and rolls it over.
class HomeMonthNotifier extends Notifier<HomeMonth> {
  Timer? _midnight;

  @override
  HomeMonth build() {
    ref.onDispose(() => _midnight?.cancel());
    return _read();
  }

  /// Reads the clock again; changes the month (or the day) only if it moved.
  void refresh() {
    final next = _read();
    if (next != state) state = next;
  }

  HomeMonth _read() {
    final now = ref.read(clockProvider).now();
    _midnight?.cancel();
    final nextDay = DateTime(now.year, now.month, now.day + 1);
    // Fires at local midnight. Should it fire a moment early, the day has
    // not changed, nothing is emitted and the next timer is set again.
    _midnight = Timer(nextDay.difference(now), refresh);
    return HomeMonth.of(now);
  }
}

/// This month's entries the viewer can read, from the 1st to today.
final StreamProvider<List<LedgerTransaction>> homeMonthTransactionsProvider =
    StreamProvider.autoDispose<List<LedgerTransaction>>((ref) {
      final month = ref.watch(homeMonthProvider);
      return ref
          .watch(homeReaderProvider)
          .watchRange(fromDay: month.firstDay, toDay: month.today);
    }, name: 'homeMonthTransactionsProvider');

/// The latest entries the viewer can read, for Recent.
final StreamProvider<List<LedgerTransaction>> homeRecentTransactionsProvider =
    StreamProvider.autoDispose<List<LedgerTransaction>>(
      (ref) =>
          ref.watch(homeReaderProvider).watchRecent(limit: homeRecentCount),
      name: 'homeRecentTransactionsProvider',
    );

/// Home's figures, once accounts, members, the month and Recent have
/// loaded. Derived each time any of them changes; never stored.
final Provider<AsyncValue<HomeSummary>> homeSummaryProvider =
    Provider.autoDispose<AsyncValue<HomeSummary>>((ref) {
      final monthTxns = ref.watch(homeMonthTransactionsProvider);
      final recentTxns = ref.watch(homeRecentTransactionsProvider);
      final accounts = ref.watch(accountsProvider);
      final members = ref.watch(householdMembersProvider);
      final rate = ref.watch(latestRateProvider);
      final membership = ref.watch(membershipProvider).value;
      final viewer = ref.watch(accountsRepositoryProvider).viewerUid;
      for (final value in [monthTxns, recentTxns, accounts, members]) {
        if (value.hasError) return AsyncError(value.error!, value.stackTrace!);
      }
      final month = monthTxns.value;
      final recent = recentTxns.value;
      final accountList = accounts.value;
      final people = members.value;
      if (month == null ||
          recent == null ||
          accountList == null ||
          people == null ||
          membership is! InHousehold ||
          viewer == null) {
        return const AsyncLoading();
      }
      return AsyncData(
        buildHomeSummary(
          monthTransactions: month,
          recentTransactions: recent,
          accounts: accountList,
          members: people,
          viewerUid: viewer,
          baseCurrency: membership.household.baseCurrency,
          month: ref.watch(homeMonthProvider),
          rate: rate.value,
        ),
      );
    }, name: 'homeSummaryProvider');

/// What the nudge row on Home says (DESIGN_SYSTEM 8.2 `NudgeRow`).
enum HomeNudge {
  /// "Spent something? Just say it." with Ask: the placeholder until the
  /// nudge jobs (WP-60) and the daily rate prompt (WP-24) fill the slot.
  tryAsk,
}

/// The nudge row's content, or null to hide the row. Static for now: the
/// daily rate prompt (WP-24) and server nudges (WP-60) replace it.
final homeNudgeProvider = Provider<HomeNudge?>(
  (ref) => HomeNudge.tryAsk,
  name: 'homeNudgeProvider',
);
