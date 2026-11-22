import 'package:material_ui/material_ui.dart';

import 'package:xpense_app/core/theme/primitives.dart';

/// Tier 2 colour slots of the Signal design system (DESIGN_SYSTEM 3.1).
///
/// Read with [XpColors.of]. Every slot is named by its role, never by its
/// hue, so the graphite dark theme and the Increase Contrast variants swap
/// values without touching a component.
@immutable
class XpColors extends ThemeExtension<XpColors> {
  /// Creates a full set of colour slots. Use [light], [dark],
  /// [lightHighContrast] or [darkHighContrast] rather than building one.
  const new({
    required this.brightness,
    required this.canvas,
    required this.surface,
    required this.surfaceSunken,
    required this.ink,
    required this.inkSecondary,
    required this.inkTertiary,
    required this.inkOnAccent,
    required this.hairline,
    required this.hairlineSoft,
    required this.hairlineWeight,
    required this.leader,
    required this.perforation,
    required this.accent,
    required this.accentHalo,
    required this.income,
    required this.saved,
    required this.loan,
    required this.danger,
    required this.primaryFill,
    required this.onPrimaryFill,
    required this.selectedFill,
    required this.onSelectedFill,
    required this.tabActiveWell,
    required this.tabInactive,
    required this.controlWell,
    required this.scanBackdrop,
    required this.onMedia,
    required this.receiptPaper,
    required this.receiptInk,
    required this.switchKnobOff,
    required this.categories,
  });

  /// Light theme as drawn on the Signal artboards.
  static const XpColors light = XpColors(
    brightness: Brightness.light,
    canvas: XpPalette.stone92,
    surface: XpPalette.stone97,
    surfaceSunken: XpPalette.stone89,
    ink: XpPalette.ink04,
    inkSecondary: XpPalette.stone39,
    inkTertiary: XpPalette.stone46,
    inkOnAccent: XpPalette.ink04,
    hairline: XpPalette.stone83,
    hairlineSoft: XpPalette.stone86,
    hairlineWeight: 1,
    leader: XpPalette.stone64,
    perforation: XpPalette.stone72,
    accent: XpPalette.orange55,
    accentHalo: Color.fromRGBO(255, 91, 26, XpAlpha.haloLight),
    income: XpPalette.green26,
    saved: XpPalette.blue58,
    loan: XpPalette.amber32,
    danger: XpPalette.red41,
    primaryFill: XpPalette.ink04,
    onPrimaryFill: XpPalette.stone97,
    selectedFill: XpPalette.ink04,
    onSelectedFill: XpPalette.stone97,
    tabActiveWell: Color.fromRGBO(11, 11, 12, XpAlpha.tabWellLight),
    tabInactive: XpPalette.stone24,
    controlWell: Color.fromRGBO(11, 11, 12, XpAlpha.controlWellLight),
    scanBackdrop: XpPalette.graphite11,
    onMedia: XpPalette.stone97,
    receiptPaper: XpPalette.paper94,
    receiptInk: XpPalette.ink04,
    switchKnobOff: XpPalette.stone97,
    categories: XpPalette.categoriesLight,
  );

  /// Graphite dark theme (DESIGN_SYSTEM 3.1, all values new).
  static const XpColors dark = XpColors(
    brightness: Brightness.dark,
    canvas: XpPalette.graphite09,
    surface: XpPalette.graphite12,
    surfaceSunken: XpPalette.graphite06,
    ink: XpPalette.stone94,
    inkSecondary: XpPalette.stone62,
    inkTertiary: XpPalette.stone45,
    inkOnAccent: XpPalette.ink04,
    hairline: XpPalette.graphite18,
    hairlineSoft: XpPalette.graphite15,
    hairlineWeight: 1,
    leader: XpPalette.graphite30,
    perforation: XpPalette.graphite23,
    accent: XpPalette.orange55,
    accentHalo: Color.fromRGBO(255, 91, 26, XpAlpha.haloDark),
    income: XpPalette.green53,
    saved: XpPalette.blue74,
    loan: XpPalette.amber58,
    danger: XpPalette.red75,
    primaryFill: XpPalette.stone94,
    onPrimaryFill: XpPalette.ink04,
    selectedFill: XpPalette.stone94,
    onSelectedFill: XpPalette.ink04,
    tabActiveWell: Color.fromRGBO(255, 255, 255, XpAlpha.tabWellDark),
    tabInactive: XpPalette.stone69,
    controlWell: Color.fromRGBO(255, 255, 255, XpAlpha.controlWellDark),
    scanBackdrop: XpPalette.black0,
    onMedia: XpPalette.stone97,
    receiptPaper: XpPalette.paper94,
    receiptInk: XpPalette.ink04,
    switchKnobOff: XpPalette.stone94,
    categories: XpPalette.categoriesDark,
  );

  /// Light theme with Increase Contrast on: darker secondary ink and
  /// hairlines drawn at twice the strength (DESIGN_SYSTEM 3.2).
  static final XpColors lightHighContrast = light._withContrast(
    inkSecondary: XpPalette.stone28,
  );

  /// Dark theme with Increase Contrast on.
  static final XpColors darkHighContrast = dark._withContrast(
    inkSecondary: XpPalette.stone77,
  );

