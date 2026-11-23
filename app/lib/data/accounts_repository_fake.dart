// An in-memory `AccountsRepository` for tests and the `fakes` environment.
// Only the composition root and tests name this file.
import 'dart:async';

import 'package:clock/clock.dart';
import 'package:xpense_app/data/accounts_repository.dart';
import 'package:xpense_app/data/write/ledger_store.dart';
import 'package:xpense_app/data/write/ledger_transactions_repository.dart';
import 'package:xpense_app/data/write/memory_ledger_store.dart';
import 'package:xpense_shared/xpense_shared.dart';

/// An [AccountsRepository] that keeps one household's accounts in memory.
///
/// It plays the rules: [watchAccounts] returns only what [viewerUid] can
/// see. Sharing bumps the account's visibility rev; the history rewrite
/// then finishes after [sharingDelay] (or at once with [Duration.zero]),
/// or when a test calls [finishSharing] while [sharingDelay] is null.
///
/// With a [ledger] (the `fakes` build), the in-memory write path's store
/// follows this one: the accounts, the members and every rate entered here
/// are written to it, so what the app shows is what a save checks against,
/// as one Firestore household would be.
final class FakeAccountsRepository implements AccountsRepository {
  /// Creates the fake for [viewerUid] in a household of [_members].
  new({
    this.viewerUid = sampleViewer,
    this._members = const [
      HouseholdMember(uid: sampleViewer, displayName: 'You'),
    ],
    List<Account> accounts = const [],
    this.baseCurrency = Currency.usd,
    this._rate,
    this.sharingDelay = Duration.zero,
    this.ledger,
    Clock? clock,
  }) : _clock = clock ?? const Clock() {
    for (final a in accounts) {
      _all[a.id] = a;
    }
    _syncLedger();
  }

  /// The `fakes` environment: the artboards' household ("You" and Sam,
  /// USD, 1,705 dinars per dollar).
  factory sample({
    String viewerUid = sampleViewer,
    MemoryLedgerStore? ledger,
    Clock? clock,
  }) => FakeAccountsRepository(
    viewerUid: viewerUid,
    ledger: ledger,
    clock: clock,
    members: const [
      HouseholdMember(uid: sampleViewer, displayName: 'You'),
      HouseholdMember(uid: samplePartner, displayName: 'Sam'),
    ],
    accounts: sampleAccounts,
    rate: FxRate.forPair(FxPair.usdIqd, '1705').valueOrNull,
    sharingDelay: const Duration(seconds: 3),
  ).._entries['acc-checking'] = _sampleEntries;

  /// The checking account's entries on artboard 11.
  static final List<AccountEntry> _sampleEntries = [
    _entry('t6', 'Salary', 'income', 320000, 21),
    _entry('t5', 'Rent', 'expense', -140000, 20),
    _entry('t4', 'To Summer trip', 'transfer', -22500, 18),
    _entry('t3', 'Electricity', 'expense', -8640, 15),
    _entry('t2', 'Gave Alex', 'loan_given', -30000, 12),
    _entry('t1', 'Pharmacy', 'expense', -2415, 9),
  ];

  static AccountEntry _entry(
    String id,
    String name,
    String type,
    int amountMinor,
    int day,
  ) => AccountEntry(
    id: id,
    title: name,
    type: type,
    amountMinor: amountMinor,
    currency: Currency.usd,
    occurredAt: DateTime(2026, 11, day, 12),
  );

  /// The viewer of the sample household (the fake auth's provider user).
  static const String sampleViewer = 'fake-provider-user';

  /// The partner of the sample household.
  static const String samplePartner = 'fake-partner';

  static const List<String> _both = [sampleViewer, samplePartner];

