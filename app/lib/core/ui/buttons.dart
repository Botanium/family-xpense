import 'package:material_ui/material_ui.dart';

import 'package:xpense_app/core/theme/theme.dart';
import 'package:xpense_app/core/ui/xp_icon.dart';
import 'package:xpense_app/core/ui/xp_pressable.dart';

/// Kinds of [XpButton] (DESIGN_SYSTEM 8.1). One primary per screen.
enum XpButtonKind {
  /// Ink fill: the screen's main action. Never orange.
  primary,

  /// Ink outline.
  secondary,

  /// Text only.
  text,

  /// Text in `danger`, for destructive actions.
  destructive,
}

/// Stadium button, 52 high (DESIGN_SYSTEM 8.1).
class XpButton extends StatelessWidget {
  /// Creates a button.
  const new({
    required this.label,
    required this.onPressed,
    this.kind = XpButtonKind.primary,
    this.glyph,
    this.expand = true,
    this.semanticLabel,
    super.key,
  });

  /// Creates a primary button.
  const new primary({
    required this.label,
    required this.onPressed,
    this.glyph,
    this.expand = true,
    this.semanticLabel,
    super.key,
  }) : kind = XpButtonKind.primary;

  /// Creates a secondary (outline) button.
  const new secondary({
    required this.label,
    required this.onPressed,
    this.glyph,
    this.expand = true,
    this.semanticLabel,
    super.key,
  }) : kind = XpButtonKind.secondary;

  /// Creates a text button.
  const new text({
    required this.label,
    required this.onPressed,
    this.glyph,
    this.expand = false,
    this.semanticLabel,
    super.key,
  }) : kind = XpButtonKind.text;

  /// Creates a destructive text button.
  const new destructive({
    required this.label,
    required this.onPressed,
    this.glyph,
    this.expand = false,
    this.semanticLabel,
    super.key,
  }) : kind = XpButtonKind.destructive;

  /// Button text.
  final String label;

  /// Tap handler; null disables the button.
  final VoidCallback? onPressed;

  /// Look of the button.
  final XpButtonKind kind;

  /// Optional leading icon.
  final XpGlyph? glyph;

  /// Whether the button fills the available width.
  final bool expand;

  /// Spoken label when it should differ from [label].
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final colors = XpColors.of(context);
    final type = XpType.of(context);
    final (fill, fg, side) = switch (kind) {
      XpButtonKind.primary => (colors.primaryFill, colors.onPrimaryFill, null),
      XpButtonKind.secondary => (
        null,
        colors.ink,
        BorderSide(color: colors.ink, width: XpSpace.hairline(context) * 2),
      ),
      XpButtonKind.text => (null, colors.ink, null),
      XpButtonKind.destructive => (null, colors.danger, null),
    };
    final weight = kind == XpButtonKind.secondary
        ? FontWeight.w500
        : FontWeight.w600;
    final content = Row(
      mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (glyph != null) ...[
          XpIcon(glyph!, size: XpSpace.iconTop, color: fg),
          const SizedBox(width: XpSpace.s8),
        ],
        Flexible(
          child: Text(
            label,
            style: type.button.copyWith(color: fg, fontWeight: weight),
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );
    final isText =
        kind == XpButtonKind.text || kind == XpButtonKind.destructive;
    return XpPressable(
      onPressed: onPressed,
      semanticLabel: semanticLabel,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          minHeight: isText ? XpSpace.minTarget : XpSpace.buttonHeight,
        ),
        child: DecoratedBox(
          decoration: ShapeDecoration(
            color: fill,
            shape: StadiumBorder(side: side ?? BorderSide.none),
          ),
          child: Padding(
            padding: EdgeInsetsDirectional.symmetric(
              horizontal: isText ? XpSpace.s4 : XpSpace.s24,
              vertical: XpSpace.s12,
            ),
            child: content,
          ),
        ),
      ),
    );
  }
}
