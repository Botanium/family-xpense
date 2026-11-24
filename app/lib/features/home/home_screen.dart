import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';
import 'package:xpense_app/core/l10n/l10n.dart';
import 'package:xpense_app/core/routing/routing.dart';
import 'package:xpense_app/core/theme/theme.dart';
import 'package:xpense_app/core/ui/ui.dart';
import 'package:xpense_app/data/accounts_repository.dart';
import 'package:xpense_app/data/categories_repository.dart';
import 'package:xpense_app/data/household_repository.dart';
import 'package:xpense_app/features/home/home_providers.dart';
import 'package:xpense_app/features/home/home_rate_prompt.dart';
import 'package:xpense_app/features/home/home_summary.dart';
import 'package:xpense_shared/xpense_shared.dart';

/// Home (DESIGN_SYSTEM 9, screen 6; artboard 06): the mono header with the
/// bell and the avatar pair, the household balance, the month's daily
/// spending, the Income / Spent / Saved ledger, the nudge row and Recent.
///
/// No cards: content sits on the canvas with hairlines. Every figure is
/// derived from what the viewer can read ([homeSummaryProvider]).
class HomeScreen extends ConsumerStatefulWidget {
  /// Creates Home.
  const new({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    // Back from the background: today may be another day, or another month.
    _lifecycle = AppLifecycleListener(
      onResume: () => ref.read(homeMonthProvider.notifier).refresh(),
    );
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = XpColors.of(context);
    final summary = ref.watch(homeSummaryProvider);
    final l10n = context.l10n;
    return Scaffold(
      backgroundColor: colors.canvas,
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator.adaptive(
          onRefresh: () => _refresh(ref),
          child: ListView(
            // Pull to refresh works even when Home fits on the screen.
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsetsDirectional.only(
              start: XpSpace.screenMargin,
              end: XpSpace.screenMargin,
              top: XpSpace.s8,
              bottom: XpSpace.contentBottomPadding(context),
            ),
            children: [
              const _Header(),
              const SizedBox(height: XpSpace.s32),
              ...switch (summary) {
                AsyncData(:final value) => _body(context, ref, value),
                AsyncError() => [
                  EmptyState(
                    message: l10n.homeLoadError,
                    actionLabel: l10n.homeRetry,
                    onAction: () => unawaited(_refresh(ref)),
                  ),
                ],
                _ => [Skeleton(rows: 6, semanticLabel: l10n.homeTitle)],
              },
            ],
          ),
        ),
      ),
    );
  }

  static Future<void> _refresh(WidgetRef ref) async {
    ref.read(homeMonthProvider.notifier).refresh();
    ref
      ..invalidate(homeMonthTransactionsProvider)
      ..invalidate(homeRecentTransactionsProvider)
      ..invalidate(accountsProvider);
    await ref.read(homeMonthTransactionsProvider.future);
  }