  /// The artboard accounts (docs/design 10): they sum to the Home balance.
  static const List<Account> sampleAccounts = [
    Account(
      id: 'acc-checking',
      name: 'My checking ••1187',
      kind: AccountKind.bank,
      currency: Currency.usd,
      scope: AccountScope.personal,
      ownerUid: sampleViewer,
      visibleTo: [sampleViewer],
      balanceMinor: 394000,
    ),
    Account(
      id: 'acc-sam-checking',
      name: "Sam's checking ••5530",
      kind: AccountKind.bank,
      currency: Currency.usd,
      scope: AccountScope.personal,
      ownerUid: samplePartner,
      sharedWithPartner: true,
      visibleTo: _both,
      balanceMinor: 261500,
      order: 1,
    ),
    Account(
      id: 'acc-visa',
      name: 'Joint Visa ••4021',
      kind: AccountKind.credit,
      currency: Currency.usd,
      scope: AccountScope.joint,
      visibleTo: _both,
      balanceMinor: -61200,
      order: 2,
    ),
    Account(
      id: 'acc-cash',
      name: 'Cash (IQD)',
      kind: AccountKind.cash,
      currency: Currency.iqd,
      scope: AccountScope.personal,
      ownerUid: sampleViewer,
      sharedWithPartner: true,
      visibleTo: _both,
      balanceMinor: 315425,
      order: 3,
    ),
    Account(
      id: 'acc-emergency',
      name: 'Emergency fund',
      kind: AccountKind.savings,
      currency: Currency.usd,
      scope: AccountScope.joint,
      visibleTo: _both,
      balanceMinor: 520000,
      order: 4,
    ),
    Account(
      id: 'acc-trip',
      name: 'Summer trip',
      kind: AccountKind.savings,
      currency: Currency.usd,
      scope: AccountScope.joint,
      visibleTo: _both,
      balanceMinor: 115200,
      order: 5,
    ),
    Account(
      id: 'acc-sam-private',
      name: "Sam's savings",
      kind: AccountKind.savings,
      currency: Currency.usd,
      scope: AccountScope.personal,
      ownerUid: samplePartner,
      visibleTo: [samplePartner],
      balanceMinor: 900000,
      order: 6,
    ),
  ];

  @override
  final String viewerUid;

  /// The household base currency.
  final Currency baseCurrency;

  /// How long the server's history rewrite takes; null waits for
  /// [finishSharing].
  Duration? sharingDelay;

  /// The write path's store this one keeps in step, in the `fakes` build.
  final MemoryLedgerStore? ledger;

  final Clock _clock;
  final Map<String, Account> _all = {};
  List<HouseholdMember> _members;
  FxRate? _rate;
  final Map<String, List<AccountEntry>> _entries = {};
  final _changes = StreamController<void>.broadcast(sync: true);
  var _nextId = 0;

  /// When set, the next write fails with it (then it clears).
  AccountsFailure? nextFailure;

  /// Every call made, by name, in order.
  final List<String> calls = [];

  /// The drafts [create] received.
  final List<AccountDraft> created = [];

  /// Every account, including ones the viewer cannot see.
  List<Account> get allAccounts => _sorted(_all.values);

  /// Replaces the rate, as a member answering the rate prompt would: it
  /// is today's rate in the [ledger] too.
  void setRate(FxRate? rate) {
    _putRate(rate);
    _changed();
  }

  void _putRate(FxRate? rate) {
    _rate = rate;
    if (ledger case final store? when rate != null) {
      final day = householdDay(_clock.now());
      store.rates[day] = DayRate(day: day, rate: rate, kind: 'market');
    }
  }

  void _changed() {
    _syncLedger();
    _changes.add(null);
  }

  // The accounts and members as the write path checks them.
  void _syncLedger() {
    final store = ledger;
    if (store == null) return;
    for (final a in _all.values) {
      store.accounts[a.id] = LedgerAccount(
        id: a.id,
        currency: a.currency,
        visibleTo: a.visibleTo,
        joint: a.scope == AccountScope.joint,
        ownerUid: a.ownerUid,
      );
    }
    store.householdInfo = LedgerHousehold(
      baseCurrency: baseCurrency,
      memberIds: [for (final m in _members) m.uid],
    );
  }

