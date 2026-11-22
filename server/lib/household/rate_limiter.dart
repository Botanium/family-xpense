/// Per-user limits on the household flows (ARCHITECTURE 4.5).
///
/// One fixed window per user and action, kept in the server-only document
/// `rateLimits/{uid}` (no phone rule allows it, so a user cannot reset their
/// own count): `{<action>: {windowStart, count}}`.
library;

import 'package:clock/clock.dart';
import 'package:meta/meta.dart';

import 'package:xpense_agent/admin/admin_gateway.dart';
import 'package:xpense_agent/household/household_failure.dart';

/// How often one user may call an action.
@immutable
final class RateLimit {
  /// At most [max] calls per [window].
  const new({required this.max, required this.window});

  /// Calls allowed in one window.
  final int max;

  /// The window length.
  final Duration window;
}

/// The actions that are limited, with their limits.
enum LimitedAction {
  /// Creating invite codes: a household needs one, a few retries are fine.
  householdInvite(
    'householdInvite',
    RateLimit(max: 10, window: Duration(hours: 1)),
  ),

  /// Join attempts, successful or not: slows down guessing on top of the
  /// 50-bit code space and App Check.
  householdJoin(
    'householdJoin',
    RateLimit(max: 10, window: Duration(hours: 1)),
  );

  new(this.field, this.limit);

  /// The field in `rateLimits/{uid}`.
  final String field;

  /// The limit.
  final RateLimit limit;
}

/// Counts calls per user and refuses those over the limit.
final class RateLimiter {
  /// Creates a limiter over [_documents].
  new(this._documents, {Clock? clock}) : _clock = clock ?? const Clock();

  final DocumentStore _documents;
  final Clock _clock;

  /// The limiter document of [uid].
  static String pathFor(String uid) => 'rateLimits/$uid';

  /// Counts one call of [action] by [uid], or throws a [HouseholdRejection]
  /// with [HouseholdFailure.rateLimited] when the window is full.
  ///
  /// Runs in its own transaction, before the action's: an action that then
  /// fails still counts, which is the point for join attempts.
  Future<void> hit(String uid, LimitedAction action) async {
    final now = _clock.now().toUtc();
    final path = pathFor(uid);
    await _documents.transaction((tx) async {
      final doc = await tx.read(path);
      final entry = doc?[action.field];
      var start = now;
      var count = 0;
      if (entry
          case {
            'windowStart': final DateTime windowStart,
            'count': final int stored,
          }
          when now.difference(windowStart) < action.limit.window &&
              !windowStart.isAfter(now)) {
        start = windowStart;
        count = stored;
      }
      if (count >= action.limit.max) {
        throw const HouseholdRejection(HouseholdFailure.rateLimited);
      }
      tx.write(path, {
        action.field: {'windowStart': start, 'count': count + 1},
        'updatedAt': now,
        'schemaVersion': 1,
      }, merge: true);
    });
  }
}
