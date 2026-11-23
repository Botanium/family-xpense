import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import 'package:xpense_app/core/l10n/l10n.dart';
import 'package:xpense_app/core/routing/routing.dart';
import 'package:xpense_app/core/theme/theme.dart';
import 'package:xpense_app/core/ui/ui.dart';
import 'package:xpense_app/data/accounts_repository.dart';
import 'package:xpense_app/data/household_repository.dart';
import 'package:xpense_app/data/read/activity_reader.dart';
import 'package:xpense_app/data/transactions_repository.dart';
import 'package:xpense_app/features/activity/activity_controller.dart';
import 'package:xpense_app/features/activity/activity_model.dart';
import 'package:xpense_app/features/activity/activity_row.dart';
import 'package:xpense_app/features/activity/swipe_actions.dart';
import 'package:xpense_app/services/clock.dart';
import 'package:xpense_shared/xpense_shared.dart';

/// Query parameter on an entry's location that opens its edit form
/// (WP-21 reads it; until then the entry route shows its placeholder).
const String activityEditParam = 'edit';

/// Where Edit on an Activity row goes: the entry, with its form open.
String activityEditLocation(String txnId) =>
    '${AppRoutes.entry(txnId)}?$activityEditParam=1';

/// Activity (DESIGN_SYSTEM 9, screen 16; artboard 16; BACKLOG S2.4): the
/// "Search or ask" field, the filter bar and the entries grouped by day with
/// each day's net. Rows swipe to Edit and Delete (with the undo toast) and
/// long-press for the same menu. The list pages back as it scrolls.
class ActivityScreen extends ConsumerStatefulWidget {
  /// Creates Activity.
  const new({super.key});

  /// How long the window must stay served from the cache before the
  /// offline strip shows.
  static const Duration offlineGrace = cacheOnlyMeansOffline;

  /// How close to the end of the list the next page starts loading.
  static const double loadAheadExtent = 800;

  @override
  ConsumerState<ActivityScreen> createState() => _ActivityScreenState();
}

class _ActivityScreenState extends ConsumerState<ActivityScreen> {
  late final TextEditingController _search = TextEditingController(
    text: ref.read(activityControllerProvider).search,
  );
  final SwipeGroup _group = SwipeGroup();
  VoidCallback? _dismissToast;
  Timer? _offlineTimer;
  bool _offline = false;
  String? _notice;

  @override
  void initState() {
    super.initState();
    ref.listenManual(activityWindowProvider, _onWindow, fireImmediately: true);
  }

  @override
  void dispose() {
    _offlineTimer?.cancel();
    _search.dispose();
    _group.dispose();
    super.dispose();
  }

  // --------------------------------------------------------------- state

  void _onWindow(
    AsyncValue<ActivityWindow>? previous,
    AsyncValue<ActivityWindow> next,
  ) {
    final cached = next.value?.fromCache ?? false;
    if (!cached) {
      _offlineTimer?.cancel();
      _offlineTimer = null;
      if (_offline) setState(() => _offline = false);
      return;
    }
    if (_offline || _offlineTimer != null) return;
    _offlineTimer = Timer(ActivityScreen.offlineGrace, () {
      _offlineTimer = null;
      if (mounted) setState(() => _offline = true);
    });
  }

  void _loadMore() {
    final window = ref.read(activityWindowProvider);
    if (window.isLoading || !window.hasValue) return;
    ref.read(activityControllerProvider.notifier).loadMore(window.value);
  }

  void _select(ActivityFilter filter) {
    _group.closeAll();
    setState(() => _notice = null);
    ref.read(activityControllerProvider.notifier).select(filter);
  }

  // ------------------------------------------------------------- actions

  void _ask(String text) {
    final question = text.trim();
    if (question.isEmpty) return;
    unawaited(context.push(AppRoutes.askWith(text: question)));
  }

  void _submit(String text) {
    if (looksLikeQuestion(text)) _ask(text);
  }

  void _open(LedgerTransaction txn) =>
      unawaited(context.push(AppRoutes.entry(txn.id)));

  void _edit(LedgerTransaction txn) =>
      unawaited(context.push(activityEditLocation(txn.id)));

  Future<void> _delete(LedgerTransaction txn) async {
    final l10n = context.l10n;
    final repository = ref.read(transactionsRepositoryProvider);
    _dismissToast?.call();
    _dismissToast = null;
    setState(() => _notice = null);
    final result = await repository.deleteEntry(txn.id);
    if (!mounted) return;
    switch (result) {
      case Ok():
        final title = txn.title.trim().isNotEmpty
            ? txn.title.trim()
            : txn.personName;
        _dismissToast = showUndoToast(
          context: context,
          message: title == null || title.isEmpty
              ? l10n.activityDeletedEntry
              : l10n.activityDeleted(title),
          actionLabel: l10n.activityUndo,
          onAction: () => unawaited(_restore(repository, txn.id)),
        );
      // Already gone (the partner deleted it a moment before): nothing to
      // undo, nothing to say.
      case Err(failure: TransactionDeleted()):
        break;
      case Err(:final failure):
        setState(
          () => _notice = failure is TransactionConflict
              ? l10n.activityChangedElsewhere
              : l10n.activityDeleteFailed,
        );
    }
  }

