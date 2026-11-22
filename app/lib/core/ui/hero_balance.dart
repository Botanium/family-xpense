import 'package:material_ui/material_ui.dart';

import 'package:xpense_app/core/theme/theme.dart';
import 'package:xpense_app/core/ui/money_text.dart';

/// The one hero number on a screen (DESIGN_SYSTEM 8.2, Home artboard).
///
/// Label, currency mark, hero figure with tertiary decimals, and a delta
/// line. When the figure does not fit the width it steps down to
/// `figureLarge`, then to compact notation ("16.3M"). It never truncates and
/// never shrinks the text box.
class HeroBalance extends StatelessWidget {
  /// Creates a hero balance.
  const new({
    required this.label,
    required this.minorUnits,
    required this.exponent,
    required this.currencyMark,
    this.delta,
    this.deltaPositive = true,
    this.secondary,
    super.key,
  });

  /// Caption above the figure, such as "Household balance".
  final String label;

  /// The balance in minor units.
  final int minorUnits;

  /// Decimal places of the currency.
  final int exponent;

  /// Short mark before the figure: `$`, or `IQD`.
  final String currencyMark;

  /// Change line such as "+1,240.00 THIS MONTH"; upper-cased here.
  final String? delta;

  /// Whether the delta is a gain (income colour; the sign also says so).
  final bool deltaPositive;

  /// Trailing secondary part of the delta line, such as "IQD 16.3M".
  final String? secondary;

  @override
  Widget build(BuildContext context) {
    final type = XpType.of(context);
    final colors = XpColors.of(context);
    return Semantics(
      container: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: type.caption.copyWith(color: colors.inkSecondary)),
          const SizedBox(height: XpSpace.s2),
          LayoutBuilder(
            builder: (context, constraints) =>
                _figure(context, constraints.maxWidth),
          ),
          if (delta != null)
            Padding(
              padding: const EdgeInsetsDirectional.only(top: XpSpace.s2),
              child: Text.rich(
                TextSpan(
                  text: delta!.toUpperCase(),
                  style: TextStyle(
                    color: deltaPositive ? colors.income : colors.ink,
                  ),
                  children: [
                    if (secondary != null)
                      TextSpan(
                        text: ' · $secondary',
                        style: TextStyle(color: colors.inkSecondary),
                      ),
                  ],
                ),
                style: type.figureSmall,
              ),
            ),
        ],
      ),
    );
  }

  Widget _figure(BuildContext context, double maxWidth) {
    final type = XpType.of(context);
    final colors = XpColors.of(context);
    final scaler = MediaQuery.textScalerOf(context);
    final full = MoneyFormat.figure(minorUnits, exponent: exponent);
    final compact = MoneyFormat.compact(minorUnits, exponent: exponent);
    final steps = [
      (type.figureHero, type.figureMarkHero, full),
      (type.figureLarge, type.figureMarkLarge, full),
      (type.figureLarge, type.figureMarkLarge, compact),
    ];
    for (final (index, (style, markStyle, figure)) in steps.indexed) {
      final span = _span(figure, style, markStyle, colors);
      final painter = TextPainter(
        text: span,
        textDirection: Directionality.of(context),
        textScaler: scaler,
        maxLines: 1,
      )..layout();
      final fits = painter.width <= maxWidth;
      painter.dispose();
      if (fits || index == steps.length - 1) {
        return Text.rich(
          span,
          softWrap: true,
          semanticsLabel: '$currencyMark ${figure.amount}',
        );
      }
    }
    return const SizedBox.shrink();
  }

  TextSpan _span(
    MoneyFigure figure,
    TextStyle style,
    TextStyle markStyle,
    XpColors colors,
  ) => TextSpan(
    style: style.copyWith(color: colors.ink),
    children: [
      TextSpan(
        text: '$currencyMark ',
        style: markStyle.copyWith(color: colors.ink),
      ),
      TextSpan(text: '${figure.sign}${figure.whole}'),
      if (figure.fraction.isNotEmpty)
        TextSpan(
          text: figure.fraction,
          style: TextStyle(color: colors.inkTertiary),
        ),
    ],
  );
}
