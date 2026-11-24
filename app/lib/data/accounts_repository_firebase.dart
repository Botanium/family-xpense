// The Firestore adapter behind `AccountsRepository` (DATA_MODEL 2.4, 2.5,
// 2.13, 3, 4). Only the composition root names this file.
import 'dart:async';
import 'dart:math';

import 'package:clock/clock.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import 'package:xpense_app/data/accounts_repository.dart';
import 'package:xpense_app/data/fx_repository.dart';
import 'package:xpense_app/data/fx_repository_firebase.dart';
import 'package:xpense_app/data/household_repository.dart';
import 'package:xpense_app/data/transactions_repository.dart';
import 'package:xpense_app/data/write/firestore_ledger_store.dart';
import 'package:xpense_app/data/write/ledger_store.dart';
import 'package:xpense_app/data/write/ledger_transactions_repository.dart';
import 'package:xpense_shared/xpense_shared.dart';

/// [AccountsRepository] over Firestore.
///
/// It follows the household membership: while the person is in a
/// household, one listener keeps the accounts they can see; the other
/// streams start their own listeners per subscriber.
final class FirebaseAccountsRepository implements AccountsRepository {
  /// Creates the adapter. [households] says which household is current;
  /// [_firestore] must already point at the emulator when one is used
  /// (the household adapter does that).
  new({
    required this._auth,
    required this._firestore,
    required HouseholdRepository households,
    Clock? clock,
    Random? random,
    TransactionsRepository? ledger,
    this.entriesLimit = defaultEntriesLimit,
  }) : _households = households,
       _ledgerOverride = ledger,
       _clock = clock ?? const Clock(),
       _random = random ?? Random.secure() {
    _membershipSubscription = households.watchMembership().listen(
      _onMembership,
    );
  }

  /// The adapter on [FirebaseFirestore.instance] and [FirebaseAuth.instance].
  factory connect({required HouseholdRepository households}) =>
      FirebaseAccountsRepository(
        auth: FirebaseAuth.instance,
        firestore: FirebaseFirestore.instance,
        households: households,
      );

  /// How long a write waits for Firestore before it counts as queued
  /// offline.
  static const Duration writeAckTimeout = Duration(seconds: 8);

  /// Entries shown on an account's detail screen by default.
  static const int defaultEntriesLimit = 50;

  /// Entries shown on an account's detail screen.
  final int entriesLimit;

  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;
  final HouseholdRepository _households;
  final Clock _clock;
  final Random _random;
  final TransactionsRepository? _ledgerOverride;

  /// The transaction write path (WP-20), which writes opening balances.
  late final TransactionsRepository _ledger =
      _ledgerOverride ??
      LedgerTransactionsRepository(
        FirestoreLedgerStore(
          firestore: _firestore,
          scope: () {
            final hid = _hid;
            final uid = _uid;
            return hid == null || uid == null
                ? null
                : LedgerScope(householdId: hid, uid: uid);
          },
          clock: _clock,
          random: _random,
        ),
      );

  late final StreamSubscription<Membership> _membershipSubscription;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _accountsSub;
  String? _hid;
  String? _uid;
  List<Account> _accounts = const [];
  final StreamController<List<Account>> _accountChanges =
      StreamController<List<Account>>.broadcast();
  final StreamController<void> _scopeChanges =
      StreamController<void>.broadcast();

  @override
  String? get viewerUid => _hid == null ? null : _uid;

  /// Stops listening.
  Future<void> dispose() async {
    await _membershipSubscription.cancel();
    await _accountsSub?.cancel();
    await _accountChanges.close();
    await _scopeChanges.close();
  }

  // ----------------------------------------------------------- following

