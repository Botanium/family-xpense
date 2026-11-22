import 'package:material_ui/material_ui.dart';

import 'package:xpense_app/core/theme/theme.dart';

/// Draws an [XpGlyph] in the ambient [IconTheme] colour.
///
/// Decorative by default: give [semanticLabel] only when the icon is the
/// sole content of something a screen reader should announce.
class XpIcon extends StatelessWidget {
  /// Creates an icon.
  const new(this.glyph, {this.size, this.color, this.semanticLabel, super.key});

  /// Which glyph.
  final XpGlyph glyph;

  /// Edge length in logical points; defaults to the [IconTheme] size.
  final double? size;

  /// Overrides the [IconTheme] colour.
  final Color? color;

  /// Label for screen readers; null keeps the icon out of the tree.
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final theme = IconTheme.of(context);
    final edge = size ?? theme.size ?? XpSpace.iconTop;
    final paint = color ?? theme.color ?? XpColors.of(context).ink;
    final mirror =
        glyph.directional && Directionality.of(context) == TextDirection.rtl;
    Widget icon = CustomPaint(
      size: Size.square(edge),
      painter: _GlyphPainter(glyph: glyph, color: paint, mirror: mirror),
    );
    icon = SizedBox.square(dimension: edge, child: icon);
    return semanticLabel == null
        ? ExcludeSemantics(child: icon)
        : Semantics(label: semanticLabel, image: true, child: icon);
  }
}

class _GlyphPainter extends CustomPainter {
  const new({required this.glyph, required this.color, required this.mirror});

  final XpGlyph glyph;
  final Color color;
  final bool mirror;

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.width / 24;
    canvas.save();
    if (mirror) {
      canvas
        ..translate(size.width, 0)
        ..scale(-1, 1);
    }
    canvas.scale(scale);
    final paint = Paint()
      ..color = color
      ..isAntiAlias = true
      ..style = glyph.filled ? PaintingStyle.fill : PaintingStyle.stroke
      ..strokeWidth = glyph.strokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas
      ..drawPath(glyphPath(glyph), paint)
      ..restore();
  }

  @override
  bool shouldRepaint(_GlyphPainter old) =>
      old.glyph != glyph || old.color != color || old.mirror != mirror;
}
