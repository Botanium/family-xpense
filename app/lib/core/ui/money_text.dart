import 'package:material_ui/material_ui.dart';

import 'package:xpense_app/core/theme/theme.dart';

/// The pieces of a formatted amount, so components can colour the decimals
/// apart from the whole part.
@immutable
class MoneyFigure {
  /// Creates a figure.
  const new({
    required this.sign,
    required this.currency,
    required this.whole,
    required this.fraction,
  });

  /// `+`, `−` (U+2212) or empty.
  final String sign;

  /// Currency code such as `IQD`, or empty.
  final String currency;

  /// Grouped whole part such as `12,480`, or a compact `16.3M`.
  final String whole;

  /// Decimal separator and fraction such as `.00`, or empty.
  final String fraction;

  /// The figure without the currency: `−1,240.00`.
  String get amount => '$sign$whole$fraction';

  /// The figure with the currency: `IQD 10,000`.
  String get withCurrency =>
      currency.isEmpty ? amount : '$sign$currency $whole$fraction';

  @override
  String toString() => withCurrency;
}

/// Formats integer minor units for display.
///
/// Integer arithmetic only: no `double`, and the number of decimals comes
/// from the currency's exponent (USD 2, IQD 0) rather than a hard-coded 100.
/// The exponent comes from `xpense_shared`'s currency table once WP-02 lands;
/// until then callers pass it.
abstract final class MoneyFormat {
  /// Minus sign used for negative amounts (U+2212, as on the artboards).
  static const String minus = '−';

  /// Splits [minorUnits] into a [MoneyFigure].
  ///
  /// [signed] adds `+` to positive amounts; negative amounts always show
  /// [minus].
  static MoneyFigure figure(
    int minorUnits, {
    required int exponent,
    String currency = '',
    bool signed = false,
  }) {
    assert(exponent >= 0, 'exponent must not be negative');
    final negative = minorUnits < 0;
    final abs = negative ? -minorUnits : minorUnits;
    final divisor = _pow10(exponent);
    final whole = abs ~/ divisor;
    final fraction = abs % divisor;
    return MoneyFigure(
      sign: negative
          ? minus
          : signed && abs > 0
          ? '+'
          : '',
      currency: currency,
      whole: group(whole),
      fraction: exponent == 0
          ? ''
          : '.${fraction.toString().padLeft(exponent, '0')}',
    );
  }

  /// Compact notation for figures too wide to show in full: `16.3M`.
  /// Rounds half up to one decimal and drops a trailing `.0`.
  static MoneyFigure compact(
    int minorUnits, {
    required int exponent,
    String currency = '',
    bool signed = false,
  }) {
    final negative = minorUnits < 0;
    final abs = negative ? -minorUnits : minorUnits;
    final whole = abs ~/ _pow10(exponent);
    const steps = [(1000000000000, 'T'), (1000000000, 'B'), (1000000, 'M')];
    var text = group(whole);
    for (final (unit, suffix) in [...steps, (1000, 'K')]) {
      if (whole >= unit) {
        final tenths = (whole * 10 + unit ~/ 2) ~/ unit;
        final intPart = tenths ~/ 10;
        final decimal = tenths % 10;
        text = decimal == 0
            ? '${group(intPart)}$suffix'
            : '${group(intPart)}.$decimal$suffix';
        break;
      }
    }
    return MoneyFigure(
      sign: negative
          ? minus
          : signed && abs > 0
          ? '+'
          : '',
      currency: currency,
      whole: text,
      fraction: '',
    );
  }

