// The read side of Activity (DESIGN_SYSTEM screen 16; DATA_MODEL 6;
// BACKLOG S2.4): a live, growing window of the newest transactions the
// member can see.
//
// This file is the interface features import. The Firestore adapter is
// `activity_feed_firestore.dart` and the in-memory one
// `activity_feed_memory.dart`; only the composition root and tests name
// them. Writes never go through here: they go through
// `TransactionsRepository` (D-10).
//
// Query rules (DATA_MODEL 6):
// - every query filters `visibleTo array-contains <uid>` and
//   `deletedAt == null` (every live entry stores an explicit null);
// - "All" uses the index (visibleTo, deletedAt, occurredAt desc);
// - a type filter uses (visibleTo, type, occurredAt desc) and a member
//   filter (visibleTo, whoUid, occurredAt desc), merged with the first for
//   the `deletedAt` equality. Where the backend asks for a composite index
//   instead, the adapter falls back to the "All" query and filters on the
//   phone ([ActivityWindow.filteredOnPhone]).
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:xpense_app/data/transactions_repository.dart';
import 'package:xpense_shared/xpense_shared.dart';

/// Which entries a window holds, newest first.
@immutable
final class ActivityQuery {
  /// Creates a query for the newest [limit] entries, of [types] only when
  /// given, and of member [whoUid] only when given.
  const new({required this.limit, this.types, this.whoUid})
    : assert(limit > 0, 'limit must be positive'),
      assert(
        types == null || whoUid == null,
        'one filter at a time: the indexes cover one',
      );

  /// How many entries, at most.
  final int limit;

  /// Only these ledger types (`type in [...]`); null is every type.
  final Set<LedgerType>? types;

  /// Only entries of this member (`whoUid ==`); null is everyone's.
  final String? whoUid;

  /// Whether [txn] passes the filter (the phone-side check, also used by
  /// the fallback and the memory adapter).
  bool matches(LedgerTransaction txn) =>
      (types == null || types!.contains(txn.type)) &&
      (whoUid == null || txn.whoUid == whoUid);

  /// The same filter with another [limit].
  ActivityQuery withLimit(int limit) =>
      ActivityQuery(limit: limit, types: types, whoUid: whoUid);

  @override
  bool operator ==(Object other) =>
      other is ActivityQuery &&
      other.limit == limit &&
      setEquals(other.types, types) &&
      other.whoUid == whoUid;

  @override
  int get hashCode => Object.hash(
    limit,
    types == null ? null : Object.hashAllUnordered(types!),
    whoUid,
  );

  @override
  String toString() =>
      'ActivityQuery($limit, ${types?.map((t) => t.wire).join('|')}, '
      '${whoUid == null ? '' : 'who'})';
}

/// One snapshot of the window.
@immutable
final class ActivityWindow {
  /// Creates the snapshot.
  const new({
    required this.entries,
    required this.hasMore,
    this.fromCache = false,
    this.syncing = const {},
    this.filteredOnPhone = false,
  });

  /// Live entries the member can see, newest first.
  final List<LedgerTransaction> entries;

  /// Whether older entries may exist beyond the limit.
  final bool hasMore;

  /// Whether the snapshot came from the phone's cache only (offline, or the
  /// server has not answered yet).
  final bool fromCache;

  /// Ids of entries with a write still on the phone only ("syncing" dot,
  /// DATA_MODEL 7).
  final Set<String> syncing;

  /// Whether the filter ran on the phone over the "All" window because the
  /// backend had no index for it.
  final bool filteredOnPhone;

  @override
  bool operator ==(Object other) =>
      other is ActivityWindow &&
      listEquals(other.entries, entries) &&
      other.hasMore == hasMore &&
      other.fromCache == fromCache &&
      setEquals(other.syncing, syncing) &&
      other.filteredOnPhone == filteredOnPhone;

  @override
  int get hashCode => Object.hash(
    Object.hashAll(entries),
    hasMore,
    fromCache,
    Object.hashAllUnordered(syncing),
    filteredOnPhone,
  );

  @override
  String toString() =>
      'ActivityWindow(${entries.length}, more: $hasMore, cache: $fromCache)';
}

/// Why the window could not be read. Carries a stable [code]; the screen
/// localises from it.
@immutable
sealed class ActivityFeedFailure implements Exception, Failure {
  const new();

  @override
  bool operator ==(Object other) => other.runtimeType == runtimeType;

  @override
  int get hashCode => runtimeType.hashCode;

  @override
  String toString() => code;
}

/// The rules refused the read.
final class ActivityNotAllowed extends ActivityFeedFailure {
  /// Creates the failure.
  const new();

  @override
  String get code => 'activity.not_allowed';
}

/// Anything else. The original error is reported where it was caught.
final class ActivityReadFailed extends ActivityFeedFailure {
  /// Creates the failure with a machine-readable [detail].
  const new(this.detail);

  /// The error code or type. Never shown.
  final String detail;

  @override
  String get code => 'activity.read_failed';

  @override
  bool operator ==(Object other) =>
      other is ActivityReadFailed && other.detail == detail;

  @override
  int get hashCode => Object.hash(ActivityReadFailed, detail);
}

/// How long a window may come from the cache only before the phone counts
/// as offline. A normal start is served from the cache first and by the
/// server a moment later; this keeps the offline strip from flashing then.
const Duration cacheOnlyMeansOffline = Duration(seconds: 2);

/// Reads the Activity window.
abstract interface class ActivityFeed {
  /// The newest entries matching [query], live. Emits again on every change
  /// (a save, an edit, a delete, an undo, the partner's writes). Errors are
  /// [ActivityFeedFailure]s. Emits an empty window while not in a
  /// household.
  Stream<ActivityWindow> watch(ActivityQuery query);
}

/// The [ActivityFeed] for this run. Throws until the composition root sets
/// it.
final activityFeedProvider = Provider<ActivityFeed>(
  (ref) =>
      throw UnimplementedError('activityFeedProvider is set in bootstrap()'),
  name: 'activityFeedProvider',
);