  /// The rates saved through [setDailyRate], in order.
  final List<FxRate> dailyRates = [];

  @override
  Future<Result<void, AccountsFailure>> setDailyRate(FxRate rate) async {
    dailyRates.add(rate);
    setRate(rate);
    return const Ok(null);
  }

  /// Replaces the members, as a partner joining would.
  void setMembers(List<HouseholdMember> members) {
    _members = members;
    _changed();
  }

  /// Puts [account] in the store, as the partner's phone would.
  void put(Account account) {
    _all[account.id] = account;
    _changed();
  }

  /// Finishes the history rewrite of account [id], as the server does.
  void finishSharing(String id) {
    final a = _all[id];
    if (a == null) return;
    _all[id] = _copy(a, appliedVisibleTo: a.visibleTo);
    _changed();
  }

  /// Sets the entries shown for account [id].
  void setEntries(String id, List<AccountEntry> entries) {
    _entries[id] = entries;
    _changed();
  }

  List<Account> _visible() => [
    for (final a in _sorted(_all.values))
      if (a.visibleTo.contains(viewerUid)) a,
  ];

  static List<Account> _sorted(Iterable<Account> accounts) =>
      accounts.toList()..sort((a, b) => a.order.compareTo(b.order));

  Stream<T> _watch<T>(T Function() read) async* {
    yield read();
    yield* _changes.stream.map((_) => read());
  }

  @override
  Stream<List<Account>> watchAccounts() => _watch(_visible);

  @override
  Stream<List<HouseholdMember>> watchMembers() => _watch(() {
    final mine = _all.values.any(
      (a) => a.isOwnedBy(viewerUid) && a.isPrivate && !a.archived,
    );
    return [
      for (final m in _members)
        HouseholdMember(
          uid: m.uid,
          displayName: m.displayName,
          hasPrivateAccounts: m.uid == viewerUid
              ? mine
              : _all.values.any(
                  (a) => a.isOwnedBy(m.uid) && a.isPrivate && !a.archived,
                ),
        ),
    ];
  });

  @override
  Stream<FxRate?> watchLatestRate() => _watch(() => _rate);

  @override
  Stream<List<AccountEntry>> watchEntries(String accountId) => _watch(
    () => _all[accountId]?.visibleTo.contains(viewerUid) ?? false
        ? _entries[accountId] ?? const []
        : const [],
  );

  Result<T, AccountsFailure>? _fail<T>(String call) {
    calls.add(call);
    final failure = nextFailure;
    if (failure == null) return null;
    nextFailure = null;
    return Err(failure);
  }

  @override
  Future<Result<String, AccountsFailure>> create(AccountDraft draft) async {
    final failed = _fail<String>('create');
    if (failed != null) return failed;
    final opening = draft.openingBalanceMinor;
    final needed = openingBaseAmount(
      amountMinor: opening,
      currency: draft.currency,
      base: baseCurrency,
      rate: draft.openingRate ?? _rate,
    );
    if (needed == null) return const Err(AccountsRateNeeded());
    if (opening != 0 && draft.openingRate != null) _putRate(draft.openingRate);
    created.add(draft);
    final id = 'acc-new-${_nextId++}';
    final ownerUid = draft.scope == AccountScope.personal ? viewerUid : null;
    final shared =
        draft.scope == AccountScope.personal && draft.sharedWithPartner;
    _all[id] = Account(
      id: id,
      name: draft.name,
      kind: draft.kind,
      currency: draft.currency,
      scope: draft.scope,
      ownerUid: ownerUid,
      sharedWithPartner: shared,
      visibleTo: accountVisibleTo(
        scope: draft.scope,
        ownerUid: ownerUid,
        sharedWithPartner: shared,
        memberIds: [for (final m in _members) m.uid],
      ),
      balanceMinor: opening,
      order: _all.values.fold(-1, (m, a) => a.order > m ? a.order : m) + 1,
    );
    if (opening != 0) {
      _entries[id] = [
        AccountEntry(
          id: 'txn-$id',
          title: '',
          type: 'adjustment',
          amountMinor: opening,
          currency: draft.currency,
          occurredAt: _clock.now(),
        ),
      ];
    }
    _changed();
    return Ok(id);
  }

