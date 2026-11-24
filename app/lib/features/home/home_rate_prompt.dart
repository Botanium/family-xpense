// WP-24: the daily rate prompt in Home's notice slot (ARCHITECTURE 3.5,
// D-16). Home owns the slot; this file owns what goes in it while the
// household has not entered today's USD/IQD rate.
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:xpense_app/core/l10n/l10n.dart';
import 'package:xpense_app/core/theme/theme.dart';
import 'package:xpense_app/core/ui/ui.dart';
import 'package:xpense_app/data/accounts_repository.dart';
import 'package:xpense_app/data/fx_repository.dart';
import 'package:xpense_app/features/home/home_providers.dart';
import 'package:xpense_shared/xpense_shared.dart';

/// What Home's notice slot asks about today's rate, or null.
///
/// Asked on the first open of each household-local day (the day rolls over
/// with [homeMonthProvider]) and until someone answers: once this member or
/// the partner has entered today's rate, it is gone on both phones, as one
/// answer covers the household. Only a household with accounts in both
/// currencies is asked.
final Provider<DailyRateAsk?> homeRateAskProvider =
    Provider.autoDispose<DailyRateAsk?>((ref) {
      final today = ref.watch(homeMonthProvider).today;
      final rates = ref.watch(fxRatesProvider).value;
      final accounts = ref.watch(accountsProvider).value;
      // Nothing is asked until both are known, so the prompt never flashes
      // up before the partner's answer has loaded.
      if (rates == null || accounts == null) return null;
      return dailyRateAsk(
        today: today,
        rates: rates,
        accountCurrencies: [
          for (final a in accounts)
            if (!a.archived) a.currency,
        ],
      );
    }, name: 'homeRateAskProvider');

/// The daily rate prompt (DESIGN_SYSTEM 8.2 `RatePrompt`): the previous
/// rate with **Same** and **Change**; a far-away typed rate is confirmed
/// first.
class HomeRatePrompt extends ConsumerStatefulWidget {
  /// Creates the prompt for [ask].
  const new({required this.ask, super.key});

  /// What is asked.
  final DailyRateAsk ask;

  @override
  ConsumerState<HomeRatePrompt> createState() => _HomeRatePromptState();
}

class _HomeRatePromptState extends ConsumerState<HomeRatePrompt> {
  bool _saving = false;
  bool _failed = false;

  Future<void> _save(String typed) async {
    final rate = FxRate.forPair(FxPair.usdIqd, typed).valueOrNull;
    if (rate == null || _saving) return;
    setState(() {
      _saving = true;
      _failed = false;
    });
    final result = await ref
        .read(fxRepositoryProvider)
        .setRate(widget.ask.today, rate);
    if (!mounted) return;
    setState(() {
      _saving = false;
      _failed = result is Err;
    });
    if (result is Ok) unawaited(XpHaptics.picked());
  }

  Future<void> _change() async {
    final previous = widget.ask.previous;
    final typed = await showRateEntry(
      context: context,
      labels: rateEntryLabelsOf(context, previous: previous?.rate.rateString),
      initial: previous?.rate.rateString ?? '',
      needsConfirm: previous == null
          ? null
          : (typed) => switch (FxRate.forPair(FxPair.usdIqd, typed)) {
              Ok(:final value) => isRateJump(previous.rate, value),
              Err() => false,
            },
    );
    if (typed == null || !mounted) return;
    await _save(typed);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final previous = widget.ask.previous;
    final prompt = previous == null
        ? NudgeRow(
            message: l10n.settingsFxPromptFirst,
            actionLabel: l10n.settingsFxPromptEnter,
            onAction: _saving ? null : () => unawaited(_change()),
          )
        : RatePrompt(
            question: l10n.settingsFxPromptQuestion,
            rate: formatRate(previous.rate.rateString),
            sameLabel: l10n.settingsFxPromptSame,
            changeLabel: l10n.settingsFxPromptChange,
            semanticLabel: l10n.settingsFxPromptSpoken(
              formatRate(previous.rate.rateString),
            ),
            onSame: () {
              if (!_saving) unawaited(_save(previous.rate.rateString));
            },
            onChange: () {
              if (!_saving) unawaited(_change());
            },
          );
    if (!_failed) return prompt;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        prompt,
        Padding(
          padding: const EdgeInsetsDirectional.only(top: XpSpace.s4),
          child: Semantics(
            liveRegion: true,
            child: Text(
              l10n.settingsFxPromptFailed,
              style: XpType.of(context).meta
                  .copyWith(color: XpColors.of(context).danger),
            ),
          ),
        ),
      ],
    );
  }
}
