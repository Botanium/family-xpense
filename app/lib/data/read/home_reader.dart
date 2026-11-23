// The transaction read path (DATA_MODEL 6): live queries over the entries
// the signed-in member can read, for Home (WP-23) and any later screen that
// lists entries. Writes stay in `transactions_repository.dart` (D-10).
//
// Every query carries the `visibleTo` filter, so a partner's private entry
// never reaches the phone (DATA_MODEL 4); the implementations repeat the
// check on the results as well.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:xpense_app/data/transactions_repository.dart';

/// Live reads of the transactions the signed-in member can see.
abstract interface class HomeReader {
  /// Live, non-deleted entries whose household-local day (`occurredOn`) is
  /// from [fromDay] to [toDay] inclusive (`YYYY-MM-DD`), oldest first.
  ///
  /// Uses the `visibleTo` + `occurredOn` index ("month totals, daily
  /// chart"). Emits an empty list while signed out or outside a household.
  Stream<List<LedgerTransaction>> watchRange({
    required String fromDay,
    required String toDay,
  });

  /// The latest [limit] live, non-deleted entries, newest first.
  ///
  /// Uses the `visibleTo` + `deletedAt` + `occurredAt` index ("Activity,
  /// Home recent").
  Stream<List<LedgerTransaction>> watchRecent({required int limit});
}

/// The [HomeReader] for this run. Throws until the composition root
/// sets it.
final homeReaderProvider = Provider<HomeReader>(
  (ref) => throw UnimplementedError('homeReaderProvider is set in bootstrap()'),
  name: 'homeReaderProvider',
);
