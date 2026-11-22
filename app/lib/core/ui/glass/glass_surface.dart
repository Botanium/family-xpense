import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:material_ui/material_ui.dart';

import 'package:xpense_app/core/theme/theme.dart';
import 'package:xpense_app/core/ui/glass/glass_tier.dart';

/// The one widget that draws Liquid Glass (DESIGN_SYSTEM 6.2).
///
/// Glass is for controls only and never sits on glass. Features never import
/// `liquid_glass_widgets`; they use this widget, which picks the rendering
/// tier from the nearest [GlassScope] and the recipe from the theme:
///
/// * [GlassTier.premium] and [GlassTier.standard]: the package shader.
/// * [GlassTier.blur]: the package's shader-free `BackdropFilter` path.
/// * [GlassTier.solid]: an opaque `surface` fill with a hairline border.
///
/// Every tier keeps the same shape and the same outside-only drop shadow, and
/// draws the recipe's 1 pt border and top highlight on top, as the
/// prototype's CSS did. Increase Contrast raises the tint to 90 % and turns
/// the border to ink at 40 %. [GlassVariant.overMedia] is capped at the blur
/// tier, because glass over the camera preview (a platform view) can only be
/// drawn by a live backdrop filter.
class GlassSurface extends StatelessWidget {
  /// Creates a glass surface.
  const new({
    required this.variant,
    required this.child,
    this.shape = const StadiumBorder(),
    this.padding,
    this.overMedia = false,
    super.key,
  });

  /// Which recipe to use.
  final GlassVariant variant;

  /// The control drawn on the glass. Text and icons default to the recipe's
  /// content colour.
  final Widget child;

  /// Outline of the glass: [StadiumBorder], [CircleBorder],
  /// [RoundedRectangleBorder] or [RoundedSuperellipseBorder].
  final OutlinedBorder shape;

  /// Space between the glass edge and [child].
  final EdgeInsetsGeometry? padding;

  /// Whether this glass sits over camera media; for [GlassVariant.sheet] it
  /// switches the shadow to black (DESIGN_SYSTEM 6.1).
  final bool overMedia;

  /// Returns the content colour of the nearest glass, or ink when [context]
  /// is not on glass. Text styles carry an explicit colour, so components
  /// that draw text on glass read this rather than relying on inheritance.
  static Color contentColorOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_GlassContent>()?.color ??
      XpColors.of(context).ink;

  @override
  Widget build(BuildContext context) {
    final scopeTier = GlassScope.tierOf(context);
    final tier =
        (variant == GlassVariant.overMedia || overMedia) &&
            scopeTier.index > GlassTier.blur.index
        ? GlassTier.blur
        : scopeTier;
    final colors = XpColors.of(context);
    final glass = XpGlass.of(context);
    final highContrast = MediaQuery.highContrastOf(context);
    var recipe = glass.recipe(variant);
    if (highContrast) recipe = recipe.increasedContrast(colors.ink);
    final shadows = variant == GlassVariant.sheet && overMedia
        ? glass.sheetOverMediaShadows
        : recipe.shadows;
    final direction = Directionality.of(context);

    final isAccent = variant == GlassVariant.accent;
    final content = tier == GlassTier.solid
        ? (isAccent ? colors.inkOnAccent : colors.ink)
        : recipe.content;
    Widget inner = _GlassContent(
      color: content,
      child: IconTheme.merge(
        data: IconThemeData(color: content),
        child: DefaultTextStyle.merge(
          style: TextStyle(color: content),
          child: child,
        ),
      ),
    );
    if (padding != null) inner = Padding(padding: padding!, child: inner);

    final Widget body;
    final Color rimBorder;
    final Color rimHighlight;
    if (tier == GlassTier.solid) {
      rimBorder = isAccent ? colors.accent : colors.hairline;
      rimHighlight = colors.surface.withValues(alpha: 0);
      body = ClipPath(
        clipper: ShapeBorderClipper(shape: shape, textDirection: direction),
        child: ColoredBox(
          color: isAccent ? colors.accent : colors.surface,
          child: inner,
        ),
      );
    } else {
      rimBorder = recipe.border;
      rimHighlight = recipe.highlight;
      body = GlassAccessibilityScope(
        // Increase Contrast is handled by the recipe above; the package would
        // otherwise treat it as Reduce Transparency, which is tier 0's job.
        reduceTransparency: false,
        reduceMotion: MediaQuery.disableAnimationsOf(context),
        child: GlassContainer(
          useOwnLayer: true,
          quality: switch (tier) {
            GlassTier.premium => GlassQuality.premium,
            GlassTier.standard => GlassQuality.standard,
            GlassTier.blur || GlassTier.solid => GlassQuality.minimal,
          },
          shape: _liquidShape(shape, direction),
          clipBehavior: Clip.antiAlias,
          platformViewBackdrop: tier == GlassTier.blur && overMedia,
          settings: LiquidGlassSettings(
            glassColor: recipe.tint,
            blur: recipe.blur,
            saturation: recipe.saturation,
            thickness: recipe.refraction,
            shadowElevation: 0,
            shadow: const [],
          ),
          child: inner,
        ),
      );
    }

    return CustomPaint(
      painter: _OuterShadowPainter(
        shape: shape,
        shadows: shadows,
        direction: direction,
      ),
      foregroundPainter: _RimPainter(
        shape: shape,
        border: rimBorder,
        highlight: rimHighlight,
        borderWidth: tier == GlassTier.solid ? XpSpace.hairline(context) : 1,
        direction: direction,
      ),
      child: body,
    );
  }