  @override
  Future<Result<void, AccountsFailure>> edit(
    String id, {
    required String name,
    required AccountKind kind,
  }) async {
    final failed = _fail<void>('edit');
    if (failed != null) return failed;
    final a = _all[id];
    if (a == null || !a.visibleTo.contains(viewerUid)) {
      return const Err(AccountNotFound());
    }
    _all[id] = _copy(a, name: name, kind: kind);
    _changed();
    return const Ok(null);
  }

  @override
  Future<Result<void, AccountsFailure>> setArchived(
    String id, {
    required bool archived,
  }) async {
    final failed = _fail<void>('setArchived');
    if (failed != null) return failed;
    final a = _all[id];
    if (a == null || !a.visibleTo.contains(viewerUid)) {
      return const Err(AccountNotFound());
    }
    _all[id] = _copy(a, archived: archived);
    _changed();
    return const Ok(null);
  }

  @override
  Future<Result<void, AccountsFailure>> setShared(
    String id, {
    required bool shared,
  }) async {
    final failed = _fail<void>('setShared');
    if (failed != null) return failed;
    final a = _all[id];
    if (a == null || !a.isOwnedBy(viewerUid)) {
      return const Err(AccountNotFound());
    }
    if (a.sharedWithPartner == shared) return const Ok(null);
    _all[id] = _copy(
      a,
      sharedWithPartner: shared,
      visibleTo: accountVisibleTo(
        scope: a.scope,
        ownerUid: a.ownerUid,
        sharedWithPartner: shared,
        memberIds: [for (final m in _members) m.uid],
      ),
      appliedVisibleTo: a.appliedVisibleTo ?? a.visibleTo,
    );
    _changed();
    final delay = sharingDelay;
    if (delay == Duration.zero) {
      finishSharing(id);
    } else if (delay != null) {
      // The `fakes` build plays the server's progress line.
      final total = _entries[id]?.length ?? 42;
      _all[id] = _copy(_all[id]!, sharingDone: 0, sharingTotal: total);
      _changed();
      Timer(delay ~/ 2, () {
        final now = _all[id];
        if (now == null || !now.sharingInProgress) return;
        _all[id] = _copy(now, sharingDone: total ~/ 2, sharingTotal: total);
        _changed();
      });
      Timer(delay, () => finishSharing(id));
    }
    return const Ok(null);
  }

  /// Closes the change stream.
  Future<void> dispose() => _changes.close();
}

Account _copy(
  Account a, {
  String? name,
  AccountKind? kind,
  bool? archived,
  bool? sharedWithPartner,
  List<String>? visibleTo,
  List<String>? appliedVisibleTo,
  int? sharingDone,
  int? sharingTotal,
}) {
  final next = Account(
    id: a.id,
    name: a.name,
    kind: a.kind,
    currency: a.currency,
    scope: a.scope,
    visibleTo: visibleTo ?? a.visibleTo,
    appliedVisibleTo: appliedVisibleTo ?? a.appliedVisibleTo,
  );
  final running = next.sharingInProgress;
  return Account(
    id: a.id,
    name: name ?? a.name,
    kind: kind ?? a.kind,
    currency: a.currency,
    scope: a.scope,
    ownerUid: a.ownerUid,
    sharedWithPartner: sharedWithPartner ?? a.sharedWithPartner,
    visibleTo: visibleTo ?? a.visibleTo,
    balanceMinor: a.balanceMinor,
    archived: archived ?? a.archived,
    order: a.order,
    appliedVisibleTo: next.appliedVisibleTo,
    sharingDone: running ? sharingDone ?? a.sharingDone : null,
    sharingTotal: running ? sharingTotal ?? a.sharingTotal : null,
  );
}
