// WP-24: Settings > Exchange rate (BACKLOG S2.6, ARCHITECTURE 3.5): the
// household's label for its rate (official or market), the rate history,
// and correcting a day's rate. A correction never rewrites saved entries:
// each keeps the rate it was saved with (DATA_MODEL 2.13).
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';
import 'package:xpense_app/core/l10n/l10n.dart';
import 'package:xpense_app/core/routing/routing.dart';
import 'package:xpense_app/core/theme/theme.dart';
import 'package:xpense_app/core/ui/ui.dart';
import 'package:xpense_app/data/accounts_repository.dart';
import 'package:xpense_app/data/fx_repository.dart';
import 'package:xpense_shared/xpense_shared.dart';

/// The label of [kind].
String rateKindLabel(AppLocalizations l10n, RateKind kind) => switch (kind) {
  RateKind.official => l10n.settingsFxKindOfficial,
  RateKind.market => l10n.settingsFxKindMarket,
};

/// Settings > Exchange rate.
class RateSettingsScreen extends ConsumerStatefulWidget {
  /// Creates the screen.
  const new({super.key});

  @override
  ConsumerState<RateSettingsScreen> createState() => _RateSettingsScreenState();
}

class _RateSettingsScreenState extends ConsumerState<RateSettingsScreen> {
  bool _saving = false;
  bool _failed = false;

  Future<void> _run(Future<Result<void, FxFailure>> Function() write) async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _failed = false;
    });
    final result = await write();
    if (!mounted) return;
    setState(() {
      _saving = false;
      _failed = result is Err;
    });
  }

  String _dayLabel(BuildContext context, String day, String today) {
    if (day == today) return context.l10n.settingsFxToday;
    final date = DateTime.tryParse(day);
    if (date == null) return day;
    final locale = Localizations.localeOf(context).toLanguageTag();
    final sameYear = today.startsWith('${date.year}-');
    return (sameYear ? DateFormat.MMMd(locale) : DateFormat.yMMMd(locale))
        .format(date);
  }

  /// Opens the keypad for [day]: its rate, else the one before it. A rate
  /// more than 5% from the day before is confirmed first.
  Future<void> _edit(String day, String today) async {
    final rates = ref.read(fxRatesProvider).value ?? const <DailyRate>[];
    final current = rates.where((r) => r.day == day).firstOrNull;
    final previous = rateBefore(rates, day);
    final title = day == today
        ? context.l10n.settingsFxRateTitle
        : context.l10n.settingsFxRateTitleDay(_dayLabel(context, day, today));
    final typed = await showRateEntry(
      context: context,
      labels: rateEntryLabelsOf(
        context,
        title: title,
        previous: previous?.rate.rateString,
      ),
      initial: (current ?? previous)?.rate.rateString ?? '',
      needsConfirm: previous == null
          ? null
          : (typed) => switch (FxRate.forPair(FxPair.usdIqd, typed)) {
              Ok(:final value) => isRateJump(previous.rate, value),
              Err() => false,
            },
    );
    if (typed == null || !mounted) return;
    final rate = FxRate.forPair(FxPair.usdIqd, typed).valueOrNull;
    if (rate == null || rate == current?.rate) return;
    await _run(() => ref.read(fxRepositoryProvider).setRate(day, rate));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final type = XpType.of(context);
    final colors = XpColors.of(context);
    final today = ref.watch(rateTodayProvider);
    final rates = ref.watch(fxRatesProvider).value ?? const <DailyRate>[];
    final kind = ref.watch(rateKindProvider).value ?? RateKind.market;
    final viewer = ref.watch(accountsRepositoryProvider).viewerUid;
    final members = ref.watch(householdMembersProvider).value ?? const [];
    String who(String? uid) {
      if (uid == null) return l10n.settingsFxPartner;
      if (uid == viewer) return l10n.settingsFxYou;
      final name = members.where((m) => m.uid == uid).firstOrNull?.displayName;
      return name == null || name.isEmpty ? l10n.settingsFxPartner : name;
    }

    final hasToday = rates.any((r) => r.day == today);
    return Scaffold(
      backgroundColor: colors.canvas,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            XpTopBar(
              title: l10n.settingsFxTitle,
              leading: const XpBackButton(),
            ),
            Expanded(
              child: ListView(
                padding: EdgeInsetsDirectional.only(
                  start: XpSpace.screenMargin,
                  end: XpSpace.screenMargin,
                  top: XpSpace.s16,
                  bottom: XpSpace.bottomControlOffset(context),
                ),
                children: [
                  XpSection(
                    label: l10n.settingsFxKindSection,
                    children: [
                      Padding(
                        padding: const EdgeInsetsDirectional.symmetric(
                          vertical: XpSpace.s12,
                        ),
                        child: ChoiceChips<RateKind>(
                          options: [
                            for (final k in RateKind.values)
                              ChoiceOption(
                                value: k,
                                label: rateKindLabel(l10n, k),
                              ),
                          ],
                          selected: kind,
                          onSelected: _saving
                              ? null
                              : (k) => unawaited(
                                  _run(
                                    () => ref
                                        .read(fxRepositoryProvider)
                                        .setRateKind(k),
                                  ),
                                ),
                        ),
                      ),
                      Text(
                        l10n.settingsFxKindHint,
                        style: type.meta.copyWith(color: colors.inkSecondary),
                      ),
                    ],
                  ),
                  if (_failed)
                    Padding(
                      padding: const EdgeInsetsDirectional.only(
                        top: XpSpace.s8,
                      ),
                      child: Semantics(
                        liveRegion: true,
                        child: Text(
                          l10n.settingsFxSaveFailed,
                          style: type.meta.copyWith(color: colors.danger),
                        ),
                      ),
                    ),
                  const SizedBox(height: XpSpace.s24),
                  XpSection(
                    label: l10n.settingsFxHistorySection,
                    children: [
                      if (!hasToday)
                        XpListRow(
                          title: l10n.settingsFxToday,
                          subtitle: l10n.settingsFxNotEntered,
                          onTap: _saving
                              ? null
                              : () => unawaited(_edit(today, today)),
                        ),
                      for (final r in rates)
                        XpListRow(
                          title: _dayLabel(context, r.day, today),
                          subtitle: l10n.settingsFxEnteredBy(
                            who(r.enteredBy),
                            rateKindLabel(l10n, r.kind),
                          ),
                          trailing: Text(
                            formatRate(r.rate.rateString),
                            style: type.figureBody,
                          ),
                          onTap: _saving
                              ? null
                              : () => unawaited(_edit(r.day, today)),
                        ),
                      if (rates.isEmpty)
                        Padding(
                          padding: const EdgeInsetsDirectional.only(
                            top: XpSpace.s12,
                          ),
                          child: Text(
                            l10n.settingsFxHistoryEmpty,
                            style: type.meta.copyWith(
                              color: colors.inkSecondary,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: XpSpace.s12),
                  Text(
                    l10n.settingsFxEditNote,
                    style: type.meta.copyWith(color: colors.inkSecondary),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