  /// Returns the colour slots of the nearest theme.
  ///
  /// Asserts when the theme was not built by `buildAppTheme`, which attaches
  /// every Signal extension to both brightnesses.
  static XpColors of(BuildContext context) {
    final colors = Theme.of(context).extension<XpColors>();
    assert(colors != null, 'XpColors missing: use buildAppTheme.');
    return colors ?? light;
  }

  /// Light or dark; decides which glass recipes and shadows apply.
  final Brightness brightness;

  /// Screen background.
  final Color canvas;

  /// Slips, and the solid fallback for glass.
  final Color surface;

  /// Input wells and pressed rows.
  final Color surfaceSunken;

  /// Primary text, figures, icons and chart bars.
  final Color ink;

  /// Labels, meta and mono captions.
  final Color inkSecondary;

  /// Large-figure decimals only (3:1, large text).
  final Color inkTertiary;

  /// Icons on the orange accent.
  final Color inkOnAccent;

  /// Separators.
  final Color hairline;

  /// List row separators.
  final Color hairlineSoft;

  /// Hairline strength in physical pixels: 1, or 2 under Increase Contrast.
  final double hairlineWeight;

  /// Dotted leaders in ledger rows.
  final Color leader;

  /// Dashed slip rules and the switch's off track.
  final Color perforation;

  /// The signal orange: Ask, mic and live marks. Never text.
  final Color accent;

  /// Ring around the recording button.
  final Color accentHalo;

  /// Positive figures, the income dot and the "on-device" chip text.
  final Color income;

  /// Savings dot.
  final Color saved;

  /// Loans and debts dot, due markers.
  final Color loan;

  /// Destructive actions and over-budget states.
  final Color danger;

  /// Primary button fill (ink, never orange).
  final Color primaryFill;

  /// Primary button label.
  final Color onPrimaryFill;

  /// Selected chip fill.
  final Color selectedFill;

  /// Selected chip label.
  final Color onSelectedFill;

  /// Well behind the active tab.
  final Color tabActiveWell;

  /// Inactive tab icon and label.
  final Color tabInactive;

  /// Neutral round wells inside glass (dock side buttons).
  final Color controlWell;

  /// Camera screen background.
  final Color scanBackdrop;

  /// Content colour on glass over camera media (`overMedia`).
  final Color onMedia;

  /// Receipt preview paper.
  final Color receiptPaper;

  /// Text printed on receipt paper.
  final Color receiptInk;

  /// Switch knob when off (on, it is [onSelectedFill] over [selectedFill]).
  final Color switchKnobOff;

  /// Category colours `cat1` … `cat8`, used only as dots and chart segments.
  final List<Color> categories;

  /// Returns the colour for a category key such as `cat3`, falling back to
  /// [inkSecondary] for an unknown key so a bad key never hides a row.
  Color category(String colorKey) {
    final match = RegExp(r'^cat([1-8])$').firstMatch(colorKey);
    if (match == null) return inkSecondary;
    return categories[int.parse(match.group(1)!) - 1];
  }

  XpColors _withContrast({required Color inkSecondary}) => XpColors(
    brightness: brightness,
    canvas: canvas,
    surface: surface,
    surfaceSunken: surfaceSunken,
    ink: ink,
    inkSecondary: inkSecondary,
    inkTertiary: inkTertiary,
    inkOnAccent: inkOnAccent,
    hairline: hairline,
    hairlineSoft: hairlineSoft,
    hairlineWeight: hairlineWeight * 2,
    leader: leader,
    perforation: perforation,
    accent: accent,
    accentHalo: accentHalo,
    income: income,
    saved: saved,
    loan: loan,
    danger: danger,
    primaryFill: primaryFill,
    onPrimaryFill: onPrimaryFill,
    selectedFill: selectedFill,
    onSelectedFill: onSelectedFill,
    tabActiveWell: tabActiveWell,
    tabInactive: tabInactive,
    controlWell: controlWell,
    scanBackdrop: scanBackdrop,
    onMedia: onMedia,
    receiptPaper: receiptPaper,
    receiptInk: receiptInk,
    switchKnobOff: switchKnobOff,
    categories: categories,
  );

  /// Tokens are fixed per theme, so a copy is the same value.
  @override
  XpColors copyWith() => this;

  /// Theme changes cut rather than animate
  /// (`themeAnimationStyle: AnimationStyle.noAnimation`), so this snaps.
  @override
  XpColors lerp(covariant XpColors? other, double t) =>
      other == null || t < 0.5 ? this : other;
}

/// Opacities applied to colour slots by components.
abstract final class XpOpacity {
  /// Pressed controls dim to this, as iOS buttons do.
  static const double pressed = 0.55;

  /// Disabled controls.
  static const double disabled = 0.38;

  /// Chart bars before today (ink at 82 %, from the Home artboard).
  static const double chartBar = 0.82;

  /// Waveform bars not yet spoken.
  static const double waveQuiet = 0.3;

  /// Sheet grabber (ink at 20 %).
  static const double grabber = 0.2;

  /// Text selection highlight.
  static const double selection = 0.18;

  /// Modal barrier behind sheets.
  static const double barrier = 0.24;

  /// Lock overlay canvas over the blurred app.
  static const double lockCanvas = 0.72;

  /// Camera legibility scrim at its darkest.
  static const double cameraScrim = 0.35;
}
