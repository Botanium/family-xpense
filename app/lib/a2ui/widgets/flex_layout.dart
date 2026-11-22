import 'package:material_ui/material_ui.dart';
import 'package:xpense_app/core/theme/theme.dart';

/// Main-axis arrangement of [XpFlex], as the catalog's `justify` names it.
MainAxisAlignment justifyOf(String? justify) => switch (justify) {
  'center' => MainAxisAlignment.center,
  'end' => MainAxisAlignment.end,
  'spaceBetween' => MainAxisAlignment.spaceBetween,
  'spaceAround' => MainAxisAlignment.spaceAround,
  'spaceEvenly' => MainAxisAlignment.spaceEvenly,
  _ => MainAxisAlignment.start,
};

/// Cross-axis alignment of [XpFlex], as the catalog's `align` names it.
/// A row never stretches: surfaces have unbounded height.
CrossAxisAlignment alignOf(String? align, {required bool horizontal}) =>
    switch (align) {
      'start' => CrossAxisAlignment.start,
      'center' => CrossAxisAlignment.center,
      'end' => CrossAxisAlignment.end,
      _ when horizontal => CrossAxisAlignment.center,
      _ => CrossAxisAlignment.stretch,
    };

/// A column or row of children with Signal spacing. Rows give each child a
/// loose flexible share, so long text wraps instead of overflowing.
class XpFlex extends StatelessWidget {
  /// Creates a flex layout.
  const new({
    required this.direction,
    required this.children,
    this.justify,
    this.align,
    this.gap,
    super.key,
  });

  /// Vertical for `Column` and `List`, horizontal for `Row`.
  final Axis direction;

  /// The children, already built.
  final List<Widget> children;

  /// The catalog's `justify`.
  final String? justify;

  /// The catalog's `align`.
  final String? align;

  /// Space between children; 12 in a column, 8 in a row by default.
  final double? gap;

  @override
  Widget build(BuildContext context) {
    final horizontal = direction == Axis.horizontal;
    final space = gap ?? (horizontal ? XpSpace.s8 : XpSpace.s12);
    final spaced = <Widget>[
      for (final (i, child) in children.indexed) ...[
        if (i > 0)
          SizedBox(
            width: horizontal ? space : 0,
            height: horizontal ? 0 : space,
          ),
        if (horizontal) Flexible(child: child) else child,
      ],
    ];
    return Flex(
      direction: direction,
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: justifyOf(justify),
      crossAxisAlignment: alignOf(align, horizontal: horizontal),
      children: spaced,
    );
  }
}
