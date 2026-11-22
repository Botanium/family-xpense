import 'package:material_ui/material_ui.dart';

import 'package:xpense_app/core/theme/primitives.dart';

/// Where a piece of glass is used; each has its own recipe (DESIGN_SYSTEM 6.1).
enum GlassVariant {
  /// The tab bar.
  control,

  /// Top round buttons and pills.
  button,

  /// The capture dock and the undo toast.
  dock,

  /// Bottom sheets.
  sheet,

  /// The orange Ask button.
  accent,

  /// Controls over the camera preview.
  overMedia,
}

/// One glass recipe: what the prototype's CSS drew with `backdrop-filter`,
/// tint, border, inset highlight and shadow.
@immutable
class GlassRecipe {
  /// Creates a recipe.
  const new({
    required this.tint,
    required this.blur,
    required this.saturation,
    required this.border,
    required this.highlight,
    required this.shadows,
    required this.content,
    required this.refraction,
  });

  /// Fill colour over the blurred backdrop, alpha included.
  final Color tint;

  /// Backdrop blur, as a Gaussian sigma in logical points (CSS `blur()`).
  final double blur;

  /// Backdrop saturation multiplier (CSS `saturate()`).
  final double saturation;

  /// One-point border around the shape.
  final Color border;

  /// Inset highlight along the top edge.
  final Color highlight;

  /// Drop shadows, outermost first.
  final List<BoxShadow> shadows;

  /// Colour of icons and text drawn on this glass.
  final Color content;

  /// Lens thickness for the shader tiers (premium and standard); larger
  /// bends the backdrop more at the rim. Proposed in WP-03, tuned in WP-S2.
  final double refraction;

  /// Returns this recipe as Increase Contrast draws it: tint opacity rises to
  /// at least 90 % and the border becomes [ink] at 40 % (DESIGN_SYSTEM 6.2).
  GlassRecipe increasedContrast(Color ink) => GlassRecipe(
    tint: tint.withValues(alpha: tint.a < 0.9 ? 0.9 : tint.a),
    blur: blur,
    saturation: saturation,
    border: ink.withValues(alpha: 0.4),
    highlight: highlight,
    shadows: shadows,
    content: content,
    refraction: refraction,
  );
}

/// Glass recipes per variant for one theme (DESIGN_SYSTEM 6.1).
@immutable
class XpGlass extends ThemeExtension<XpGlass> {
  /// Creates the recipe set.
  const new({required this.recipes, required this.sheetOverMediaShadows});

  /// Light theme recipes, from the prototype CSS. The control tint uses the
  /// 72 % fixed in iOS review item 6 so inactive tabs keep 4.5:1 over ink.
  static final XpGlass light = XpGlass(
    recipes: {
      GlassVariant.control: GlassRecipe(
        tint: XpPalette.stone97.withValues(alpha: 0.72),
        blur: 24,
        saturation: 1.6,
        border: _white(0.75),
        highlight: _white(0.95),
        shadows: [_shadow(XpPalette.ink04, 0.12, 12, 32)],
        content: XpPalette.ink04,
        refraction: 20,
      ),
      GlassVariant.button: GlassRecipe(
        tint: XpPalette.stone97.withValues(alpha: 0.60),
        blur: 20,
        saturation: 1.6,
        border: _white(0.75),
        highlight: _white(0.90),
        shadows: [_shadow(XpPalette.ink04, 0.06, 4, 14)],
        content: XpPalette.ink04,
        refraction: 16,
      ),
      GlassVariant.dock: GlassRecipe(
        tint: XpPalette.stone97.withValues(alpha: 0.62),
        blur: 26,
        saturation: 1.6,
        border: _white(0.80),
        highlight: _white(0.95),
        shadows: [_shadow(XpPalette.ink04, 0.14, 16, 40)],
        content: XpPalette.ink04,
        refraction: 22,
      ),
      GlassVariant.sheet: GlassRecipe(
        tint: XpPalette.stone92.withValues(alpha: 0.82),
        blur: 30,
        saturation: 1.6,
        border: _white(0.60),
        highlight: _white(0.90),
        shadows: [_shadow(XpPalette.ink04, 0.14, -10, 40)],
        content: XpPalette.ink04,
        refraction: 24,
      ),
      GlassVariant.accent: GlassRecipe(
        tint: XpPalette.orange55.withValues(alpha: 0.94),
        blur: 24,
        saturation: 1.6,
        border: _white(0.40),
        highlight: _white(0.50),
        shadows: [_shadow(XpPalette.orange55, 0.35, 12, 28)],
        content: XpPalette.ink04,
        refraction: 18,
      ),
      GlassVariant.overMedia: _overMedia,
    },
    sheetOverMediaShadows: [_shadow(XpPalette.black0, 0.35, -10, 40)],
  );

