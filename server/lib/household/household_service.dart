/// Invites and joins (BACKLOG S1.5, D-27, D-19).
///
/// The phone creates a household and its first member itself, in one batch
/// the rules check (BACKLOG S1.4). Adding the second member changes
/// `memberIds`, which only the server may write, so it happens here with
/// admin rights, in one transaction:
///
/// - `invites/{sha256(code)}`: `{hid, createdBy, createdAt, expiresAt,
///   usedBy, usedAt}`. The code itself is never stored or logged.
/// - A household has at most one live invite: a new one deletes the unused
///   earlier ones.
/// - Joining checks the invite (exists, unused, unexpired), the household
///   (fewer than two members) and the caller (no other household lists them
///   in `memberIds`), then
///   writes `memberIds`, the member document, `users/{uid}.householdId` and
///   marks the invite used.
library;

import 'dart:math';

import 'package:clock/clock.dart';
import 'package:logging/logging.dart';
import 'package:meta/meta.dart';

import 'package:xpense_agent/admin/admin_gateway.dart';
import 'package:xpense_agent/household/household_failure.dart';
import 'package:xpense_agent/household/invite_code.dart';
import 'package:xpense_agent/household/rate_limiter.dart';

final _log = Logger('xpense.household');

/// An invite as the inviter receives it, once.
@immutable
final class IssuedInvite {
  /// Creates an invite.
  const new({required this.code, required this.expiresAt});

  /// The 10-character code, canonical (no separators).
  final String code;

  /// When the invite stops working (UTC).
  final DateTime expiresAt;

  /// The link that opens the join screen with [code].
  String get link => inviteLink(code);
}

/// The household the caller is now a member of.
@immutable
final class JoinedHousehold {
  /// Creates the result.
  const new({required this.hid, required this.name});

  /// The household id.
  final String hid;

  /// The household's name, for the welcome line.
  final String name;
}

/// Work a join does inside its own transaction, so it commits with the join
/// or not at all. Called after the join's reads with the household's new
/// member ids; it may read, and returns the writes to apply once every read
/// is done (Firestore transactions read before they write).
///
/// WP-13 widens joint and shared accounts to the new member here
/// (`AccountVisibilityJob.prepareJoinWidening`).
typedef JoinTransactionHook = Future<void Function()> Function(
  DocumentTransaction tx,
  String hid,
  List<String> memberIds,
  DateTime now,
);

/// Creates invites and joins households.
final class HouseholdService {
  /// Creates the service. [random] must be cryptographically secure outside
  /// tests; it defaults to `Random.secure()`. `onJoin` runs inside every
  /// join transaction.
  new(
    this._documents, {
    Clock? clock,
    Random? random,
    RateLimiter? limiter,
    this._onJoin,
  }) : _clock = clock ?? const Clock(),
       _random = random ?? Random.secure(),
       _limiter = limiter ?? RateLimiter(_documents, clock: clock);

  /// How long an invite works (D-27).
  static const inviteLifetime = Duration(days: 7);

  /// Members per household (DATA_MODEL 2.2).
  static const maxMembers = 2;

  /// Longest display name, in characters.
  static const maxDisplayName = 40;

  final DocumentStore _documents;
  final Clock _clock;
  final Random _random;
  final RateLimiter _limiter;
  final JoinTransactionHook? _onJoin;

  /// Creates an invite to household [hid] for its member [uid].
  ///
  /// Throws a [HouseholdRejection] (rate limited, not a member, household
  /// full) or a [GatewayUnavailable].
  Future<IssuedInvite> createInvite({
    required String uid,
    required String hid,
  }) async {
    await _limiter.hit(uid, LimitedAction.householdInvite);
    final issued = await _documents.transaction((tx) async {
      final now = _clock.now().toUtc();
      final household = await tx.read(_householdPath(hid));
      final memberIds = _memberIds(household);
      if (!memberIds.contains(uid)) {
        throw const HouseholdRejection(HouseholdFailure.notMember);
      }
      if (memberIds.length >= maxMembers) {
        throw const HouseholdRejection(HouseholdFailure.householdFull);
      }
      final earlier = await tx.whereEquals(_invites, 'hid', hid);
      // A fresh code that no invite, live or used, has had. Collisions in
      // 2^50 codes are not expected; the loop keeps it certain.
      var code = generateInviteCode(_random);
      while (await tx.read(_invitePath(code)) != null) {
        code = generateInviteCode(_random);
      }
      for (final invite in earlier) {
        if (invite.data['usedBy'] == null) tx.delete(invite.path);
      }
      final expiresAt = now.add(inviteLifetime);
      tx.write(_invitePath(code), {
        'hid': hid,
        'createdBy': uid,
        'createdAt': now,
        'expiresAt': expiresAt,
        'usedBy': null,
        'usedAt': null,
        'schemaVersion': 1,
      });
      return IssuedInvite(code: code, expiresAt: expiresAt);
    });
    _log.info({'message': 'invite created', 'uid': uid, 'hid': hid});
    return issued;
  }