  /// Groups an integer by thousands with commas: `16300000` → `16,300,000`.
  static String group(int value) {
    final digits = value.abs().toString();
    final buffer = StringBuffer(value < 0 ? '-' : '');
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(',');
      buffer.write(digits[i]);
    }
    return buffer.toString();
  }

  /// Parses typed text such as `1,705.5` into minor units, or returns null
  /// when the text is not an amount or has more decimals than [exponent].
  static int? parseMinor(String text, {required int exponent}) {
    final cleaned = text.replaceAll(',', '').trim();
    final match = RegExp(r'^(\d+)(?:\.(\d*))?$').firstMatch(cleaned);
    if (match == null) return null;
    final fraction = match.group(2) ?? '';
    if (fraction.length > exponent) return null;
    final whole = int.parse(match.group(1)!);
    final frac = fraction.isEmpty
        ? 0
        : int.parse(fraction.padRight(exponent, '0'));
    return whole * _pow10(exponent) + frac;
  }

  static int _pow10(int exponent) {
    var result = 1;
    for (var i = 0; i < exponent; i++) {
      result *= 10;
    }
    return result;
  }
}

/// Size of a [MoneyText], mapped to the mono figure styles.
enum MoneyStyle {
  /// `figureHero`.
  hero,

  /// `figureLarge`.
  large,

  /// `figureMedium`.
  medium,

  /// `figureBody`.
  body,

  /// `figureSmall`.
  small,
}

/// Colour of a [MoneyText]. Colour never carries meaning alone: income also
/// shows a `+` sign.
enum MoneyTone {
  /// Ink.
  neutral,

  /// Income green, with a `+` sign.
  income,

  /// Secondary ink, for converted amounts and captions.
  secondary,
}

/// An amount in Geist Mono with tabular figures (DESIGN_SYSTEM 8.2).
class MoneyText extends StatelessWidget {
  /// Shows [minorUnits] in [currency] with [exponent] decimals.
  const new(
    this.minorUnits, {
    required this.exponent,
    this.currency = '',
    this.style = MoneyStyle.body,
    this.tone = MoneyTone.neutral,
    this.signed = false,
    this.converted,
    this.tertiaryDecimals = false,
    this.textAlign = TextAlign.start,
    super.key,
  });

  /// The amount in minor units.
  final int minorUnits;

  /// Decimal places of the currency (USD 2, IQD 0).
  final int exponent;

  /// Currency code shown before the figure; empty hides it.
  final String currency;

  /// Size.
  final MoneyStyle style;

  /// Colour.
  final MoneyTone tone;

  /// Whether positive amounts show `+`. Income always does.
  final bool signed;

  /// Optional converted line under the figure, such as `≈ USD 7.63`.
  final String? converted;

  /// Whether the decimals use tertiary ink, as on the hero balance.
  final bool tertiaryDecimals;

  /// Alignment of the figure and the converted line.
  final TextAlign textAlign;

  @override
  Widget build(BuildContext context) {
    final type = XpType.of(context);
    final colors = XpColors.of(context);
    final base = switch (style) {
      MoneyStyle.hero => type.figureHero,
      MoneyStyle.large => type.figureLarge,
      MoneyStyle.medium => type.figureMedium,
      MoneyStyle.body => type.figureBody,
      MoneyStyle.small => type.figureSmall,
    };
    final color = switch (tone) {
      MoneyTone.neutral => colors.ink,
      MoneyTone.income => colors.income,
      MoneyTone.secondary => colors.inkSecondary,
    };
    final figure = MoneyFormat.figure(
      minorUnits,
      exponent: exponent,
      currency: currency,
      signed: signed || tone == MoneyTone.income,
    );
    final head = figure.currency.isEmpty
        ? '${figure.sign}${figure.whole}'
        : '${figure.sign}${figure.currency} ${figure.whole}';
    final text = Text.rich(
      TextSpan(
        text: head,
        children: [
          if (figure.fraction.isNotEmpty)
            TextSpan(
              text: figure.fraction,
              style: tertiaryDecimals
                  ? TextStyle(color: colors.inkTertiary)
                  : null,
            ),
        ],
      ),
      style: base.copyWith(color: color),
      textAlign: textAlign,
      semanticsLabel: figure.withCurrency,
    );
    if (converted == null) return text;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: textAlign == TextAlign.end
          ? CrossAxisAlignment.end
          : CrossAxisAlignment.start,
      children: [
        text,
        Text(
          converted!,
          style: type.figureSmall.copyWith(color: colors.inkSecondary),
          textAlign: textAlign,
        ),
      ],
    );
  }
}