  void _onMembership(Membership membership) {
    final hid = membership is InHousehold ? membership.household.id : null;
    final uid = hid == null ? null : _auth.currentUser?.uid;
    if (hid == _hid && uid == _uid) return;
    unawaited(_accountsSub?.cancel());
    _accountsSub = null;
    _hid = hid;
    _uid = uid;
    _setAccounts(const []);
    if (!_scopeChanges.isClosed) _scopeChanges.add(null);
    if (hid == null || uid == null) return;
    _listenAccounts(hid, uid, 0);
  }

  void _listenAccounts(String hid, String uid, int attempt) {
    _accountsSub = _visible(_collection(hid, 'accounts'), uid)
        .orderBy('order')
        .snapshots()
        .listen(
          (snapshot) {
            if (hid != _hid) return;
            _setAccounts([
              for (final doc in snapshot.docs)
                ?accountFromFirestore(doc.id, doc.data()),
            ]);
          },
          onError: (Object e, StackTrace s) {
            if (_retryLater(e, attempt, () {
              if (hid == _hid && uid == _uid) {
                _listenAccounts(hid, uid, attempt + 1);
              }
            })) {
              return;
            }
            _report(e, s, 'accounts');
          },
        );
  }

  /// How many times a refused listener is started again.
  static const int listenRetries = 6;

  /// The first wait before starting a refused listener again; it doubles.
  static const Duration listenRetryDelay = Duration(milliseconds: 500);

  /// A listener started right after this phone founded or joined the
  /// household is refused until the server has the membership (the
  /// household repository's founding batch shows locally first; WP-12
  /// handover). Schedules [again] with backoff and returns true when [error]
  /// is such a refusal and retries are left.
  bool _retryLater(Object error, int attempt, void Function() again) {
    if (error is! FirebaseException || error.code != 'permission-denied') {
      return false;
    }
    if (attempt >= listenRetries) return false;
    Timer(listenRetryDelay * (1 << attempt), again);
    return true;
  }

  void _setAccounts(List<Account> accounts) {
    if (listEquals(accounts, _accounts)) return;
    _accounts = accounts;
    if (!_accountChanges.isClosed) _accountChanges.add(accounts);
  }

  @override
  Stream<List<Account>> watchAccounts() async* {
    yield _accounts;
    yield* _accountChanges.stream;
  }

  /// A stream rebuilt from [build] whenever the household or the person
  /// changes; [empty] while not in a household.
  Stream<T> _scoped<T>(
    T empty,
    Stream<T> Function(String hid, String uid) build,
  ) {
    late final StreamController<T> controller;
    StreamSubscription<T>? inner;
    StreamSubscription<void>? scope;
    var generation = 0;
    void restart([int attempt = 0]) {
      unawaited(inner?.cancel());
      inner = null;
      final hid = _hid;
      final uid = _uid;
      if (hid == null || uid == null) {
        controller.add(empty);
        return;
      }
      final mine = generation;
      inner = build(hid, uid).listen(
        controller.add,
        onError: (Object e, StackTrace s) {
          if (_retryLater(e, attempt, () {
            if (mine == generation && !controller.isClosed) {
              restart(attempt + 1);
            }
          })) {
            return;
          }
          _report(e, s, 'a list');
        },
      );
    }

    controller = StreamController<T>(
      onListen: () {
        scope = _scopeChanges.stream.listen((_) {
          generation++;
          restart();
        });
        restart();
      },
      onCancel: () async {
        generation++;
        await scope?.cancel();
        await inner?.cancel();
      },
    );
    return controller.stream;
  }

  @override
  Stream<List<HouseholdMember>> watchMembers() => _scoped(
    const [],
    (hid, _) => _collection(hid, 'members').snapshots().map(
      (snapshot) => [
        for (final doc in snapshot.docs)
          HouseholdMember(
            uid: doc.id,
            displayName: switch (doc.data()['displayName']) {
              final String name => name,
              _ => '',
            },
            hasPrivateAccounts: doc.data()['hasPrivateAccounts'] == true,
          ),
      ],
    ),
  );