  Future<void> _restore(TransactionsRepository repository, String id) async {
    _dismissToast = null;
    final result = await repository.restoreEntry(id);
    if (!mounted) return;
    final l10n = context.l10n;
    switch (result) {
      case Ok() || Err(failure: TransactionNotDeleted()):
        break;
      case Err(:final failure):
        setState(
          () => _notice = failure is TransactionConflict
              ? l10n.activityChangedElsewhere
              : l10n.activityRestoreFailed,
        );
    }
  }

  // --------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final type = XpType.of(context);
    final colors = XpColors.of(context);
    final view = ref.watch(activityControllerProvider);
    final people = ref.watch(activityPeopleProvider);
    final list = ref.watch(activityListProvider);

    final filters = [
      ActivityFilter.all,
      ActivityFilter.out,
      ActivityFilter.inflow,
      ActivityFilter.loans,
      ActivityFilter.you,
      if (people.partnerUid != null) ActivityFilter.partner,
    ];
    String filterLabel(ActivityFilter f) => switch (f) {
      ActivityFilter.all => l10n.activityFilterAll,
      ActivityFilter.out => l10n.activityFilterOut,
      ActivityFilter.inflow => l10n.activityFilterIn,
      ActivityFilter.loans => l10n.activityFilterLoans,
      ActivityFilter.you => l10n.activityFilterYou,
      ActivityFilter.partner =>
        people.partnerName ?? l10n.activityFilterPartner,
    };
    final notice = _notice;

