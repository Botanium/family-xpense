// The household the signed-in person belongs to, and how they get one
// (PRD ON-3, ON-4; BACKLOG S1.4, S1.5).
//
// This file is the interface features import. The Firebase adapter is
// `household_repository_firebase.dart` and the fake is
// `household_repository_fake.dart`; only the composition root and tests
// name them.
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:xpense_shared/xpense_shared.dart';

/// The household as its members see it (DATA_MODEL 2.2).
@immutable
final class HouseholdSummary {
  /// Creates a summary.
  const new({
    required this.id,
    required this.name,
    required this.baseCurrency,
    required this.memberCount,
    this.myDisplayName,
  });

  /// The household id.
  final String id;

  /// The household's name, such as "Our home".
  final String name;

  /// The base currency, set at creation.
  final Currency baseCurrency;

  /// How many people are in it: 1 until the partner joins, at most 2.
  final int memberCount;

  /// The name the signed-in person chose for themself, when known.
  final String? myDisplayName;

  @override
  bool operator ==(Object other) =>
      other is HouseholdSummary &&
      other.id == id &&
      other.name == name &&
      other.baseCurrency == baseCurrency &&
      other.memberCount == memberCount &&
      other.myDisplayName == myDisplayName;

  @override
  int get hashCode =>
      Object.hash(id, name, baseCurrency, memberCount, myDisplayName);

  // No names: this lands in logs.
  @override
  String toString() => 'HouseholdSummary($id, members: $memberCount)';
}

/// Where the signed-in person stands with households.
@immutable
sealed class Membership {
  const new();
}

/// Not known yet: signed out, or the first read has not answered.
final class MembershipUnknown extends Membership {
  /// Creates the state.
  const new();

  @override
  bool operator ==(Object other) => other is MembershipUnknown;

  @override
  int get hashCode => (MembershipUnknown).hashCode;
}

/// Signed in, in no household: household setup or joining comes next.
final class NoHousehold extends Membership {
  /// Creates the state.
  const new();

  @override
  bool operator ==(Object other) => other is NoHousehold;

  @override
  int get hashCode => (NoHousehold).hashCode;
}

/// A member of [household].
final class InHousehold extends Membership {
  /// Creates the state.
  const new(this.household);

  /// The household.
  final HouseholdSummary household;

  @override
  bool operator ==(Object other) =>
      other is InHousehold && other.household == household;

  @override
  int get hashCode => Object.hash(InHousehold, household);
}

/// An invite for the partner (D-27): shown once, valid 7 days, single use.
@immutable
final class HouseholdInvite {
  /// Creates an invite.
  const new({required this.code, required this.link, required this.expiresAt});

  /// Characters in a code.
  static const int codeLength = 10;

  /// The 10-character code, without separators.
  final String code;

  /// `xpense://join?code=…`.
  final String link;

  /// When the invite stops working.
  final DateTime expiresAt;

  /// The code as people read it: two groups of five, `ABCDE-FGHJK`.
  String get displayCode => formatInviteCode(code);

  @override
  bool operator ==(Object other) =>
      other is HouseholdInvite &&
      other.code == code &&
      other.link == link &&
      other.expiresAt == expiresAt;

  @override
  int get hashCode => Object.hash(code, link, expiresAt);

  // No code: this lands in logs.
  @override
  String toString() => 'HouseholdInvite(expires: $expiresAt)';
}

/// [code] in two groups of five, as the invite screen shows it. A code of
/// another length is returned as it is.
String formatInviteCode(String code) =>
    code.length == HouseholdInvite.codeLength
    ? '${code.substring(0, 5)}-${code.substring(5)}'
    : code;

/// The household someone just joined.
@immutable
final class JoinedHousehold {
  /// Creates the result.
  const new({required this.id, required this.name});

  /// The household id.
  final String id;

  /// Its name, for the welcome line.
  final String name;

  @override
  bool operator ==(Object other) =>
      other is JoinedHousehold && other.id == id && other.name == name;

  @override
  int get hashCode => Object.hash(id, name);

  @override
  String toString() => 'JoinedHousehold($id)';
}

/// Why creating a household, an invite or a join did not work. A failure
/// carries a stable [code], never a user-facing string; the screen picks
/// the words from the ARB file.
@immutable
sealed class HouseholdFailure implements Failure {
  const new();

  // Field-less failures are equal when they are the same case.
  @override
  bool operator ==(Object other) => other.runtimeType == runtimeType;

  @override
  int get hashCode => runtimeType.hashCode;

  @override
  String toString() => code;
}

/// No connection to Firestore or the server.
final class HouseholdOffline extends HouseholdFailure {
  /// Creates the failure.
  const new();

  @override
  String get code => 'household.offline';
}

/// No invite has this code: mistyped, never issued, or replaced by a newer
/// one. The server does not say which.
final class InviteInvalid extends HouseholdFailure {
  /// Creates the failure.
  const new();

  @override
  String get code => 'household.invite_invalid';
}

/// The invite is more than 7 days old.
final class InviteExpired extends HouseholdFailure {
  /// Creates the failure.
  const new();