  @override
  Stream<List<AccountEntry>> watchEntries(String accountId) =>
      _scoped(const [], (hid, uid) {
        // Entries that leave the account and transfers that arrive in it:
        // two queries, both with the visibleTo filter, merged here.
        final transactions = _visible(_collection(hid, 'transactions'), uid);
        Stream<List<QueryDocumentSnapshot<Map<String, dynamic>>>> side(
          String field,
        ) => transactions
            .where(field, isEqualTo: accountId)
            // Deleted entries are left out by the query, before the limit,
            // so they never use up the page (Codex review, PR #33). Every
            // write path stores `deletedAt: null` on a live entry.
            .where('deletedAt', isNull: true)
            .orderBy('occurredAt', descending: true)
            .limit(entriesLimit)
            .snapshots()
            .map((s) => s.docs);
        return _combine(side('accountId'), side('toAccountId')).map((both) {
          final currency = _accounts
              .where((a) => a.id == accountId)
              .map((a) => a.currency)
              .firstOrNull;
          final entries = <AccountEntry>[
            for (final doc in {
              for (final d in [...both.$1, ...both.$2]) d.id: d,
            }.values)
              ?entryFromFirestore(
                doc.id,
                doc.data(),
                accountId,
                currency: currency,
              ),
          ]..sort((a, b) => b.occurredAt.compareTo(a.occurredAt));
          return entries.take(entriesLimit).toList();
        });
      });

  // -------------------------------------------------------------- writes

  @override
  Future<Result<String, AccountsFailure>> create(AccountDraft draft) async {
    final hid = _hid;
    final uid = _uid;
    final membership = _households.current;
    if (hid == null || uid == null || membership is! InHousehold) {
      return const Err(AccountsNotAllowed());
    }
    final base = membership.household.baseCurrency;
    final opening = draft.openingBalanceMinor;

    // The base amount of the opening entry is fixed now, so a missing rate
    // stops the whole add before anything is written. No opening entry, no
    // conversion (Codex review, PR #33).
    FxRate? rate;
    if (opening != 0 && draft.currency != base) {
      rate = draft.openingRate ?? await _latestRate(hid);
    }
    final baseAmountMinor = openingBaseAmount(
      amountMinor: opening,
      currency: draft.currency,
      base: base,
      rate: rate,
    );
    if (baseAmountMinor == null) return const Err(AccountsRateNeeded());

    try {
      final household = await _collectionDoc(hid).get();
      final memberIds = _strings(household.data()?['memberIds']);
      final rateKind = switch (household.data()?['rateKind']) {
        'official' => 'official',
        _ => 'market',
      };
      final id = uuidV7(_clock.now(), _random);
      final accountRef = _collection(hid, 'accounts').doc(id);
      final ownerUid = draft.scope == AccountScope.personal ? uid : null;
      final shared =
          draft.scope == AccountScope.personal && draft.sharedWithPartner;
      final visibleTo = accountVisibleTo(
        scope: draft.scope,
        ownerUid: ownerUid,
        sharedWithPartner: shared,
        memberIds: memberIds,
      );
      final account = Account(
        id: id,
        name: draft.name,
        kind: draft.kind,
        currency: draft.currency,
        scope: draft.scope,
        ownerUid: ownerUid,
        sharedWithPartner: shared,
        visibleTo: visibleTo,
      );
      final order = _accounts.fold(-1, (m, a) => max(m, a.order)) + 1;

      // First write: the account (balance 0), the private-accounts flag and
      // a typed rate as today's. The opening entry is a second write,
      // because the rules check the entry against the account as it was
      // before the batch.
      final today = householdDay(_clock.now());
      final typedRate = draft.openingRate;
      final first = _firestore.batch()
        ..set(accountRef, {
          'name': draft.name,
          'kind': draft.kind.wire,
          'currency': draft.currency.code,
          'scope': draft.scope.wire,
          'ownerUid': ownerUid,
          'sharedWithPartner': shared,
          'visibleTo': visibleTo,
          'balanceMinor': 0,
          'balanceCheckedAt': null,
          'archived': false,
          'order': order,
          // No history yet: it already matches (the rules allow only this).
          'visibilityAppliedTo': visibleTo,
          ..._createStamps(uid),
        });
      if (opening != 0 && typedRate != null) {
        first.set(_collection(hid, 'fxRates').doc(today), {
          'usdIqd': typedRate.rateString,
          'kind': rateKind,
          'enteredBy': uid,
          'enteredAt': FieldValue.serverTimestamp(),
        });
      }
      _flagPrivate(first, hid, uid, [..._accounts, account]);
      await _commit(first, 'adding an account');

      if (opening != 0) {
        // The opening balance is an `adjustment` saved through the
        // transaction write path (WP-20).
        const draftId = 'opening';
        final saved = await _ledger.saveEntries(
          [
            EntryDraft(
              id: draftId,
              intent: CaptureIntent.adjustment.wire,
              amountMinor: opening.abs(),
              currency: draft.currency.code,
              accountId: id,
              occurredOn: today,
              fx: typedRate == null
                  ? null
                  : FxQuote(
                      pair: typedRate.pair.code,
                      pairRate: typedRate.rateString,
                      source: 'manual',
                      asOf: today,
                    ),
            ),
          ],
          source: EntrySource.manual,
          extras: {draftId: EntryExtras(adjustmentSign: opening < 0 ? -1 : 1)},
        );
        if (saved case Err(:final failure)) {
          return Err(switch (failure) {
            EntryRateNeeded() => const AccountsRateNeeded(),
            TransactionsNotAllowed() => const AccountsNotAllowed(),
            _ => AccountsUnknown(failure.code),
          });
        }
      }
      return Ok(id);
    } on FirebaseException catch (e, s) {
      return Err(_failure(e, s, 'adding an account'));
    }
  }

