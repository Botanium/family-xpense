import 'package:material_ui/material_ui.dart';
import 'package:xpense_app/a2ui/widgets/restricted_markdown.dart';
import 'package:xpense_app/core/theme/theme.dart';
import 'package:xpense_app/core/ui/ui.dart';

/// The catalog `Button`: the Signal stadium button (`XpButton`) around a
/// child component instead of a string, so a bound label stays live.
/// `primary` is the ink pill, never orange; `default` the outline;
/// `borderless` text only.
class CatalogButton extends StatelessWidget {
  /// Creates a button.
  const new({
    required this.label,
    required this.onPressed,
    this.kind = XpButtonKind.secondary,
    this.hint,
    super.key,
  });

  /// The label, usually a `Text` component.
  final Widget label;

  /// Tap handler; null disables the button.
  final VoidCallback? onPressed;

  /// Look.
  final XpButtonKind kind;

  /// Why the button is disabled, such as a failed check's message.
  final String? hint;

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
    final isText =
        kind == XpButtonKind.text || kind == XpButtonKind.destructive;
    final button = XpPressable(
      onPressed: onPressed,
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
            child: Center(
              heightFactor: 1,
              child: ButtonLabelStyle(
                style: type.button.copyWith(
                  color: fg,
                  fontWeight: kind == XpButtonKind.secondary
                      ? FontWeight.w500
                      : FontWeight.w600,
                ),
                child: label,
              ),
            ),
          ),
        ),
      ),
    );
    if (hint == null) return button;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        button,
        Padding(
          padding: const EdgeInsetsDirectional.only(top: XpSpace.s4),
          child: Text(
            hint!,
            style: type.meta.copyWith(color: colors.inkSecondary),
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );
  }
}
