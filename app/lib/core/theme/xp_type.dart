import 'package:material_ui/material_ui.dart';

import 'package:xpense_app/core/theme/xp_colors.dart';

/// Bundled font families (DESIGN_SYSTEM 4). Registered in `pubspec.yaml`
/// with their OFL licence in `assets/fonts/OFL.txt`.
abstract final class XpFonts {
  /// Geist: all Latin text.
  static const String sans = 'Geist';

  /// Geist Mono: every figure and mono label.
  static const String mono = 'GeistMono';

  /// Largest text scale for tab labels, matching iOS tab bars. Every other
  /// style scales without a cap.
  static const double tabLabelMaxScale = 1.35;

  /// Text scale from which rows with a trailing figure stack the figure
  /// under the label (iOS accessibility sizes start near this).
  static const double stackRowsFromScale = 1.6;
}

/// Text styles of the Signal design system (DESIGN_SYSTEM 4).
///
/// Sizes are logical points and scale with `MediaQuery.textScaler`. Every
/// style carries `ink` as its colour; components switch to another slot with
/// `copyWith(color: …)`. Mono styles use tabular figures so columns align;
/// mono labels are upper-cased by the component, not in the string.
@immutable
class XpType extends ThemeExtension<XpType> {
  /// Creates the full set of styles. Use [XpType.from] instead.
  const new({
    required this.figureHero,
    required this.figureLarge,
    required this.figureMedium,
    required this.figureBody,
    required this.figureSmall,
    required this.figureMarkHero,
    required this.figureMarkLarge,
    required this.monoLabel,
    required this.screenTitle,
    required this.quote,
    required this.title,
    required this.body,
    required this.bodyStrong,
    required this.subhead,
    required this.caption,
    required this.meta,
    required this.button,
    required this.chip,
    required this.tabLabelActive,
    required this.tabLabelInactive,
  });

  /// Builds every style with [colors] `ink` as the default colour.
  factory from(XpColors colors) {
    TextStyle mono(double size, double line, FontWeight w, double tracking) =>
        TextStyle(
          inherit: false,
          fontFamily: XpFonts.mono,
          fontSize: size,
          height: line / size,
          fontWeight: w,
          letterSpacing: tracking,
          color: colors.ink,
          fontFeatures: const [FontFeature.tabularFigures()],
          textBaseline: TextBaseline.alphabetic,
          leadingDistribution: TextLeadingDistribution.even,
        );
    TextStyle sans(double size, double line, FontWeight w, double tracking) =>
        TextStyle(
          inherit: false,
          fontFamily: XpFonts.sans,
          fontSize: size,
          height: line / size,
          fontWeight: w,
          letterSpacing: tracking,
          color: colors.ink,
          textBaseline: TextBaseline.alphabetic,
          leadingDistribution: TextLeadingDistribution.even,
        );
    return XpType(
      figureHero: mono(50, 56, FontWeight.w300, -2.5),
      figureLarge: mono(38, 42, FontWeight.w300, -1.6),
      figureMedium: mono(28, 32, FontWeight.w300, -1.2),
      figureBody: mono(14, 20, FontWeight.w400, 0),
      figureSmall: mono(12, 16, FontWeight.w400, 0),
      figureMarkHero: mono(22, 28, FontWeight.w300, 0),
      figureMarkLarge: mono(17, 22, FontWeight.w300, 0),
      monoLabel: mono(11, 14, FontWeight.w400, 1.2),
      screenTitle: mono(12, 16, FontWeight.w400, 1.4),
      quote: sans(20, 27, FontWeight.w500, -0.3),
      title: sans(16, 22, FontWeight.w600, 0),
      body: sans(15, 22, FontWeight.w400, 0),
      bodyStrong: sans(15, 22, FontWeight.w500, 0),
      subhead: sans(14, 20, FontWeight.w500, 0),
      caption: sans(13, 18, FontWeight.w400, 0),
      meta: sans(12, 16, FontWeight.w400, 0),
      button: sans(15, 20, FontWeight.w600, 0),
      chip: sans(13, 18, FontWeight.w500, 0),
      tabLabelActive: sans(11, 13, FontWeight.w600, 0),
      tabLabelInactive: sans(11, 13, FontWeight.w500, 0),
    );
  }

  static final XpType _fallback = XpType.from(XpColors.light);

  /// Returns the text styles of the nearest theme.
  static XpType of(BuildContext context) {
    final type = Theme.of(context).extension<XpType>();
    assert(type != null, 'XpType missing: build the theme with buildAppTheme.');
    return type ?? _fallback;
  }

  /// Mono 300, 50/56, −2.5: the household balance.
  final TextStyle figureHero;

  /// Mono 300, 38/42, −1.6: slip amount.
  final TextStyle figureLarge;

  /// Mono 300, 28/32, −1.2: sheet and detail totals.
  final TextStyle figureMedium;

  /// Mono 400, 14/20: row amounts.
  final TextStyle figureBody;

  /// Mono 400, 12/16: converted amounts and captions.
  final TextStyle figureSmall;

  /// Mono 300, 22/28: the currency mark beside [figureHero].
  final TextStyle figureMarkHero;

  /// Mono 300, 17/22: the currency mark beside [figureLarge].
  final TextStyle figureMarkLarge;

  /// Mono 400, 11/14, +1.2, upper-case: "NOV 2026 · OUR HOME".
  final TextStyle monoLabel;

  /// Mono 400, 12/16, +1.4, upper-case: "ASK".
  final TextStyle screenTitle;

  /// Geist 500, 20/27, −0.3: what the user said.
  final TextStyle quote;

  /// Geist 600, 16/22: merchant, section title.
  final TextStyle title;

  /// Geist 400, 15/22: default text.
  final TextStyle body;

  /// Geist 500, 15/22: row titles.
  final TextStyle bodyStrong;

  /// Geist 500, 14/20: questions, ledger labels.
  final TextStyle subhead;

  /// Geist 400, 13/18: section labels, links.
  final TextStyle caption;

  /// Geist 400, 12/16: row subtitles.
  final TextStyle meta;

  /// Geist 600, 15/20: buttons.
  final TextStyle button;

  /// Geist 500, 13/18: chips.
  final TextStyle chip;

  /// Geist 600, 11/13: the active tab label.
  final TextStyle tabLabelActive;

  /// Geist 500, 11/13: inactive tab labels.
  final TextStyle tabLabelInactive;

  /// Tokens are fixed per theme, so a copy is the same value.
  @override
  XpType copyWith() => this;

  /// Theme changes cut rather than animate, so this snaps.
  @override
  XpType lerp(covariant XpType? other, double t) =>
      other == null || t < 0.5 ? this : other;
}