  @override
  Future<Result<void, AccountsFailure>> edit(
    String id, {
    required String name,
    required AccountKind kind,
  }) => _update(id, 'editing an account', (account, batch, ref, uid) {
    batch.update(ref, {'name': name, 'kind': kind.wire, ..._updateStamps(uid)});
  });

  @override
  Future<Result<void, AccountsFailure>> setArchived(
    String id, {
    required bool archived,
  }) => _update(id, 'archiving an account', (account, batch, ref, uid) {
    batch.update(ref, {'archived': archived, ..._updateStamps(uid)});
    _flagPrivate(batch, _hid!, uid, [
      for (final a in _accounts)
        _with(a, archived: a.id == id ? archived : null),
    ]);
  });

  @override
  Future<Result<void, AccountsFailure>> setShared(
    String id, {
    required bool shared,
  }) async {
    final hid = _hid;
    if (hid == null) return const Err(AccountsNotAllowed());
    final List<String> memberIds;
    try {
      memberIds = _strings(
        (await _collectionDoc(hid).get()).data()?['memberIds'],
      );
    } on FirebaseException catch (e, s) {
      return Err(_failure(e, s, 'reading the household'));
    }
    return await _update(id, 'sharing an account', (account, batch, ref, uid) {
      if (!account.isOwnedBy(uid)) throw const _Refused();
      if (account.sharedWithPartner == shared) return;
      final visibleTo = accountVisibleTo(
        scope: account.scope,
        ownerUid: account.ownerUid,
        sharedWithPartner: shared,
        memberIds: memberIds,
      );
      batch.update(ref, {
        'sharedWithPartner': shared,
        'visibleTo': visibleTo,
        // The server's history rewrite follows (`/events/account-visibility`
        // compares visibleTo with the server-only visibilityAppliedTo).
        ..._updateStamps(uid),
      });
      _flagPrivate(batch, hid, uid, [
        for (final a in _accounts)
          _with(a, sharedWithPartner: a.id == id ? shared : null),
      ]);
    });
  }