    return Scaffold(
      backgroundColor: colors.canvas,
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            XpTopBar(title: l10n.activityTitle),
            Padding(
              padding: const EdgeInsetsDirectional.only(
                start: XpSpace.screenMargin,
                end: XpSpace.screenMargin,
                top: XpSpace.s8,
                bottom: XpSpace.s16,
              ),
              child: XpSearchField(
                hint: l10n.activitySearchHint,
                controller: _search,
                onChanged: ref.read(activityControllerProvider.notifier).search,
                onSubmitted: _submit,
              ),
            ),
            Padding(
              padding: const EdgeInsetsDirectional.symmetric(
                horizontal: XpSpace.screenMargin,
              ),
              child: XpFilterBar(
                labels: [for (final f in filters) filterLabel(f)],
                selectedIndex: filters
                    .indexOf(view.filter)
                    .clamp(0, filters.length - 1),
                onSelected: (i) => _select(filters[i]),
              ),
            ),
            const Hairline(),
            if (_offline)
              Padding(
                padding: const EdgeInsetsDirectional.only(top: XpSpace.s8),
                child: OfflineBanner(message: l10n.activityOffline),
              ),
            if (notice != null)
              Padding(
                padding: const EdgeInsetsDirectional.only(
                  start: XpSpace.screenMargin,
                  end: XpSpace.screenMargin,
                  top: XpSpace.s8,
                ),
                child: Semantics(
                  liveRegion: true,
                  child: Text(
                    notice,
                    style: type.meta.copyWith(color: colors.danger),
                  ),
                ),
              ),
            Expanded(child: _body(context, list, view)),
          ],
        ),
      ),
    );
  }

  Widget _body(
    BuildContext context,
    AsyncValue<ActivityList> list,
    ActivityViewState view,
  ) {
    final l10n = context.l10n;
    if (list.hasValue) return _list(context, list.requireValue, view);
    if (list.hasError) {
      final failure = activityFailureOf(list.error!);
      return Center(
        child: Padding(
          padding: const EdgeInsetsDirectional.symmetric(
            horizontal: XpSpace.screenMargin,
          ),
          child: EmptyState(
            message: switch (failure) {
              ActivityNotAllowed() => l10n.activityLoadNotAllowed,
              ActivityReadFailed() => l10n.activityLoadError,
            },
            actionLabel: l10n.activityRetry,
            onAction: () => ref.invalidate(activityWindowProvider),
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsetsDirectional.symmetric(
        horizontal: XpSpace.screenMargin,
        vertical: XpSpace.s16,
      ),
      child: Skeleton(rows: 6, semanticLabel: l10n.activityLoading),
    );
  }

  Widget _list(
    BuildContext context,
    ActivityList data,
    ActivityViewState view,
  ) {
    final l10n = context.l10n;
    final window = data.window;
    final loadingMore = ref.watch(
      activityWindowProvider.select((w) => w.isLoading),
    );
    final question = data.searching && looksLikeQuestion(view.search)
        ? view.search.trim()
        : null;

    if (data.items.isEmpty) {
      final empty = data.searching
          ? EmptyState(
              message: l10n.activitySearchEmpty,
              actionLabel: window.hasMore ? l10n.activitySearchOlder : null,
              onAction: window.hasMore ? _loadMore : null,
            )
          : view.filter == ActivityFilter.all
          ? EmptyState(
              message: l10n.activityEmpty,
              actionLabel: l10n.activityEmptyAdd,
              onAction: () => unawaited(context.push(AppRoutes.ask)),
            )
          : EmptyState(message: l10n.activityEmptyFiltered);
      return ListView(
        padding: EdgeInsetsDirectional.only(
          start: XpSpace.screenMargin,
          end: XpSpace.screenMargin,
          bottom: XpSpace.contentBottomPadding(context),
        ),
        children: [
          if (question != null) _AskRow(text: question, onAsk: _ask),
          empty,
        ],
      );
    }

    final membership = ref.watch(membershipProvider).value;
    final accounts = ref.watch(accountsProvider).value ?? const <Account>[];
    final labels = ActivityRowLabels(
      accountNames: {for (final a in accounts) a.id: a.name},
      baseCurrency: membership is InHousehold
          ? membership.household.baseCurrency
          : Currency.usd,
      people: ref.watch(activityPeopleProvider),
    );
    final today = ref.read(clockProvider).now().toLocal();
    final lead = question == null ? 0 : 1;
    final items = data.items;

    return NotificationListener<ScrollNotification>(
      onNotification: (n) {
        if (n is ScrollStartNotification && n.dragDetails != null) {
          _group.closeAll();
        }
        if (n.metrics.axis == Axis.vertical &&
            n.metrics.extentAfter < ActivityScreen.loadAheadExtent &&
            window.hasMore &&
            !data.searching) {
          _loadMore();
        }
        return false;
      },
      child: ListView.builder(
        padding: EdgeInsetsDirectional.only(
          bottom: XpSpace.contentBottomPadding(context),
        ),
        itemCount: lead + items.length + 1,
        findChildIndexCallback: (key) {
          if (key is! ValueKey<String>) return null;
          final i = items.indexWhere(
            (it) => it is ActivityEntryItem && it.txn.id == key.value,
          );
          return i < 0 ? null : i + lead;
        },
        itemBuilder: (context, index) {
          if (index < lead) {
            return Padding(
              padding: const EdgeInsetsDirectional.symmetric(
                horizontal: XpSpace.screenMargin,
              ),
              child: _AskRow(text: question!, onAsk: _ask),
            );
          }
          final i = index - lead;
          if (i == items.length) {
            return _Footer(
              hasMore: window.hasMore,
              loading: loadingMore,
              label: data.searching
                  ? l10n.activitySearchOlder
                  : l10n.activityLoadOlder,
              onMore: _loadMore,
            );
          }
          return switch (items[i]) {
            ActivityDayHeader(:final day) => Padding(
              padding: const EdgeInsetsDirectional.symmetric(
                horizontal: XpSpace.screenMargin,
              ),
              child: ActivityDayHeaderView(
                day: day,
                today: today,
                baseCurrency: labels.baseCurrency,
              ),
            ),
            ActivityEntryItem(:final txn, :final last) => ActivityEntryRow(
              key: ValueKey<String>(txn.id),
              txn: txn,
              labels: labels,
              group: _group,
              last: last,
              syncing: window.syncing.contains(txn.id),
              onOpen: () => _open(txn),
              onEdit: () => _edit(txn),
              onDelete: () => unawaited(_delete(txn)),
            ),
          };
        },
      ),
    );
  }
}

/// "Ask “how much on food?”" at the top of search results.
class _AskRow extends StatelessWidget {
  const new({required this.text, required this.onAsk});

  final String text;
  final ValueChanged<String> onAsk;

  @override
  Widget build(BuildContext context) {
    final colors = XpColors.of(context);
    return XpListRow(
      title: context.l10n.activityAskRow(text),
      leading: XpIcon(
        XpGlyph.sparkle,
        size: XpSpace.iconRow,
        color: colors.accent,
      ),
      onTap: () => onAsk(text),
    );
  }
}

/// The end of the list: a spinner while older entries load, or a button
/// to load them when the list is too short to scroll there.
class _Footer extends StatelessWidget {
  const new({
    required this.hasMore,
    required this.loading,
    required this.label,
    required this.onMore,
  });

  final bool hasMore;
  final bool loading;
  final String label;
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context) {
    if (!hasMore) return const SizedBox(height: XpSpace.s16);
    return Padding(
      padding: const EdgeInsetsDirectional.symmetric(vertical: XpSpace.s16),
      child: Center(
        child: loading
            ? XpSpinner(semanticLabel: context.l10n.activityLoading)
            : XpButton.text(label: label, onPressed: onMore),
      ),
    );
  }
}
