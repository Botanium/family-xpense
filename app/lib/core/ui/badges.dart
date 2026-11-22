import 'package:material_ui/material_ui.dart';

import 'package:xpense_app/core/theme/theme.dart';

/// A coloured dot: ledger (7), unread (6) or nudge (18) (DESIGN_SYSTEM 8.1).
///
/// Colour never carries meaning alone, so a dot always sits next to a label;
/// it is excluded from semantics unless [semanticLabel] is given.
class Dot extends StatelessWidget {
  /// Creates a dot of [size] in [color].
  const new({
    required this.color,
    this.size = XpSpace.dotLedger,
    this.semanticLabel,
    super.key,
  });

  /// An unread marker: orange, 6 pt.
  factory unread(BuildContext context, {String? semanticLabel}) => Dot(
    color: XpColors.of(context).accent,
    size: XpSpace.dotUnread,
    semanticLabel: semanticLabel,
  );

  /// Fill colour.
  final Color color;

  /// Diameter.
  final double size;

  /// Spoken label, if the dot is the only carrier of its meaning.
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final dot = SizedBox.square(
      dimension: size,
      child: DecoratedBox(
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
    );
    return semanticLabel == null
        ? ExcludeSemantics(child: dot)
        : Semantics(label: semanticLabel, child: dot);
  }
}

/// Text badge marking a field the app guessed (DESIGN_SYSTEM 8.1). A text
/// badge, not a colour, so the meaning survives without colour vision.
class GuessedBadge extends StatelessWidget {
  /// Creates the badge with [label], such as "Guessed".
  const new({required this.label, super.key});

  /// Badge text; upper-cased here.
  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = XpColors.of(context);
    final type = XpType.of(context);
    return DecoratedBox(
      decoration: ShapeDecoration(
        shape: StadiumBorder(
          side: BorderSide(
            color: colors.perforation,
            width: XpSpace.hairline(context) * 2,
          ),
        ),
      ),
      child: Padding(
        padding: const EdgeInsetsDirectional.symmetric(
          horizontal: XpSpace.s6,
          vertical: XpSpace.s2,
        ),
        child: Text(
          label.toUpperCase(),
          style: type.monoLabel.copyWith(color: colors.inkSecondary),
        ),
      ),
    );
  }
}

/// A small ink pill with a count, such as unread notifications.
class CountBadge extends StatelessWidget {
  /// Creates a badge showing [count]; counts over 99 show "99+".
  const new({required this.count, this.semanticLabel, super.key});

  /// The number.
  final int count;

  /// Spoken label, such as "3 unread".
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final colors = XpColors.of(context);
    final type = XpType.of(context);
    final text = count > 99 ? '99+' : '$count';
    return Semantics(
      label: semanticLabel,
      excludeSemantics: semanticLabel != null,
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          minWidth: XpSpace.countBadge,
          minHeight: XpSpace.countBadge,
        ),
        child: DecoratedBox(
          decoration: ShapeDecoration(
            color: colors.primaryFill,
            shape: const StadiumBorder(),
          ),
          child: Padding(
            padding: const EdgeInsetsDirectional.symmetric(
              horizontal: XpSpace.s4,
            ),
            child: Center(
              widthFactor: 1,
              child: Text(
                text,
                style: type.figureSmall.copyWith(color: colors.onPrimaryFill),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