  Future<Result<void, AccountsFailure>> _update(
    String id,
    String what,
    void Function(
      Account account,
      WriteBatch batch,
      DocumentReference<Map<String, dynamic>> ref,
      String uid,
    )
    build,
  ) async {
    final hid = _hid;
    final uid = _uid;
    if (hid == null || uid == null) return const Err(AccountsNotAllowed());
    final account = _accounts.where((a) => a.id == id).firstOrNull;
    if (account == null) return const Err(AccountNotFound());
    final batch = _firestore.batch();
    try {
      build(account, batch, _collection(hid, 'accounts').doc(id), uid);
    } on _Refused {
      return const Err(AccountNotFound());
    }
    try {
      await _commit(batch, what);
      return const Ok(null);
    } on FirebaseException catch (e, s) {
      return Err(_failure(e, s, what));
    }
  }

  /// Keeps `members/{uid}.hasPrivateAccounts` in step with [accounts], the
  /// member's accounts after the write.
  void _flagPrivate(
    WriteBatch batch,
    String hid,
    String uid,
    List<Account> accounts,
  ) {
    final private = accounts.any(
      (a) => a.isOwnedBy(uid) && a.isPrivate && !a.archived,
    );
    batch.update(_collection(hid, 'members').doc(uid), {
      'hasPrivateAccounts': private,
    });
  }

  /// Commits [batch], waiting [writeAckTimeout] for Firestore; offline the
  /// batch stays queued on the phone and shows from the cache at once.
  Future<void> _commit(WriteBatch batch, String what) async {
    final commit = batch.commit();
    try {
      await commit.timeout(writeAckTimeout);
    } on TimeoutException {
      unawaited(
        commit.then<void>(
          (_) {},
          onError: (Object e, StackTrace s) => _report(e, s, what),
        ),
      );
    }
  }

  /// The newest rate of the last [latestRateWindow], for an opening
  /// balance in the other currency.
  Future<FxRate?> _latestRate(String hid) async {
    try {
      final snapshot = await ratesSince(
        _collection(hid, 'fxRates'),
        localDay(_clock.now().subtract(latestRateWindow)),
      ).get();
      for (final doc in snapshot.docs.reversed) {
        if (dailyRateFromFirestore(doc.id, doc.data()) case final r?) {
          return r.rate;
        }
      }
      return null;
    } on FirebaseException {
      return null;
    }
  }

  // ------------------------------------------------------------- helpers

  DocumentReference<Map<String, dynamic>> _collectionDoc(String hid) =>
      _firestore.collection('households').doc(hid);

  CollectionReference<Map<String, dynamic>> _collection(
    String hid,
    String name,
  ) => _collectionDoc(hid).collection(name);

  /// Every privacy-scoped list query goes through here (DATA_MODEL 4).
  static Query<Map<String, dynamic>> _visible(
    Query<Map<String, dynamic>> query,
    String uid,
  ) => query.where('visibleTo', arrayContains: uid);

  static Map<String, Object?> _createStamps(String uid) => {
    'createdAt': FieldValue.serverTimestamp(),
    'createdBy': uid,
    'updatedAt': FieldValue.serverTimestamp(),
    'updatedBy': uid,
    'schemaVersion': 1,
  };

  static Map<String, Object?> _updateStamps(String uid) => {
    'updatedAt': FieldValue.serverTimestamp(),
    'updatedBy': uid,
  };

  static AccountsFailure _failure(
    FirebaseException error,
    StackTrace stack,
    String what,
  ) {
    _report(error, stack, what);
    return switch (error.code) {
      'permission-denied' || 'unauthenticated' => const AccountsNotAllowed(),
      'not-found' => const AccountNotFound(),
      _ => AccountsUnknown(error.code),
    };
  }