  static LiquidShape _liquidShape(OutlinedBorder shape, TextDirection dir) {
    double radiusOf(BorderRadiusGeometry r) => r.resolve(dir).topLeft.x;
    return switch (shape) {
      // The package draws capsules as a rounded rectangle with a radius it
      // clamps to half the short side (its own GlassChip does the same).
      StadiumBorder() => const LiquidRoundedRectangle(borderRadius: 100),
      CircleBorder() => const LiquidOval(),
      RoundedSuperellipseBorder(:final borderRadius) =>
        LiquidRoundedSuperellipse(borderRadius: radiusOf(borderRadius)),
      RoundedRectangleBorder(:final borderRadius) => LiquidRoundedRectangle(
        borderRadius: radiusOf(borderRadius),
      ),
      _ => const LiquidRoundedRectangle(borderRadius: 0),
    };
  }
}

/// Shares one backdrop read between the glass surfaces below it, as SwiftUI's
/// `GlassEffectContainer` does. Wrap one screen's bars, not a navigator.
class XpGlassGroup extends StatelessWidget {
  /// Groups the glass in [child].
  const new({required this.child, this.enabled = true, super.key});

  /// The glass surfaces to group.
  final Widget child;

  /// Set false around glass that overlaps other grouped glass.
  final bool enabled;

  @override
  Widget build(BuildContext context) =>
      GlassBackdropGroup(enabled: enabled, child: child);
}

/// Paints drop shadows outside the shape only, like CSS `box-shadow`, so
/// they never darken the translucent glass from underneath.
class _OuterShadowPainter extends CustomPainter {
  const new({
    required this.shape,
    required this.shadows,
    required this.direction,
  });

  final OutlinedBorder shape;
  final List<BoxShadow> shadows;
  final TextDirection direction;

  @override
  void paint(Canvas canvas, Size size) {
    if (shadows.isEmpty) return;
    final rect = Offset.zero & size;
    final outline = shape.getOuterPath(rect, textDirection: direction);
    final outside = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(rect.inflate(200))
      ..addPath(outline, Offset.zero);
    canvas
      ..save()
      ..clipPath(outside);
    for (final shadow in shadows) {
      final spread = shape.getOuterPath(
        rect.shift(shadow.offset).inflate(shadow.spreadRadius),
        textDirection: direction,
      );
      canvas.drawPath(spread, shadow.toPaint());
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_OuterShadowPainter old) =>
      old.shape != shape ||
      old.direction != direction ||
      !_sameShadows(old.shadows, shadows);

  static bool _sameShadows(List<BoxShadow> a, List<BoxShadow> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// Paints the 1 pt border and the inset top highlight
/// (CSS `inset 0 1px 0 highlight`).
class _RimPainter extends CustomPainter {
  const new({
    required this.shape,
    required this.border,
    required this.highlight,
    required this.borderWidth,
    required this.direction,
  });

  final OutlinedBorder shape;
  final Color border;
  final Color highlight;
  final double borderWidth;
  final TextDirection direction;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final outline = shape.getOuterPath(rect, textDirection: direction);
    if (highlight.a > 0) {
      final lowered = shape.getOuterPath(
        rect.shift(const Offset(0, 1)),
        textDirection: direction,
      );
      final band = Path.combine(PathOperation.difference, outline, lowered);
      canvas.drawPath(band, Paint()..color = highlight);
    }
    if (border.a > 0 && borderWidth > 0) {
      final inset = shape.getOuterPath(
        rect.deflate(borderWidth / 2),
        textDirection: direction,
      );
      canvas.drawPath(
        inset,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = borderWidth
          ..color = border,
      );
    }
  }

  @override
  bool shouldRepaint(_RimPainter old) =>
      old.shape != shape ||
      old.border != border ||
      old.highlight != highlight ||
      old.borderWidth != borderWidth ||
      old.direction != direction;
}

/// One-time setup of the glass renderer: preloads the shaders so the first
/// glass frame does not flash. Call before `runApp`.
abstract final class GlassSetup {
  /// Preloads the glass shaders.
  static Future<void> initialize() => LiquidGlassWidgets.initialize();
}

class _GlassContent extends InheritedWidget {
  const new({required this.color, required super.child});

  final Color color;

  @override
  bool updateShouldNotify(_GlassContent old) => old.color != color;
}