  List<Widget> _body(BuildContext context, WidgetRef ref, HomeSummary s) {
    final l10n = context.l10n;
    final type = XpType.of(context);
    final colors = XpColors.of(context);
    final base = s.baseCurrency;
    String amount(int minor) =>
        MoneyFormat.figure(minor, exponent: base.exponent).amount;
    final other = s.otherCurrency;
    final otherMinor = s.otherBalanceMinor;
    final nudge = ref.watch(homeNudgeProvider);
    // WP-24: today's rate, while nobody has entered it, takes the slot.
    final rateAsk = ref.watch(homeRateAskProvider);
    return [
      HeroBalance(
        label: s.balanceComplete
            ? l10n.homeHouseholdBalance
            : l10n.homeYourView,
        minorUnits: s.balanceMinor,
        exponent: base.exponent,
        currencyMark: currencyMark(base),
        delta: l10n.homeMonthDelta(
          MoneyFormat.figure(
            s.netMinor,
            exponent: base.exponent,
            signed: true,
          ).amount,
        ),
        deltaPositive: s.netMinor >= 0,
        secondary: other == null || otherMinor == null
            ? null
            // A no-break space keeps "IQD 21.3M" on one line when the delta
            // line wraps at large text.
            : MoneyFormat.compact(
                otherMinor,
                exponent: other.exponent,
                currency: other.code,
              ).withCurrency.replaceAll(' ', '\u00A0'),
      ),
      for (final currency in s.unconverted)
        Padding(
          padding: const EdgeInsetsDirectional.only(top: XpSpace.s4),
          child: Text(
            l10n.homeUnconvertedNote(currency.code),
            style: type.meta.copyWith(color: colors.inkSecondary),
          ),
        ),
      const SizedBox(height: XpSpace.s24),
      _ChartHead(
        average: l10n
            .homeDailyAverage(
              MoneyFormat.figure(
                s.dailyAverageMinor,
                exponent: base.exponent,
              ).whole,
            )
            .toUpperCase(),
      ),
      const SizedBox(height: XpSpace.s8),
      MiniBars(values: s.dailySpentMinor, summary: _chartSummary(context, s)),
      const SizedBox(height: XpSpace.s24),
      LedgerRow(
        label: l10n.homeIncome,
        value: amount(s.incomeMinor),
        dotColor: colors.income,
      ),
      LedgerRow(
        label: l10n.homeSpent,
        value: amount(s.spentMinor),
        dotColor: colors.ink,
      ),
      LedgerRow(
        label: l10n.homeSaved,
        value: amount(s.savedMinor),
        dotColor: colors.saved,
      ),
      if (rateAsk != null) ...[
        const SizedBox(height: XpSpace.s12),
        HomeRatePrompt(ask: rateAsk),
      ] else if (nudge != null) ...[
        const SizedBox(height: XpSpace.s12),
        switch (nudge) {
          HomeNudge.tryAsk => NudgeRow(
            message: l10n.homeNudgeTryAsk,
            actionLabel: l10n.homeNudgeTryAskAction,
            onAction: () => unawaited(context.push(AppRoutes.ask)),
          ),
        },
      ],
      const SizedBox(height: XpSpace.s20),
      SectionLabel(
        l10n.homeRecent,
        actionLabel: l10n.homeSeeAll,
        onAction: () => context.go(AppRoutes.activity),
      ),
      if (s.recent.isEmpty)
        Padding(
          padding: const EdgeInsetsDirectional.only(top: XpSpace.s16),
          child: EmptyState(
            message: l10n.homeRecentEmpty,
            actionLabel: l10n.homeRecentEmptyAction,
            onAction: () => unawaited(context.push(AppRoutes.ask)),
          ),
        )
      else
        for (final entry in s.recent)
          _RecentRow(
            entry: entry,
            summary: s,
            categoryNames: ref.watch(categoryNamesProvider),
          ),
    ];
  }

  String _chartSummary(BuildContext context, HomeSummary s) {
    final l10n = context.l10n;
    if (s.spentMinor <= 0) return l10n.homeChartSummaryEmpty;
    final locale = Localizations.localeOf(context).toLanguageTag();
    final days = DateFormat.MMMMd(locale);
    String day(int d) => days.format(DateTime(s.month.year, s.month.month, d));
    final base = s.baseCurrency;
    final average = MoneyFormat.figure(
      s.dailyAverageMinor,
      exponent: base.exponent,
      currency: base.code,
    );
    final averageText = '${average.currency} ${average.whole}';
    final busiest = s.busiestDay;
    return busiest == s.month.day
        ? l10n.homeChartSummaryToday(day(1), day(s.month.day), averageText)
        : l10n.homeChartSummary(
            day(1),
            day(s.month.day),
            averageText,
            day(busiest ?? s.month.day),
          );
  }
}

/// The short mark before the hero figure: `$` for dollars, else the code.
String currencyMark(Currency currency) => switch (currency) {
  Currency.usd => r'$',
  _ => currency.code,
};

