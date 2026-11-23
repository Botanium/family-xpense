// An in-memory `LedgerStore` for the fakes build and tests. It keeps a
// "server" copy and, while [MemoryLedgerStore.online] is false, a queue of
// pending batches shown on top of it, as Firestore's cache does. Going
// online replays the queue against the server copy with the rules' checks
// that matter to the write path (`rev` advances by one, a new entry does
// not exist yet, the writer can see the accounts).
import 'dart:math';

import 'package:clock/clock.dart';
import 'package:xpense_app/data/mappers/transaction_mapper.dart';
import 'package:xpense_app/data/transactions_repository.dart';
import 'package:xpense_app/data/write/ledger_store.dart';
import 'package:xpense_shared/xpense_shared.dart';

/// [LedgerStore] in memory.
final class MemoryLedgerStore implements LedgerStore {
  /// Creates an empty household for [scope].
  new({
    required this.scope,
    required this.householdInfo,
    Clock? clock,
    Random? random,
  }) : _clock = clock ?? const Clock(),
       _random = random ?? Random();

  @override
  LedgerScope? scope;

  /// The household; null reads as "not in a household".
  LedgerHousehold? householdInfo;

  final Clock _clock;
  final Random _random;

  /// Accounts by id, as the writer sees them (visibility is checked on
  /// commit against [LedgerAccount.visibleTo]).
  final Map<String, LedgerAccount> accounts = {};

  /// Categories by id.
  final Map<String, LedgerCategory> categories = {};

  /// Loans by id.
  final Map<String, LedgerLoan> loans = {};

  /// Person ids.
  final Set<String> people = {};

  /// Goal id → its savings account id.
  final Map<String, String> goals = {};

  /// The household's rates by day.
  final Map<String, DayRate> rates = {};

  /// Whether commits reach the "server" at once. Set it with [goOnline].
  bool get online => _online;
  bool _online = true;

  /// A failure the next commit returns instead of writing.
  StoreFailure? failNextCommit;

  /// Batches committed to the server copy so far.
  int committedBatches = 0;

  final _State _server = _State();
  final List<_Pending> _pending = [];

  // ---------------------------------------------------------------- reads

  /// Every transaction's stored fields, as the phone sees them (pending
  /// writes included).
  Map<String, Map<String, Object?>> get transactions => _view().txns;

  /// The server copy of every transaction.
  Map<String, Map<String, Object?>> get serverTransactions =>
      Map.unmodifiable(_server.txns);

  /// Revisions by transaction id, as the phone sees them.
  Map<String, List<Map<String, Object?>>> get revisions => _view().revisions;

  /// Each account's `balanceMinor`, as the phone sees it.
  Map<String, int> get balances => _view().balances;

  /// Each account's `balanceMinor` on the server.
  Map<String, int> get serverBalances => Map.unmodifiable(_server.balances);

  /// Each loan's `outstandingMinor`, as the phone sees it.
  Map<String, int> get outstanding => _view().outstanding;

  /// Batches waiting for [goOnline].
  int get pendingBatches => _pending.length;

  @override
  DateTime now() => _clock.now();

  @override
  String newId() => uuidV7(_clock.now(), _random);

  @override
  Future<LedgerHousehold?> household() async => householdInfo;

  @override
  Future<LedgerAccount?> account(String id) async {
    final a = accounts[id];
    final uid = scope?.uid;
    return a != null && uid != null && a.visibleTo.contains(uid) ? a : null;
  }

  @override
  Future<LedgerCategory?> category(String id) async => categories[id];

  @override
  Future<LedgerLoan?> loan(String id) async => loans[id];

  @override
  Future<bool> hasPerson(String id) async => people.contains(id);

  @override
  Future<String?> goalAccount(String id) async => goals[id];

  @override
  Future<DayRate?> rateOn(String day) async {
    final days = rates.keys.where((d) => d.compareTo(day) <= 0).toList()
      ..sort();
    return days.isEmpty ? null : rates[days.last];
  }

  @override
  Future<LedgerTransaction?> transaction(
    String id, {
    bool fresh = false,
  }) async {
    final state = fresh && _online ? _server : _view();
    final data = state.txns[id];
    final uid = scope?.uid;
    if (data == null || uid == null) return null;
    final txn = transactionFromFields(id, data);
    return txn != null && txn.visibleTo.contains(uid) ? txn : null;
  }

  // -------------------------------------------------------------- writes

  @override
  Future<Result<WriteAck, StoreFailure>> commit(
    LedgerPlan plan, {
    void Function(StoreFailure failure)? onLateFailure,
  }) async {
    final injected = failNextCommit;
    if (injected != null) {
      failNextCommit = null;
      return Err(injected);
    }
    final uid = scope?.uid;
    if (uid == null) return const Err(StoreFailure(StoreFailureKind.denied));
    if (!_online) {
      _pending.add(_Pending(plan, uid, onLateFailure));
      return const Ok(WriteAck.queued);
    }
    final refused = _check(_server, plan, uid);
    if (refused != null) return Err(refused);
    _apply(_server, plan, uid, _clock.now());
    committedBatches++;
    return const Ok(WriteAck.synced);
  }

