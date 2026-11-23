// Activity state (BACKLOG S2.4): the chosen filter, how far back the window
// reaches, and the search text; the live window from the feed; and the flat
// list the screen draws, derived from both.
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:xpense_app/data/accounts_repository.dart';
import 'package:xpense_app/data/household_repository.dart';
import 'package:xpense_app/data/read/activity_reader.dart';
import 'package:xpense_app/features/activity/activity_model.dart';
import 'package:xpense_shared/xpense_shared.dart';

/// What the member chose on Activity.
@immutable
final class ActivityViewState {
  /// Creates the state.
  const new({
    this.filter = ActivityFilter.all,
    this.limit = ActivityController.pageSize,
    this.search = '',
  });

  /// The filter bar's choice.
  final ActivityFilter filter;

  /// How many entries the window holds at most.
  final int limit;

  /// The search field's text.
  final String search;

  /// A copy with the given fields changed.
  ActivityViewState copyWith({
    ActivityFilter? filter,
    int? limit,
    String? search,
  }) => ActivityViewState(
    filter: filter ?? this.filter,
    limit: limit ?? this.limit,
    search: search ?? this.search,
  );

  @override
  bool operator ==(Object other) =>
      other is ActivityViewState &&
      other.filter == filter &&
      other.limit == limit &&
      other.search == search;

  @override
  int get hashCode => Object.hash(filter, limit, search);
}

/// Changes what Activity shows.
final class ActivityController extends Notifier<ActivityViewState> {
  /// Entries read per page: a few days of a busy household.
  static const int pageSize = 50;

  @override
  ActivityViewState build() => const ActivityViewState();

  /// Shows [filter], from the newest page again.
  void select(ActivityFilter filter) {
    if (filter == state.filter) return;
    state = state.copyWith(filter: filter, limit: pageSize);
  }

  /// Searches the loaded entries for [text].
  void search(String text) => state = state.copyWith(search: text);

  /// Reaches one page further back, when [window] says there is more.
  /// Callers wait until the previous page has arrived (the window provider
  /// is not loading), so a page is never skipped.
  void loadMore(ActivityWindow? window) {
    if (window == null || !window.hasMore) return;
    state = state.copyWith(limit: state.limit + pageSize);
  }
}

/// Activity's state.
final activityControllerProvider =
    NotifierProvider<ActivityController, ActivityViewState>(
      ActivityController.new,
      name: 'activityControllerProvider',
    );

/// The viewer's uid and the partner's, once known.
@immutable
final class ActivityPeople {
  /// Creates the pair.
  const new({this.viewerUid, this.partnerUid, this.partnerName});

  /// The signed-in member.
  final String? viewerUid;

  /// The partner, once they have joined.
  final String? partnerUid;

  /// The partner's display name, when they chose one.
  final String? partnerName;

  @override
  bool operator ==(Object other) =>
      other is ActivityPeople &&
      other.viewerUid == viewerUid &&
      other.partnerUid == partnerUid &&
      other.partnerName == partnerName;

  @override
  int get hashCode => Object.hash(viewerUid, partnerUid, partnerName);
}

/// Who is looking, and who the partner is.
final Provider<ActivityPeople> activityPeopleProvider =
    Provider.autoDispose<ActivityPeople>((ref) {
      // The viewer is known once the membership is.
      ref.watch(membershipProvider);
      final viewer = ref.watch(accountsRepositoryProvider).viewerUid;
      final members =
          ref.watch(householdMembersProvider).value ??
          const <HouseholdMember>[];
      final partner = members.where((m) => m.uid != viewer).firstOrNull;
      return ActivityPeople(
        viewerUid: viewer,
        partnerUid: partner?.uid,
        partnerName: partner == null || partner.displayName.isEmpty
            ? null
            : partner.displayName,
      );
    }, name: 'activityPeopleProvider');

/// The feed query for the current filter and window size; null when the
/// filter names a member who is not known yet.
final Provider<ActivityQuery?> activityQueryProvider =
    Provider.autoDispose<ActivityQuery?>((ref) {
      final view = ref.watch(activityControllerProvider);
      final people = ref.watch(activityPeopleProvider);
      return view.filter.query(
        limit: view.limit,
        viewerUid: people.viewerUid,
        partnerUid: people.partnerUid,
      );
    }, name: 'activityQueryProvider');

/// The live window. While a longer window loads, the previous one stays
/// readable (`AsyncLoading` with a value).
final StreamProvider<ActivityWindow> activityWindowProvider =
    StreamProvider.autoDispose<ActivityWindow>((ref) {
      final query = ref.watch(activityQueryProvider);
      if (query == null) {
        return Stream.value(const ActivityWindow(entries: [], hasMore: false));
      }
      return ref.watch(activityReaderProvider).watch(query);
    }, name: 'activityWindowProvider');

/// The name of category [id] (the household's seeded categories, which use
/// their slug as id); null when unknown.
String? activityCategoryName(String? id) =>
    id == null ? null : defaultCategory(id)?.nameIn('en');

/// What the list draws.
@immutable
final class ActivityList {
  /// Creates the list.
  const new({
    required this.items,
    required this.window,
    required this.searching,
    required this.matches,
  });

  /// Day headers and rows, in order.
  final List<ActivityItem> items;

  /// The window it came from.
  final ActivityWindow window;

  /// Whether a search narrows it.
  final bool searching;

  /// Entries shown.
  final int matches;
}

/// The flat list for the latest window and the search, or null before the
/// first window. Derived, so scrolling never recomputes it.
///
/// Built from the window's value whatever its state, so a reload or a read
/// error keeps the last list (`whenData` would drop it on an error, Codex
/// review PR #38); the screen reads loading and errors from
/// [activityWindowProvider].
final Provider<ActivityList?> activityListProvider =
    Provider.autoDispose<ActivityList?>((ref) {
      final w = ref.watch(activityWindowProvider.select((a) => a.value));
      final search = ref.watch(
        activityControllerProvider.select((s) => s.search.trim()),
      );
      if (w == null) return null;
      {
        final entries = search.isEmpty
            ? w.entries
            : [
                for (final t in w.entries)
                  if (searchMatches(
                    SearchText.of(
                      t,
                      categoryName: activityCategoryName(t.categoryId),
                    ),
                    search,
                  ))
                    t,
              ];
        return ActivityList(
          items: flatten(groupByDay(entries)),
          window: w,
          searching: search.isNotEmpty,
          matches: entries.length,
        );
      }
    }, name: 'activityListProvider');

/// The failure behind an error state, typed.
ActivityReadFailure activityFailureOf(Object error) => switch (error) {
  final ActivityReadFailure f => f,
  _ => ActivityReadFailed(error.runtimeType.toString()),
};
