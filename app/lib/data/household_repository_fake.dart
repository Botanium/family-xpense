// An in-memory `HouseholdRepository` for tests and the `fakes` environment.
// Only the composition root and tests name this file.
import 'dart:async';

import 'package:xpense_app/data/auth_repository.dart';
import 'package:xpense_app/data/household_repository.dart';
import 'package:xpense_shared/xpense_shared.dart';

/// A [HouseholdRepository] that keeps one household in memory.
///
/// [create] makes the household at once; [createInvite] hands out
/// [inviteCode]; [join] accepts [inviteCode] (in any case, with or without
/// the dash) and joins [partnerHousehold]. Tests steer it with
/// [nextFailure] or [failNext], hold calls open with [hold] or [holdNext]
/// and read [calls].
///
/// Given an `auth` repository it follows sign-in like the real adapter:
/// signing out makes the membership unknown, and signing in while it is
/// unknown sets [onSignIn].
final class FakeHouseholdRepository implements HouseholdRepository {
  /// Creates the fake in `membership` (unknown by default, as signed out).
  new({
    this._membership = const MembershipUnknown(),
    AuthRepository? auth,
    this.onSignIn = const NoHousehold(),
  }) {
    _authSubscription = auth?.authStateChanges().listen(_onUser);
  }

  /// The membership a sign-in leads to: [NoHousehold] for someone new.
  Membership onSignIn;

  StreamSubscription<AuthUser?>? _authSubscription;

  void _onUser(AuthUser? user) {
    if (user == null) {
      setMembership(const MembershipUnknown());
    } else if (_membership is MembershipUnknown) {
      setMembership(onSignIn);
    }
  }

  /// A household with the person in it, as the `fakes` environment starts.
  static const HouseholdSummary sampleHousehold = HouseholdSummary(
    id: 'fake-household',
    name: 'Our home',
    baseCurrency: Currency.usd,
    memberCount: 1,
    myDisplayName: 'You',
  );

  /// The household [join] joins.
  static const JoinedHousehold partnerHousehold = JoinedHousehold(
    id: 'fake-partner-household',
    name: "Sam's home",
  );

  /// The code [createInvite] returns and [join] accepts.
  static const String inviteCode = 'AB3DE7GH9K';

  Membership _membership;
  final StreamController<Membership> _changes =
      StreamController<Membership>.broadcast(sync: true);

  /// When set, the next call fails with it (then it clears).
  HouseholdFailure? nextFailure;

  /// When set, every call waits for it before answering, so a test can see
  /// the loading state.
  Completer<void>? hold;

  /// Per call name (`create`, `createInvite`, `join`): fail the next such
  /// call with this failure (then it is removed).
  final Map<String, HouseholdFailure> failNext = {};

  /// Per call name: the next such call waits for this (then it is removed).
  final Map<String, Completer<void>> holdNext = {};

  /// Every call made, by name, in order.
  final List<String> calls = [];

  /// The arguments of the last [create].
  ({String name, String displayName, Currency baseCurrency})? lastCreate;

  /// The arguments of the last [join].
  ({String code, String displayName})? lastJoin;

  @override
  Membership get current => _membership;

  /// Sets the membership, as signing in or out, or the partner joining,
  /// would.
  void setMembership(Membership value) {
    _membership = value;
    if (!_changes.isClosed) _changes.add(value);
  }

  @override
  Stream<Membership> watchMembership() async* {
    yield _membership;
    yield* _changes.stream;
  }

  @override
  Future<Result<String, HouseholdFailure>> create({
    required String name,
    required String displayName,
    required Currency baseCurrency,
  }) => _answer('create', () {
    lastCreate = (
      name: name,
      displayName: displayName,
      baseCurrency: baseCurrency,
    );
    const id = 'fake-new-household';
    setMembership(
      InHousehold(
        HouseholdSummary(
          id: id,
          name: name,
          baseCurrency: baseCurrency,
          memberCount: 1,
          myDisplayName: displayName,
        ),
      ),
    );
    return const Ok(id);
  });

  @override
  Future<Result<HouseholdInvite, HouseholdFailure>> createInvite() =>
      _answer('createInvite', () {
        if (_membership is! InHousehold) {
          return const Err(HouseholdNotAllowed());
        }
        return Ok(
          HouseholdInvite(
            code: inviteCode,
            link: 'xpense://join?code=$inviteCode',
            expiresAt: DateTime.utc(2026, 11, 29, 9),
          ),
        );
      });

  @override
  Future<Result<JoinedHousehold, HouseholdFailure>> join({
    required String code,
    required String displayName,
  }) => _answer('join', () {
    lastJoin = (code: code, displayName: displayName);
    final typed = code.replaceAll(RegExp(r'[\s-]'), '').toUpperCase();
    if (typed != inviteCode) return const Err(InviteInvalid());
    setMembership(
      InHousehold(
        HouseholdSummary(
          id: partnerHousehold.id,
          name: partnerHousehold.name,
          baseCurrency: Currency.usd,
          memberCount: 2,
          myDisplayName: displayName,
        ),
      ),
    );
    return const Ok(partnerHousehold);
  });

  /// Stops following sign-in and closes the change stream.
  Future<void> dispose() async {
    await _authSubscription?.cancel();
    await _changes.close();
  }

  Future<Result<T, HouseholdFailure>> _answer<T>(
    String name,
    Result<T, HouseholdFailure> Function() outcome,
  ) async {
    calls.add(name);
    await hold?.future;
    await holdNext.remove(name)?.future;
    final named = failNext.remove(name);
    final failure = named ?? nextFailure;
    if (failure != null) {
      if (named == null) nextFailure = null;
      return Err(failure);
    }
    return outcome();
  }
}
