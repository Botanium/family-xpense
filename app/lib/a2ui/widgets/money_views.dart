import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:xpense_app/a2ui/widgets/format.dart';
import 'package:xpense_app/core/l10n/l10n.dart';
import 'package:xpense_app/core/theme/theme.dart';
import 'package:xpense_app/core/ui/ui.dart';

/// Size of a [CatalogMoneyText], the catalog's `size`.
enum FigureSize {
  /// `figureHero`.
  hero,

  /// `figureLarge`.
  large,

  /// `figureBody`.
  body,

  /// `figureSmall`.
  small,
}

/// Colour role of a [CatalogMoneyText], the catalog's `tone`. Income also
/// shows a `+`, so colour never carries meaning alone.
enum FigureTone {
  /// Ink.
  ink,

  /// Income green, with a `+`.
  income,

  /// Secondary ink.
  muted,

  /// The loan colour.
  loan,

  /// The saved colour.
  saving,
}

/// Sign shown before a [CatalogMoneyText], the catalog's `sign`.
enum FigureSign {
  /// None (negative amounts still show `−`).
  none,

  /// `+`.
  plus,

  /// `−`.
  minus,
}

/// The catalog `MoneyText`: integer minor units formatted by the phone in
/// Geist Mono, with an optional converted line beneath ("≈ USD 6.58"). An
/// unknown currency shows a dash rather than guessing its decimals.
class CatalogMoneyText extends StatelessWidget {
  /// Creates an amount.
  const new({
    required this.amountMinor,
    required this.currency,
    this.size = FigureSize.body,
    this.sign = FigureSign.none,
    this.tone = FigureTone.ink,
    this.approx,
    this.textAlign = TextAlign.start,
    super.key,
  });

  /// The amount in minor units.
  final int amountMinor;

  /// Its currency code.
  final String? currency;

  /// Size.
  final FigureSize size;

  /// Sign.
  final FigureSign sign;

  /// Colour role.
  final FigureTone tone;

  /// The converted line, already formatted.
  final String? approx;

  /// Alignment.
  final TextAlign textAlign;

  @override
  Widget build(BuildContext context) {
    final type = XpType.of(context);
    final colors = XpColors.of(context);
    final style = switch (size) {
      FigureSize.hero => type.figureHero,
      FigureSize.large => type.figureLarge,
      FigureSize.body => type.figureBody,
      FigureSize.small => type.figureSmall,
    };
    final color = switch (tone) {
      FigureTone.ink => colors.ink,
      FigureTone.income => colors.income,
      FigureTone.muted => colors.inkSecondary,
      FigureTone.loan => colors.loan,
      FigureTone.saving => colors.saved,
    };
    final exponent = exponentOf(currency);
    final Widget figure;
    if (exponent == null) {
      figure = Semantics(
        label: context.l10n.a2uiAmountUnknown,
        excludeSemantics: true,
        child: Text(
          [?currency, '—'].join(' '),
          style: style.copyWith(color: color),
        ),
      );
    } else {
      final abs = amountMinor.abs();
      final parts = MoneyFormat.figure(
        sign == FigureSign.minus || amountMinor < 0 ? -abs : abs,
        exponent: exponent,
        currency: currency!,
        signed: sign == FigureSign.plus || tone == FigureTone.income,
      );
      figure = Text.rich(
        TextSpan(
          text: '${parts.sign}${parts.currency} ${parts.whole}',
          children: [
            if (parts.fraction.isNotEmpty) TextSpan(text: parts.fraction),
          ],
        ),
        style: style.copyWith(color: color),
        textAlign: textAlign,
        semanticsLabel: parts.withCurrency,
      );
    }
    if (approx == null) return figure;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: textAlign == TextAlign.end
          ? CrossAxisAlignment.end
          : CrossAxisAlignment.start,
      children: [
        figure,
        Text(
          approx!,
          style: type.figureSmall.copyWith(color: colors.inkSecondary),
          textAlign: textAlign,
        ),
      ],
    );
  }
}

/// Which bar of [CatalogMiniBars] uses the accent.
enum BarHighlight {
  /// Today's bar (the last).
  last,

  /// The highest bar.
  max,

  /// None.
  none,
}

/// The catalog `MiniBars`: the Signal thin daily chart, with the
/// highlighted bar in the accent and an optional caption. Screen readers
/// hear [description], never the bars.
class CatalogMiniBars extends StatelessWidget {
  /// Creates a chart.
  const new({
    required this.values,
    required this.description,
    this.caption,
    this.highlight = BarHighlight.last,
    super.key,
  });

  /// One non-negative value per day, oldest first.
  final List<int> values;

  /// Spoken summary.
  final String description;

  /// Caption under the chart, such as "avg 210/day".
  final String? caption;

  /// Highlighted bar.
  final BarHighlight highlight;

  @override
  Widget build(BuildContext context) {
    final colors = XpColors.of(context);
    final type = XpType.of(context);
    final highlighted = values.isEmpty
        ? null
        : switch (highlight) {
            BarHighlight.last => values.length - 1,
            BarHighlight.max => values.indexOf(values.reduce(math.max)),
            BarHighlight.none => null,
          };
    return Semantics(
      label: description,
      image: true,
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: XpSpace.miniBarsHeight,
            child: CustomPaint(
              painter: _BarsPainter(
                values: values,
                bar: colors.ink.withValues(alpha: XpOpacity.chartBar),
                accent: colors.accent,
                highlighted: highlighted,
                rtl: Directionality.of(context) == TextDirection.rtl,
              ),
            ),
          ),
          if (caption != null)
            Padding(
              padding: const EdgeInsetsDirectional.only(top: XpSpace.s6),
              child: Text(
                caption!.toUpperCase(),
                style: type.monoLabel.copyWith(color: colors.inkSecondary),
              ),
            ),
        ],
      ),
    );
  }
}

class _BarsPainter extends CustomPainter {
  const new({
    required this.values,
    required this.bar,
    required this.accent,
    required this.highlighted,
    required this.rtl,
  });

  final List<int> values;
  final Color bar;
  final Color accent;
  final int? highlighted;
  final bool rtl;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;
    final top = math.max(1, values.reduce(math.max));
    const gap = XpSpace.chartBarGap;
    final width = (size.width - gap * (values.length - 1)) / values.length;
    if (width <= 0) return;
    final paint = Paint()..isAntiAlias = true;
    for (var i = 0; i < values.length; i++) {
      final h = math.max(
        XpSpace.thinBar,
        size.height * math.max(0, values[i]) / top,
      );
      final left = (rtl ? values.length - 1 - i : i) * (width + gap);
      paint.color = i == highlighted ? accent : bar;
      canvas.drawRRect(
        RRect.fromLTRBR(
          left,
          size.height - h,
          left + width,
          size.height,
          const Radius.circular(XpRadius.chartBar),
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_BarsPainter old) =>
      old.bar != bar ||
      old.accent != accent ||
      old.highlighted != highlighted ||
      old.rtl != rtl ||
      !_same(old.values, values);

  static bool _same(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