  /// Graphite dark theme recipes (DESIGN_SYSTEM 6.1, dark table).
  static final XpGlass dark = XpGlass(
    recipes: {
      GlassVariant.control: _darkControl(blur: 24, refraction: 20),
      GlassVariant.button: _darkControl(blur: 20, refraction: 16),
      GlassVariant.dock: _darkControl(blur: 26, refraction: 22),
      GlassVariant.sheet: GlassRecipe(
        tint: XpPalette.graphite11.withValues(alpha: 0.84),
        blur: 30,
        saturation: 1.6,
        border: _white(0.08),
        highlight: _white(0.12),
        shadows: [_shadow(XpPalette.black0, 0.55, -10, 40)],
        content: XpPalette.stone94,
        refraction: 24,
      ),
      GlassVariant.accent: GlassRecipe(
        tint: XpPalette.orange55.withValues(alpha: 0.94),
        blur: 24,
        saturation: 1.6,
        border: _white(0.30),
        highlight: _white(0.40),
        shadows: [_shadow(XpPalette.orange55, 0.30, 12, 28)],
        content: XpPalette.ink04,
        refraction: 18,
      ),
      GlassVariant.overMedia: _overMedia,
    },
    sheetOverMediaShadows: [_shadow(XpPalette.black0, 0.55, -10, 40)],
  );

  static final GlassRecipe _overMedia = GlassRecipe(
    tint: XpPalette.stone97.withValues(alpha: 0.18),
    blur: 20,
    saturation: 1.6,
    border: _white(0.22),
    highlight: _white(0.25),
    shadows: const [],
    content: XpPalette.stone97,
    refraction: 12,
  );

  static GlassRecipe _darkControl({
    required double blur,
    required double refraction,
  }) => GlassRecipe(
    tint: XpPalette.graphite14.withValues(alpha: 0.64),
    blur: blur,
    saturation: 1.6,
    border: _white(0.10),
    highlight: _white(0.14),
    shadows: [_shadow(XpPalette.black0, 0.50, 12, 32)],
    content: XpPalette.stone94,
    refraction: refraction,
  );

  static Color _white(double alpha) =>
      XpPalette.white100.withValues(alpha: alpha);

  static BoxShadow _shadow(Color c, double alpha, double dy, double blur) =>
      BoxShadow(
        color: c.withValues(alpha: alpha),
        offset: Offset(0, dy),
        blurRadius: blur,
      );

  /// Returns the glass recipes of the nearest theme.
  static XpGlass of(BuildContext context) {
    final glass = Theme.of(context).extension<XpGlass>();
    assert(
      glass != null,
      'XpGlass missing: build the theme with buildAppTheme.',
    );
    return glass ?? light;
  }

  /// Recipe per variant.
  final Map<GlassVariant, GlassRecipe> recipes;

  /// Sheet shadow when the sheet sits over the camera (black, not ink).
  final List<BoxShadow> sheetOverMediaShadows;

  /// Returns the recipe for [variant].
  GlassRecipe recipe(GlassVariant variant) => recipes[variant]!;

  /// Tokens are fixed per theme, so a copy is the same value.
  @override
  XpGlass copyWith() => this;

  /// Theme changes cut rather than animate, so this snaps.
  @override
  XpGlass lerp(covariant XpGlass? other, double t) =>
      other == null || t < 0.5 ? this : other;
}
