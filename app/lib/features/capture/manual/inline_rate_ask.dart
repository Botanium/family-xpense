// WP-24: the inline ask for today's rate in Add manually (ARCHITECTURE
// 3.5, D-16). A cross-currency entry dated today, saved before anyone in
// the household entered today's rate, asks for it here. It is skippable:
// the entry then uses the latest rate and records that rate's date
// (`fx.asOf`), which the write path does on its own.
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';
import 'package:xpense_app/core/l10n/l10n.dart';
import 'package:xpense_app/core/theme/theme.dart';
import 'package:xpense_app/core/ui/ui.dart';
import 'package:xpense_app/data/fx_repository.dart';
import 'package:xpense_shared/xpense_shared.dart';

/// The rate [InlineRateAsk] offers to keep for [day], or null when the
/// form should not ask: [day] already has a rate, or the household has no
/// recent rate at all (then the write path asks for a typed one).
DailyRate? inlineRateAskFor(WidgetRef ref, String day) {
  final rates = ref.watch(fxRatesProvider).value;
  if (rates == null || rates.any((r) => r.day == day)) return null;
  final latest = ref.watch(latestDailyRateProvider).value;
  if (latest == null || latest.day.compareTo(day) > 0) return null;
  return latest;
}

/// "Today's dollar rate? 1,705 — Change · Use it", with what skipping
/// means. Answering saves [day]'s rate for the household.
class InlineRateAsk extends ConsumerStatefulWidget {
  /// Creates the ask for [day], offering to keep [latest].
  const new({required this.day, required this.latest, super.key});

  /// The household day being asked for (today).
  final String day;

  /// The most recent rate, kept by "Use it" and used when skipped.
  final DailyRate latest;

  @override
  ConsumerState<InlineRateAsk> createState() => _InlineRateAskState();
}

class _InlineRateAskState extends ConsumerState<InlineRateAsk> {
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
        .setRate(widget.day, rate);
    if (!mounted) return;
    setState(() {
      _saving = false;
      _failed = result is Err;
    });
  }

  Future<void> _change() async {
    final previous = widget.latest.rate;
    final typed = await showRateEntry(
      context: context,
      labels: rateEntryLabelsOf(context, previous: previous.rateString),
      initial: previous.rateString,
      needsConfirm: (typed) => switch (FxRate.forPair(FxPair.usdIqd, typed)) {
        Ok(:final value) => isRateJump(previous, value),
        Err() => false,
      },
    );
    if (typed == null || !mounted) return;
    await _save(typed);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final type = XpType.of(context);
    final colors = XpColors.of(context);
    final rate = formatRate(widget.latest.rate.rateString);
    final date = DateTime.tryParse(widget.latest.day);
    final locale = Localizations.localeOf(context).toLanguageTag();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        RatePrompt(
          question: l10n.settingsFxPromptQuestion,
          rate: rate,
          sameLabel: l10n.settingsFxInlineUse,
          changeLabel: l10n.settingsFxPromptChange,
          placement: RatePromptPlacement.inline,
          semanticLabel: l10n.settingsFxPromptSpoken(rate),
          onSame: () {
            if (!_saving) unawaited(_save(widget.latest.rate.rateString));
          },
          onChange: () {
            if (!_saving) unawaited(_change());
          },
        ),
        Text(
          l10n.settingsFxInlineSkipHint(
            rate,
            date == null
                ? widget.latest.day
                : DateFormat.MMMd(locale).format(date),
          ),
          style: type.meta.copyWith(color: colors.inkSecondary),
        ),
        if (_failed)
          Semantics(
            liveRegion: true,
            child: Text(
              l10n.settingsFxPromptFailed,
              style: type.meta.copyWith(color: colors.danger),
            ),
          ),
      ],
    );
  }
}