/// "NOV 2026 · OUR HOME", the bell and the avatar pair.
class _Header extends ConsumerWidget {
  const new();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final type = XpType.of(context);
    final colors = XpColors.of(context);
    final membership = ref.watch(membershipProvider).value;
    final household = membership is InHousehold ? membership.household : null;
    final members = ref.watch(householdMembersProvider).value ?? const [];
    final viewer = ref.watch(accountsRepositoryProvider).viewerUid;
    final month = ref.watch(homeMonthProvider);
    final locale = Localizations.localeOf(context).toLanguageTag();
    final monthText = DateFormat.yMMM(locale)
        .format(DateTime(month.year, month.month));
    final me = members.where((m) => m.uid == viewer).firstOrNull;
    final partner = members.where((m) => m.uid != viewer).firstOrNull;
    final myName = _name(me?.displayName) ?? household?.myDisplayName ?? '';
    final partnerName = _name(partner?.displayName);
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: XpSpace.minTarget),
      child: Row(
        children: [
          Expanded(
            child: Text(
              household == null
                  ? monthText.toUpperCase()
                  : l10n.homeHeader(monthText, household.name).toUpperCase(),
              style: type.monoLabel.copyWith(color: colors.inkSecondary),
            ),
          ),
          const SizedBox(width: XpSpace.s8),
          GlassIconButton(
            glyph: XpGlyph.bell,
            semanticLabel: l10n.homeNotifications,
            // The notification centre arrives with WP-61.
            onPressed: null,
          ),
          const SizedBox(width: XpSpace.s8),
          XpPressable(
            onPressed: () => unawaited(context.push(AppRoutes.settings)),
            semanticLabel: l10n.homeSettingsButton,
            excludeChildSemantics: true,
            child: AvatarPair(
              first: _initial(myName, l10n.homeWhoYou),
              second: partnerName == null ? '' : _initial(partnerName, ''),
              semanticLabel: '',
            ),
          ),
        ],
      ),
    );
  }

  static String? _name(String? name) =>
      name == null || name.trim().isEmpty ? null : name.trim();

  static String _initial(String name, String fallback) {
    final source = name.isEmpty ? fallback : name;
    return source.isEmpty ? '' : source.characters.first.toUpperCase();
  }
}

/// "Daily spending" and the average, side by side; stacked at large text.
class _ChartHead extends StatelessWidget {
  const new({required this.average});

  final String average;

  @override
  Widget build(BuildContext context) {
    final type = XpType.of(context);
    final colors = XpColors.of(context);
    final l10n = context.l10n;
    final label = Text(
      l10n.homeDailySpending,
      style: type.caption.copyWith(color: colors.inkSecondary),
    );
    final value = Text(
      average,
      style: type.figureSmall.copyWith(color: colors.inkSecondary),
    );
    if (rowsStack(context)) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [label, value],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Expanded(child: label),
        const SizedBox(width: XpSpace.s8),
        value,
      ],
    );
  }
}

/// One Recent row: title, "Category · Who", the signed amount.
class _RecentRow extends StatelessWidget {
  const new({
    required this.entry,
    required this.summary,
    required this.categoryNames,
  });

  final RecentEntry entry;
  final HomeSummary summary;

  /// The household's category names by id (WP-24).
  final Map<String, String> categoryNames;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final what = _what(context);
    final who = switch (entry.who) {
      HomeWho.you => l10n.homeWhoYou,
      HomeWho.joint => l10n.homeWhoJoint,
      HomeWho.partner => summary.partnerName ?? l10n.homeWhoPartner,
    };
    final inBase = entry.currency == summary.baseCurrency;
    return XpListRow(
      title: entry.title.isEmpty ? what : entry.title,
      subtitle: l10n.homeRecentMeta(what, who),
      trailing: MoneyText(
        entry.signedMinor,
        exponent: entry.currency.exponent,
        currency: inBase ? '' : entry.currency.code,
        tone: entry.type == LedgerType.income
            ? MoneyTone.income
            : MoneyTone.neutral,
        signed: entry.direction == RecentDirection.inflow,
        textAlign: rowsStack(context) ? TextAlign.start : TextAlign.end,
      ),
      onTap: () => unawaited(context.push(AppRoutes.entry(entry.id))),
    );
  }

  /// The category name, or what kind of entry it is.
  String _what(BuildContext context) {
    final l10n = context.l10n;
    final slug = entry.categorySlug;
    // The household's names, archived categories too (WP-24).
    final category = slug == null ? null : categoryNames[slug];
    if (category != null) return category;
    return switch (entry.type) {
      LedgerType.expense => l10n.homeTypeExpense,
      LedgerType.income => l10n.homeTypeIncome,
      LedgerType.transfer =>
        entry.savings ? l10n.homeTypeSavings : l10n.homeTypeTransfer,
      LedgerType.loanGiven || LedgerType.loanTaken => l10n.homeTypeLoan,
      LedgerType.repaymentReceived ||
      LedgerType.repaymentMade => l10n.homeTypeRepayment,
      LedgerType.adjustment => l10n.homeTypeAdjustment,
    };
  }
}