  /// Adds [uid] to the household that the invite [code] belongs to, under
  /// [displayName].
  ///
  /// A caller who is already a member of that household gets it back with
  /// nothing written, so a retry after a lost answer succeeds. Throws a
  /// [HouseholdRejection] or a [GatewayUnavailable].
  Future<JoinedHousehold> join({
    required String uid,
    required String code,
    required String displayName,
  }) async {
    final name = cleanDisplayName(displayName);
    if (name == null) {
      throw const HouseholdRejection(HouseholdFailure.invalidName);
    }
    // Counted before the code is even parsed: every guess costs one.
    await _limiter.hit(uid, LimitedAction.householdJoin);
    final canonical = normalizeInviteCode(code);
    if (canonical == null) {
      throw const HouseholdRejection(HouseholdFailure.inviteInvalid);
    }
    final invitePath = _invitePath(canonical);
    final joined = await _documents.transaction((tx) async {
      final now = _clock.now().toUtc();
      final invite = await tx.read(invitePath);
      final hid = invite?['hid'];
      if (invite == null || hid is! String || !_isDocumentId(hid)) {
        throw const HouseholdRejection(HouseholdFailure.inviteInvalid);
      }
      final household = await tx.read(_householdPath(hid));
      if (household == null) {
        throw const HouseholdRejection(HouseholdFailure.inviteInvalid);
      }
      final householdName = switch (household['name']) {
        final String n => n,
        _ => '',
      };
      final memberIds = _memberIds(household);
      if (memberIds.contains(uid)) {
        return JoinedHousehold(hid: hid, name: householdName);
      }
      if (invite['usedBy'] != null) {
        throw const HouseholdRejection(HouseholdFailure.inviteUsed);
      }
      final expiresAt = invite['expiresAt'];
      if (expiresAt is! DateTime || !now.isBefore(expiresAt)) {
        throw const HouseholdRejection(HouseholdFailure.inviteExpired);
      }
      if (memberIds.length >= maxMembers) {
        throw const HouseholdRejection(HouseholdFailure.householdFull);
      }
      // One household per person. Decided from memberIds, which only the
      // server writes, never from users/{uid}.householdId: the user may
      // clear or redirect that pointer themself (PR #29 review).
      final elsewhere = await tx.whereArrayContains(
        _households,
        'memberIds',
        uid,
        limit: 2,
      );
      if (elsewhere.any((h) => h.path != _householdPath(hid))) {
        throw const HouseholdRejection(HouseholdFailure.alreadyInHousehold);
      }
      final user = await tx.read('users/$uid');
      final joinWrites = await _onJoin?.call(tx, hid, [...memberIds, uid], now);

      tx
        ..write(_householdPath(hid), {
          'memberIds': [...memberIds, uid],
          'updatedAt': now,
          'updatedBy': uid,
        }, merge: true)
        ..write('${_householdPath(hid)}/members/$uid', {
          'displayName': name,
          'initial': initialOf(name),
          'role': 'partner',
          'privacyMode': 'smart',
          'notificationPrefs': <String, Object?>{},
          'joinedAt': now,
          'createdAt': now,
          'createdBy': uid,
          'updatedAt': now,
          'updatedBy': uid,
          'schemaVersion': 1,
        })
        ..write('users/$uid', {
          'householdId': hid,
          'displayName': name,
          if (user?['locale'] == null) 'locale': 'en',
        }, merge: true)
        ..write(invitePath, {'usedBy': uid, 'usedAt': now}, merge: true);
      joinWrites?.call();
      return JoinedHousehold(hid: hid, name: householdName);
    });
    _log.info({'message': 'joined', 'uid': uid, 'hid': joined.hid});
    return joined;
  }

  static const _invites = 'invites';

  static const _households = 'households';

  static String _invitePath(String code) => '$_invites/${inviteCodeHash(code)}';

  static String _householdPath(String hid) => '$_households/$hid';

  static List<String> _memberIds(Map<String, Object?>? household) =>
      switch (household?['memberIds']) {
        final List<Object?> ids => ids.whereType<String>().toList(),
        _ => const [],
      };

  static final _documentId = RegExp(r'^[A-Za-z0-9_-]{1,128}$');

  static bool _isDocumentId(String id) => _documentId.hasMatch(id);

  /// [raw] trimmed, with runs of whitespace as one space, or null when it is
  /// empty, longer than [maxDisplayName] characters or has control
  /// characters.
  static String? cleanDisplayName(String raw) {
    final name = raw.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (name.isEmpty || name.runes.length > maxDisplayName) return null;
    if (name.runes.any((r) => r < 0x20 || (r >= 0x7f && r < 0xa0))) {
      return null;
    }
    return name;
  }

  /// The first character of [name], upper-cased: the avatar letter.
  static String initialOf(String name) =>
      String.fromCharCode(name.runes.first).toUpperCase();
}