  /// Goes offline, or back online; going online replays the queue against
  /// the server copy in order. A refused batch is dropped (Firestore rolls
  /// it back on the phone) and its late-failure callback is called.
  void goOnline({required bool online}) {
    _online = online;
    if (!online) return;
    final queued = [..._pending];
    _pending.clear();
    for (final p in queued) {
      final refused = _check(_server, p.plan, p.uid);
      if (refused != null) {
        p.onLateFailure?.call(refused);
        continue;
      }
      _apply(_server, p.plan, p.uid, _clock.now());
      committedBatches++;
    }
  }

  /// Writes [fields] over transaction [id] on the server, advancing `rev`,
  /// as the partner's phone would.
  void remoteEdit(String id, Map<String, Object?> fields) {
    final doc = _server.txns[id]!;
    _server.txns[id] = {...doc, ...fields, 'rev': (doc['rev']! as int) + 1};
  }

  /// Sets account [id]'s balance on the server, as a drifted aggregate.
  void setServerBalance(String id, int balanceMinor) =>
      _server.balances[id] = balanceMinor;

  // ------------------------------------------------------------- helpers

  _State _view() {
    if (_pending.isEmpty) return _server;
    final view = _server.copy();
    final at = _clock.now();
    for (final p in _pending) {
      _apply(view, p.plan, p.uid, at);
    }
    return view;
  }

  StoreFailure? _check(_State state, LedgerPlan plan, String uid) {
    const denied = StoreFailure(StoreFailureKind.denied, 'permission-denied');
    final txns = {...state.txns};
    for (final write in plan.writes) {
      switch (write) {
        case TxnCreate(:final id, :final fields):
          if (txns.containsKey(id)) return denied;
          if (!_canSee(fields['accountId'], uid)) return denied;
          if (fields['toAccountId'] != null &&
              !_canSee(fields['toAccountId'], uid)) {
            return denied;
          }
          txns[id] = fields;
        case TxnUpdate(:final id, :final fields, :final rev):
          final doc = txns[id];
          if (doc == null || doc['rev'] != rev - 1) return denied;
          txns[id] = {...doc, ...fields};
        case RevisionCreate():
          break;
      }
    }
    for (final id in plan.effects.accounts.keys) {
      if (!_canSee(id, uid)) return denied;
    }
    for (final id in plan.effects.loans.keys) {
      if (!loans.containsKey(id)) return denied;
    }
    return null;
  }

  bool _canSee(Object? accountId, String uid) =>
      accounts[accountId]?.visibleTo.contains(uid) ?? false;

  static void _apply(_State state, LedgerPlan plan, String uid, DateTime at) {
    for (final write in plan.writes) {
      switch (write) {
        case TxnCreate(:final id, :final fields):
          state.txns[id] = _resolveTimes(fields, at);
        case TxnUpdate(:final id, :final fields):
          state.txns[id] = {...?state.txns[id], ..._resolveTimes(fields, at)};
        case RevisionCreate(:final txnId, :final id, :final fields):
          (state.revisions[txnId] ??= []).add({
            'id': id,
            ..._resolveTimes(fields, at),
          });
      }
    }
    plan.effects.accounts.forEach(
      (id, delta) => state.balances[id] = (state.balances[id] ?? 0) + delta,
    );
    plan.effects.loans.forEach(
      (id, delta) =>
          state.outstanding[id] = (state.outstanding[id] ?? 0) + delta,
    );
  }

  static Map<String, Object?> _resolveTimes(
    Map<String, Object?> fields,
    DateTime at,
  ) => {
    for (final e in fields.entries)
      e.key: switch (e.value) {
        ServerTime() => at.toUtc(),
        final Map<String, Object?> m => _resolveTimes(m, at),
        final v => v,
      },
  };
}

final class _State {
  final Map<String, Map<String, Object?>> txns = {};
  final Map<String, List<Map<String, Object?>>> revisions = {};
  final Map<String, int> balances = {};
  final Map<String, int> outstanding = {};

  _State copy() => _State()
    ..txns.addAll(txns)
    ..revisions.addAll({
      for (final e in revisions.entries) e.key: [...e.value],
    })
    ..balances.addAll(balances)
    ..outstanding.addAll(outstanding);
}

final class _Pending {
  const new(this.plan, this.uid, this.onLateFailure);

  final LedgerPlan plan;
  final String uid;
  final void Function(StoreFailure failure)? onLateFailure;
}