  static void _report(Object error, StackTrace stack, String what) =>
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stack,
          library: 'accounts_repository',
          context: ErrorDescription('while $what'),
        ),
      );
}

final class _Refused implements Exception {
  const new();
}

Account _with(Account a, {bool? archived, bool? sharedWithPartner}) => Account(
  id: a.id,
  name: a.name,
  kind: a.kind,
  currency: a.currency,
  scope: a.scope,
  ownerUid: a.ownerUid,
  sharedWithPartner: sharedWithPartner ?? a.sharedWithPartner,
  visibleTo: a.visibleTo,
  balanceMinor: a.balanceMinor,
  archived: archived ?? a.archived,
  order: a.order,
  appliedVisibleTo: a.appliedVisibleTo,
);

List<String> _strings(Object? value) =>
    value is List ? value.whereType<String>().toList() : <String>[];

/// Both streams' latest values, once each has emitted.
Stream<(A, B)> _combine<A, B>(Stream<A> a, Stream<B> b) {
  late final StreamController<(A, B)> controller;
  StreamSubscription<A>? subA;
  StreamSubscription<B>? subB;
  A? lastA;
  B? lastB;
  var hasA = false;
  var hasB = false;
  void emit() {
    if (hasA && hasB) controller.add((lastA as A, lastB as B));
  }

  controller = StreamController<(A, B)>(
    onListen: () {
      subA = a.listen((v) {
        lastA = v;
        hasA = true;
        emit();
      }, onError: controller.addError);
      subB = b.listen((v) {
        lastB = v;
        hasB = true;
        emit();
      }, onError: controller.addError);
    },
    onCancel: () async {
      await subA?.cancel();
      await subB?.cancel();
    },
  );
  return controller.stream;
}

/// The local calendar date of [time] as `YYYY-MM-DD` (DATA_MODEL 1). The
/// phone's zone stands in for the household's until WP-20 resolves it.
@visibleForTesting
String localDay(DateTime time) {
  final t = time.toLocal();
  String two(int v) => v.toString().padLeft(2, '0');
  return '${t.year}-${two(t.month)}-${two(t.day)}';
}

/// Reads a stored account, or null when it is malformed.
@visibleForTesting
Account? accountFromFirestore(String id, Map<String, dynamic> data) {
  final currency = Currency.tryParse('${data['currency']}');
  if (currency == null) return null;
  final sync = data['visibilitySync'];
  int? syncInt(String key) =>
      sync is Map && sync[key] is int ? sync[key] as int : null;
  int intOf(String key) => switch (data[key]) {
    final int v => v,
    _ => 0,
  };
  return Account(
    id: id,
    name: switch (data['name']) {
      final String name => name,
      _ => '',
    },
    kind: AccountKind.fromWire(data['kind']),
    currency: currency,
    scope: AccountScope.fromWire(data['scope']),
    ownerUid: switch (data['ownerUid']) {
      final String uid => uid,
      _ => null,
    },
    sharedWithPartner: data['sharedWithPartner'] == true,
    visibleTo: _strings(data['visibleTo']),
    balanceMinor: intOf('balanceMinor'),
    archived: data['archived'] == true,
    order: intOf('order'),
    appliedVisibleTo: data['visibilityAppliedTo'] is List
        ? _strings(data['visibilityAppliedTo'])
        : null,
    sharingDone: syncInt('done'),
    sharingTotal: syncInt('total'),
  );
}

/// Reads a stored transaction as an entry on account [accountId]
/// ([entryFromFields], with its `Timestamp` read as a time).
@visibleForTesting
AccountEntry? entryFromFirestore(
  String id,
  Map<String, dynamic> data,
  String accountId, {
  Currency? currency,
}) => entryFromFields(
  id,
  {
    ...data,
    'occurredAt': switch (data['occurredAt']) {
      final Timestamp t => t.toDate(),
      _ => null,
    },
  },
  accountId,
  currency: currency,
);
