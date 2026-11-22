/// Looks up who a verified user is in Firestore, with a 60 s cache.
library;

import 'dart:async';

import 'package:clock/clock.dart';
import 'package:logging/logging.dart';
import 'package:meta/meta.dart';

import 'package:xpense_agent/admin/admin_gateway.dart';
import 'package:xpense_agent/auth/auth_failure.dart';
import 'package:xpense_agent/auth/xpense_context.dart';

final _log = Logger('xpense.auth.members');

/// What the server knows about a member, read from `users/{uid}`,
/// `households/{hid}` and `households/{hid}/members/{uid}`.
@immutable
final class MemberRecord {
  /// Creates a record.
  const new({
    required this.uid,
    required this.hid,
    required this.locale,
    required this.privacyMode,
    required this.timeZone,
  });

  /// Firebase Auth user id.
  final String uid;

  /// Household id.
  final String hid;

  /// `users/{uid}.locale`, default `en`.
  final String locale;

  /// `members/{uid}.privacyMode`.
  final PrivacyMode privacyMode;

  /// `households/{hid}.timeZone`, default `Asia/Baghdad`.
  final String timeZone;
}

/// Reads [MemberRecord]s and caches each for [ttl] (ARCHITECTURE 4.4).
///
/// Only complete records are cached. A user without a household, or not a
/// member, is looked up again on the next request, so joining a household
/// takes effect at once. A change of privacy mode takes effect within [ttl].
/// Concurrent lookups for the same uid share one read.
final class MemberDirectory {
  /// Creates a directory over a [DocumentStore].
  new(
    this._documents, {
    Clock? clock,
    this.ttl = const Duration(seconds: 60),
    this.maxEntries = 10000,
  }) : _clock = clock ?? const Clock();

  /// Default household time zone (DATA_MODEL 2.2).
  static const defaultTimeZone = 'Asia/Baghdad';

  /// Default UI language (D-36).
  static const defaultLocale = 'en';

  final DocumentStore _documents;
  final Clock _clock;

  /// How long a record is served from the cache.
  final Duration ttl;

  /// Cache size bound; the oldest entries are dropped first.
  final int maxEntries;

  final _cache = <String, _Entry>{};

  /// Returns the record for [uid].
  ///
  /// Throws [AuthRejection] with [AuthFailure.noHousehold] or
  /// [AuthFailure.notMember], or [GatewayUnavailable] when Firestore cannot be
  /// read.
  Future<MemberRecord> lookup(String uid) {
    final now = _clock.now();
    final cached = _cache[uid];
    if (cached != null && now.isBefore(cached.expiresAt)) {
      return cached.record;
    }
    _cache.remove(uid);
    final record = _load(uid);
    _cache[uid] = _Entry(record, now.add(ttl));
    _evictOverflow();
    // Failed lookups are not cached. Listening here also marks the error as
    // handled for this cache's own copy; callers still receive it.
    unawaited(
      record.then<void>(
        (_) {},
        onError: (Object _) {
          if (identical(_cache[uid]?.record, record)) _cache.remove(uid);
        },
      ),
    );
    return record;
  }

  /// Drops the cached record for [uid], e.g. after a membership change made by
  /// this server.
  void invalidate(String uid) => _cache.remove(uid);

  void _evictOverflow() {
    while (_cache.length > maxEntries) {
      _cache.remove(_cache.keys.first);
    }
  }

  Future<MemberRecord> _load(String uid) async {
    if (!isDocumentId(uid)) throw const AuthRejection(AuthFailure.notMember);
    final user = await _documents.read('users/$uid');
    final hid = user?['householdId'];
    if (hid == null || hid == '') {
      throw const AuthRejection(AuthFailure.noHousehold);
    }
    // users/{uid} is writable by its owner, so householdId is untrusted until
    // the household itself lists the user. It must also be one plain path
    // segment, or a crafted value could point the reads at another path.
    if (hid is! String || !isDocumentId(hid)) {
      _log.warning('refused: malformed householdId');
      throw const AuthRejection(AuthFailure.notMember);
    }
    final [household, member] = await Future.wait([
      _documents.read('households/$hid'),
      _documents.read('households/$hid/members/$uid'),
    ]);
    // memberIds is what the rules trust (DATA_MODEL 5); the member document
    // holds the settings. Both must agree.
    final memberIds = household?['memberIds'];
    if (household == null ||
        member == null ||
        memberIds is! List ||
        !memberIds.contains(uid)) {
      _log.info('refused: not a member of the household on file');
      throw const AuthRejection(AuthFailure.notMember);
    }
    final locale = user?['locale'];
    final timeZone = household['timeZone'];
    return MemberRecord(
      uid: uid,
      hid: hid,
      locale: locale is String && locale.isNotEmpty ? locale : defaultLocale,
      privacyMode: PrivacyMode.parse(member['privacyMode']),
      timeZone: timeZone is String && timeZone.isNotEmpty
          ? timeZone
          : defaultTimeZone,
    );
  }
}

/// Whether [id] is safe as one Firestore path segment: Firebase uids, the
/// phone's UUID v7 ids and Firestore auto ids all match.
@visibleForTesting
bool isDocumentId(String id) => _documentId.hasMatch(id);

final _documentId = RegExp(r'^[A-Za-z0-9_-]{1,128}$');

final class _Entry {
  new(this.record, this.expiresAt);

  final Future<MemberRecord> record;
  final DateTime expiresAt;
}
