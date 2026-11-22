import 'package:a2ui_flutter/a2ui_flutter.dart';
import 'package:material_ui/material_ui.dart';
import 'package:xpense_app/a2ui/catalog/schema_dsl.dart';
import 'package:xpense_app/a2ui/widgets/flex_layout.dart';
import 'package:xpense_app/core/theme/theme.dart';

/// `List(children, direction?, align?)` (A2UI_CATALOG 3.1). The template
/// form `{path, componentId}` renders one child per item of a data list.
final ComponentImplementation listComponent = ComponentImplementation(
  name: 'List',
  schema: componentSchema('List', [
    Prop.children('children', required: true),
    Prop.oneOf('direction', const ['vertical', 'horizontal']),
    Prop.oneOf('align', const ['start', 'center', 'end', 'stretch']),
  ]),
  builder: (context, node, props, buildChild) {
    final horizontal = props.string('direction') == 'horizontal';
    final flex = XpFlex(
      direction: horizontal ? Axis.horizontal : Axis.vertical,
      align: props.string('align'),
      gap: XpSpace.s8,
      children: [
        for (final child in props.children('children'))
          if (!child.isPlaceholder) buildChild(child),
      ],
    );
    return horizontal
        ? SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            primary: false,
            child: flex,
          )
        : flex;
  },
);