  @override
  String get code => 'household.invite_expired';
}

/// Someone already joined with this invite.
final class InviteUsed extends HouseholdFailure {
  /// Creates the failure.
  const new();

  @override
  String get code => 'household.invite_used';
}

/// The household already has two members.
final class HouseholdFull extends HouseholdFailure {
  /// Creates the failure.
  const new();

  @override
  String get code => 'household.full';
}

/// The person already belongs to another household (one per person in v1).
final class AlreadyInHousehold extends HouseholdFailure {
  /// Creates the failure.
  const new();

  @override
  String get code => 'household.already_in_household';
}

/// Too many invites or join attempts in the last hour.
final class HouseholdRateLimited extends HouseholdFailure {
  /// Creates the failure.
  const new();

  @override
  String get code => 'household.rate_limited';
}

/// The server or Firestore refused this person: signed out, App Check
/// failed, not a member, or a rule said no.
final class HouseholdNotAllowed extends HouseholdFailure {
  /// Creates the failure.
  const new();

  @override
  String get code => 'household.not_allowed';
}

/// The server cannot be reached from this build (no server address set) or
/// answered that it is unavailable. Safe to retry later.
final class HouseholdServiceUnavailable extends HouseholdFailure {
  /// Creates the failure.
  const new();

  @override
  String get code => 'household.unavailable';
}

/// Anything else. The original error is reported where it was caught.
final class HouseholdUnknown extends HouseholdFailure {
  /// Creates the failure with a short machine-readable [detail].
  const new(this.detail);

  /// The server's message or the exception type. Never shown to the user.
  final String detail;

  @override
  String get code => 'household.unknown';

  @override
  bool operator ==(Object other) =>
      other is HouseholdUnknown && other.detail == detail;

  @override
  int get hashCode => Object.hash(HouseholdUnknown, detail);

  @override
  String toString() => '$code($detail)';
}

/// Maps the server's error message (the `message` of its error body, a
/// stable code; server `HouseholdFailure` and `AuthFailure`) to a
/// [HouseholdFailure]. Total: an unknown code gives [HouseholdUnknown].
///
/// Pure and here, not in the adapter, so it is tested without a server.
HouseholdFailure householdFailureFromServerCode(String code) => switch (code) {
  'invite_invalid' => const InviteInvalid(),
  'invite_expired' => const InviteExpired(),
  'invite_used' => const InviteUsed(),
  'household_full' => const HouseholdFull(),
  'already_in_household' => const AlreadyInHousehold(),
  'rate_limited' => const HouseholdRateLimited(),
  'household_unavailable' ||
  'auth_unavailable' => const HouseholdServiceUnavailable(),
  'missing_id_token' ||
  'invalid_id_token' ||
  'missing_app_check' ||
  'invalid_app_check' ||
  'no_household' ||
  'not_member' => const HouseholdNotAllowed(),
  _ => HouseholdUnknown(code),
};

/// Longest household or display name the app accepts, in characters. The
/// server holds display names to the same limit.
const int maxHouseholdNameLength = 40;

/// Creates a household, invites the partner and joins one.
///
/// The household and its first member are written from the phone in one
/// batch the rules check (S1.4). Invites and joins change who is a member,
/// which only the server may do, so they go through
/// `/v1/household/invite` and `/v1/household/join` (S1.5, D-19).
///
/// Every call returns a [Result] and never throws for an expected failure.
/// Screens never navigate on a membership change themselves; the router's
/// onboarding gate reads [current] and [watchMembership].
abstract interface class HouseholdRepository {
  /// Where the signed-in person stands now: [MembershipUnknown] while
  /// signed out or before the first read answers.
  Membership get current;

  /// Emits [current] now and on every change.
  Stream<Membership> watchMembership();

  /// Creates a household named [name] in [baseCurrency] with the signed-in
  /// person as its owner, called [displayName], and seeds the default
  /// categories, all in one batch. Returns the new household's id.
  ///
  /// Offline, the batch waits on the phone and the household appears at
  /// once; this returns as soon as the write is queued.
  Future<Result<String, HouseholdFailure>> create({
    required String name,
    required String displayName,
    required Currency baseCurrency,
  });

  /// Asks the server for a new invite to the person's household. A new
  /// invite replaces the unused earlier one.
  Future<Result<HouseholdInvite, HouseholdFailure>> createInvite();

  /// Joins the household of the invite [code] as [displayName].
  Future<Result<JoinedHousehold, HouseholdFailure>> join({
    required String code,
    required String displayName,
  });
}

/// The [HouseholdRepository] for this run. Throws until the composition
/// root sets it.
final householdRepositoryProvider = Provider<HouseholdRepository>(
  (ref) => throw UnimplementedError(
    'householdRepositoryProvider is set in bootstrap()',
  ),
  name: 'householdRepositoryProvider',
);

/// The membership as a stream, for screens that show the household.
final membershipProvider = StreamProvider<Membership>(
  (ref) => ref.watch(householdRepositoryProvider).watchMembership(),
  name: 'membershipProvider',
);
