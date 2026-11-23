/// A [HouseholdReader] over in-memory data: unit tests, and local runs of
/// the agent without the Firestore emulator (`XPENSE_AGENT_DATA=demo`).
///
/// It applies the same `visibleTo` rules as the Firestore reader, so tests
/// of the privacy model run against it.
library;

import 'package:xpense_agent/tools/household_reader.dart';

/// A document with its readers.
typedef Visible<T> = ({T item, List<String> visibleTo});

/// One household held in memory.
final class InMemoryHousehold {
  /// Creates a household.
  new({
    required this.profile,
    this.members = const [],
    this.accounts = const [],
    this.categories = const [],
    this.people = const [],
    this.loans = const [],
    this.budgets = const [],
    this.transactions = const [],
    this.fxRates = const [],
  });

  /// `households/{hid}`.
  final HouseholdProfile profile;

  /// Members.
  final List<HouseholdMember> members;

  /// Accounts with `visibleTo`.
  final List<Visible<HouseholdAccount>> accounts;

  /// Categories.
  final List<HouseholdCategory> categories;

  /// People with `visibleTo`.
  final List<Visible<HouseholdPerson>> people;

  /// Loans with `visibleTo`.
  final List<Visible<HouseholdLoan>> loans;

  /// Budgets with `visibleTo`.
  final List<Visible<HouseholdBudget>> budgets;

  /// Transactions with `visibleTo` (soft-deleted ones are not held).
  final List<Visible<LedgerTxn>> transactions;

  /// Daily rates.
  final List<FxDay> fxRates;
}

/// Reads [InMemoryHousehold]s by id.
final class InMemoryHouseholdReader implements HouseholdReader {
  /// Creates a reader over [households]. [maxRangeTransactions] stands in
  /// for the Firestore reader's cap (tests set it low).
  new(
    this.households, {
    this.maxRangeTransactions = HouseholdReader.maxRangeTransactions,
  });

  /// The most transactions one read returns.
  final int maxRangeTransactions;

  /// The data, by household id.
  final Map<String, InMemoryHousehold> households;

  /// Every call, as `operation:hid`, for tests.
  final calls = <String>[];

  /// Operations that throw [HouseholdUnavailable], for tests.
  final failing = <String>{};

  InMemoryHousehold? _h(String op, String hid) {
    calls.add('$op:$hid');
    if (failing.contains(op)) throw HouseholdUnavailable(op);
    return households[hid];
  }

  List<T> _visible<T>(List<Visible<T>>? items, String uid) => [
    for (final v in items ?? <Visible<T>>[])
      if (v.visibleTo.contains(uid)) v.item,
  ];

  @override
  Future<HouseholdProfile?> profile(String hid) async =>
      _h('profile', hid)?.profile;

  @override
  Future<List<HouseholdMember>> members(String hid) async =>
      _h('members', hid)?.members ?? const [];

  @override
  Future<List<HouseholdAccount>> accounts(
    String hid, {
    required String uid,
  }) async => _visible(_h('accounts', hid)?.accounts, uid);

  @override
  Future<List<HouseholdCategory>> categories(String hid) async =>
      _h('categories', hid)?.categories ?? const [];

  @override
  Future<List<HouseholdPerson>> people(
    String hid, {
    required String uid,
  }) async => _visible(_h('people', hid)?.people, uid);

  @override
  Future<List<HouseholdLoan>> loans(String hid, {required String uid}) async =>
      _visible(_h('loans', hid)?.loans, uid);

  @override
  Future<List<HouseholdBudget>> budgets(
    String hid, {
    required String uid,
  }) async => _visible(_h('budgets', hid)?.budgets, uid);

  @override
  Future<TxnRead> transactions(
    String hid, {
    required String uid,
    required String fromOn,
    required String toOn,
  }) async {
    final all = _visible(_h('transactions', hid)?.transactions, uid);
    final inRange = [
      for (final t in all)
        if (t.occurredOn.compareTo(fromOn) >= 0 &&
            t.occurredOn.compareTo(toOn) <= 0)
          t,
    ]..sort((a, b) => b.occurredOn.compareTo(a.occurredOn));
    if (inRange.length > maxRangeTransactions) {
      return TxnRead(
        inRange.take(maxRangeTransactions).toList(),
        complete: false,
      );
    }
    return TxnRead(inRange);
  }

  @override
  Future<bool> hasHiddenAccounts(String hid, {required String uid}) async => [
    for (final a
        in _h('hiddenAccounts', hid)?.accounts ?? <Visible<HouseholdAccount>>[])
      if (!a.item.archived && !a.visibleTo.contains(uid)) a,
  ].isNotEmpty;

  @override
  Future<FxDay?> fxRateOn(String hid, String date) async {
    final rates = [
      for (final r in _h('fxRates', hid)?.fxRates ?? const <FxDay>[])
        if (r.date.compareTo(date) <= 0) r,
    ]..sort((a, b) => b.date.compareTo(a.date));
    return rates.firstOrNull;
  }
}
